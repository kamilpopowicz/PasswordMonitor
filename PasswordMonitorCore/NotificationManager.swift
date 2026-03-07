//
//  NotificationManager.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//


import Foundation
import Combine
import AppKit

/// Zarządza powiadomieniami o wygaśnięciu hasła
@MainActor
public final class NotificationManager: ObservableObject {
    public enum CheckReason: String {
        case automatic
        case scheduledTime
        case manual
    }

    public static let shared = NotificationManager()
    
    // MARK: - State
    
    /// Czy w danym dniu już pokazaliśmy powiadomienie (reset o północy)
    @Published private var hasShownNotificationToday = false

    /// Sprawdza czy powiadomienie już dziś pokazane (dla helpera)
    public var isNotificationShownToday: Bool {
        return hasShownNotificationToday
    }

    /// Oznacza powiadomienie jako pokazane dzisiaj (używane przez helper)
    public func markNotificationAsShown() {
        hasShownNotificationToday = true
    }

    /// Resetuje dzienny licznik i snooze (np. po zmianie domeny).
    public func resetDailyNotificationState() {
        hasShownNotificationToday = false
        isSnoozed = false
        snoozeEndTime = nil
    }
    
    /// Czy powiadomienie jest obecnie w trybie snooze (odłożone)
    @Published private var isSnoozed = false
    @Published private var snoozeEndTime: Date?
    
    /// Aktualne okienko powiadomienia (jeśli widoczne)
    private var currentAlert: PasswordExpirationAlert?
    private var currentTestAlert: PasswordExpirationAlert?
    
    /// Timer do resetu o północy
    private var midnightTimer: Timer?
    
    /// Timer do sprawdzania czy nadszedł czas powiadomienia
    private var checkTimer: Timer?
    
    /// Data wygaśnięcia hasła (ustawiana z zewnątrz przez MainApp)
    private var currentExpirationDate: Date?
    
    /// Timer do jednorazowego sprawdzenia po zmianie hasła (30 minut)
    private var passwordChangeCheckTimer: Timer?

    static func resolvedWarningThreshold(from defaults: UserDefaults = .standard) -> Int {
        let configuredThreshold = defaults.integer(forKey: "warning_threshold")
        return configuredThreshold > 0 ? configuredThreshold : 7
    }

    static func isWithinWarningThreshold(
        now: Date,
        expirationDate: Date,
        thresholdDays: Int
    ) -> Bool {
        let daysRemaining = PasswordExpirationMath.daysRemaining(until: expirationDate, from: now)
        return daysRemaining <= thresholdDays
    }

    static func isWithinQuietHours(now: Date, defaults: UserDefaults = .standard) -> Bool {
        let startTime = (defaults.string(forKey: "quiet_hours_start")?.isEmpty == false)
            ? defaults.string(forKey: "quiet_hours_start")!
            : "18:01"
        let endTime = (defaults.string(forKey: "quiet_hours_end")?.isEmpty == false)
            ? defaults.string(forKey: "quiet_hours_end")!
            : "05:59"

        return HelperSchedule.isWithinQuietHours(
            date: now,
            startTime: startTime,
            endTime: endTime
        )
    }

    static func isNotificationSuppressedForQuietHours(
        reason: CheckReason,
        now: Date,
        defaults: UserDefaults = .standard
    ) -> Bool {
        isWithinQuietHours(now: now, defaults: defaults) && reason == .automatic
    }

    static func isNotificationSuppressedBySnooze(
        reason: CheckReason,
        isSnoozed: Bool,
        snoozeEndTime: Date?,
        now: Date = Date()
    ) -> Bool {
        guard isSnoozed, let snoozeEndTime else {
            return false
        }

        guard now < snoozeEndTime else {
            return false
        }

        return reason == .automatic
    }
    
    // MARK: - Initialization
    
    private init() {
        setupMidnightReset()
        startCheckingForNotificationTime()
    }
    
    // MARK: - Public API
    
    /// Aktualizuje datę wygaśnięcia hasła (wywoływane gdy zmieni się status hasła)
    public func updateExpirationDate(_ date: Date?) {
        currentExpirationDate = date
        Logger.shared.logLocalized("log_notification_expiration_updated %@", date?.formatted() ?? "nil")
        if let date {
            let thresholdDays = Self.resolvedWarningThreshold()
            let daysRemaining = PasswordExpirationMath.daysRemaining(until: date)
            Logger.shared.log("Notification state updated: daysRemaining=\(daysRemaining), thresholdDays=\(thresholdDays)")
        }
    }

    public func refreshPasswordStatus(
        reason: CheckReason,
        username: String = NSUserName(),
        onResult: ((PasswordInfo) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        Logger.shared.log("Password status refresh requested (reason=\(reason.rawValue), username=\(username))")

        Task.detached(priority: .userInitiated) {
            let manager = ActiveDirectoryManager()

            do {
                let info = try manager.getPasswordInfo(for: username)
                await MainActor.run {
                    self.updateExpirationDate(info.expiryDate)
                    onResult?(info)
                    self.checkAndShowNotificationIfNeeded(reason: reason)
                }
            } catch {
                await MainActor.run {
                    onError?(error)
                }
            }
        }
    }
    
    /// Sprawdza czy powinniśmy pokazać powiadomienie (wywoływane cyklicznie)
    public func checkAndShowNotificationIfNeeded(reason: CheckReason = .automatic) {
        guard let expirationDate = currentExpirationDate else {
            Logger.shared.logLocalized("log_notification_no_expiration_date")
            return
        }
        
        guard !hasShownNotificationToday else {
            Logger.shared.logLocalized("log_notification_already_shown_today")
            return
        }
        
        let now = Date()
        let snoozeStillActive = !hasSnoozeExpired()

        if Self.isNotificationSuppressedBySnooze(
            reason: reason,
            isSnoozed: isSnoozed,
            snoozeEndTime: snoozeEndTime,
            now: now
        ) {
            Logger.shared.logLocalized("log_notification_snooze_until %@", snoozeEndTime?.formatted() ?? "unknown")
            Logger.shared.log("Skipping notification because snooze is active (reason=\(reason.rawValue))")
            return
        }

        if snoozeStillActive && reason != .automatic {
            Logger.shared.log("Bypassing active snooze for notification (reason=\(reason.rawValue), snoozeUntil=\(snoozeEndTime?.formatted() ?? "unknown"))")
            isSnoozed = false
            snoozeEndTime = nil
        }

        let thresholdDays = Self.resolvedWarningThreshold()
        let daysRemaining = PasswordExpirationMath.daysRemaining(until: expirationDate, from: now)
        let isQuietHours = Self.isWithinQuietHours(now: now)
        Logger.shared.log("Notification check: reason=\(reason.rawValue), daysRemaining=\(daysRemaining), thresholdDays=\(thresholdDays), shownToday=\(hasShownNotificationToday), snoozed=\(isSnoozed), quietHours=\(isQuietHours)")

        if Self.isNotificationSuppressedForQuietHours(reason: reason, now: now) {
            Logger.shared.log("Skipping notification during quiet hours (reason=\(reason.rawValue))")
            return
        }

        // Jeśli hasło wygasa w progu ostrzeżenia, pokaż alert od razu (nie czekaj na godzinę).
        if Self.isWithinWarningThreshold(now: now, expirationDate: expirationDate, thresholdDays: thresholdDays) {
            Logger.shared.logLocalized("log_notification_threshold_reached %d", daysRemaining)
            showNotification(passwordExpirationDate: expirationDate)
            return
        }

        Logger.shared.log("Skipping notification; password expires in \(daysRemaining) days, threshold is \(thresholdDays)")
    }
    
    /// Odłóż powiadomienie o 3 godziny
    func snooze(passwordExpirationDate: Date) {
        let hoursToExpiration = passwordExpirationDate.timeIntervalSinceNow / 3600
        
        // Nie można odłożyć jeśli hasło wygasa za < 24h
        guard hoursToExpiration > 24 else {
            Logger.shared.logLocalized("log_notification_snooze_blocked %d", Int(hoursToExpiration))
            return
        }
        
        isSnoozed = true
        snoozeEndTime = Date().addingTimeInterval(3 * 3600) // +3h
        hasShownNotificationToday = false // Pozwól pokazać ponownie po snooze
        
        // Schowaj aktualne okienko
        currentAlert?.close()
        currentAlert = nil
        
        Logger.shared.logLocalized("log_notification_snooze_enabled %@", snoozeEndTime!.formatted())
    }
    
    /// Ręczne zamknięcie powiadomienia (np. po kliknięciu "Zmień hasło")
    func dismissNotification() {
        currentAlert?.close()
        currentAlert = nil
        Logger.shared.logLocalized("log_notification_closed_by_user")
    }

    func dismissTestNotification() {
        currentTestAlert?.close()
        currentTestAlert = nil
        Logger.shared.log("Test notification closed")
    }
    
    // MARK: - Private Methods
    
    /// Sprawdza czy snooze się skończył
    private func hasSnoozeExpired() -> Bool {
        guard let endTime = snoozeEndTime else { return true }
        let expired = Date() >= endTime
        if expired {
            isSnoozed = false
            snoozeEndTime = nil
        }
        return expired
    }
    
    /// Pokazuje okienko powiadomienia
    private func showNotification(passwordExpirationDate: Date) {
        guard currentAlert == nil else {
            Logger.shared.logLocalized("log_notification_window_already_open")
            return
        }
        
        hasShownNotificationToday = true
        
        let alert = PasswordExpirationAlert(
            expirationDate: passwordExpirationDate,
            onSnooze: { [weak self] in
                guard let self = self else { return }
                self.snooze(passwordExpirationDate: passwordExpirationDate)
            },
            onChangePassword: { [weak self] in
                guard let self = self else { return }
                Logger.shared.logLocalized("log_notification_change_password_selected")
                PasswordChangeHelper.openSystemPasswordSettings()
                self.schedulePasswordChangeVerification()
                self.dismissNotification()
            }
        )
        
        currentAlert = alert
        alert.show()
    }
    
    /// Pokazuje testowe powiadomienie, bez zmiany stanu (nie rusza daty, snooze ani flagi 'już pokazane')
    public func showTestNotification(expirationDate: Date) {
        guard currentTestAlert == nil else {
            Logger.shared.log("Test notification window already open")
            return
        }

        let alert = PasswordExpirationAlert(
            expirationDate: expirationDate,
            mode: .test,
            onSnooze: { [weak self] in
                self?.dismissTestNotification()
            },
            onChangePassword: { [weak self] in
                Logger.shared.logLocalized("log_notification_test_change_password_selected")
                // TODO: Otwórz panel zmiany hasła systemowego
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/TouchID.prefPane"))
                self?.dismissTestNotification()
            },
            onEndTest: { [weak self] in
                self?.dismissTestNotification()
            }
        )
        currentTestAlert = alert
        alert.show()
    }
    
    /// Po kliknięciu „Zmień hasło” zaplanuj sprawdzenie za 30 minut,
    /// czy data wygaśnięcia hasła uległa zmianie.
    private func schedulePasswordChangeVerification() {
        guard let previousExpiry = currentExpirationDate else {
            Logger.shared.logLocalized("log_notification_no_current_expiration")
            return
        }

        // Anuluj ewentualny poprzedni timer
        passwordChangeCheckTimer?.invalidate()

        let interval: TimeInterval = 30 * 60 // 30 minut
        passwordChangeCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in
                self.refreshPasswordStatus(
                    reason: .automatic,
                    onResult: { info in
                        let newExpiry = info.expiryDate

                        if newExpiry > previousExpiry {
                            Logger.shared.logLocalized("log_notification_password_changed %@", String(describing: newExpiry))
                            self.hasShownNotificationToday = false
                        } else {
                            Logger.shared.logLocalized("log_notification_password_unchanged %@", String(describing: newExpiry))
                        }
                    },
                    onError: { error in
                        Logger.shared.logLocalized("log_notification_recheck_error %@", String(describing: error))
                    }
                )
            }
        }

        Logger.shared.logLocalized("log_notification_recheck_scheduled")
    }

    
    /// Ustawia timer resetujący flagę o północy
    private func setupMidnightReset() {
        let calendar = Calendar.current
        let now = Date()
        
        // Następna północ
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.day! += 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        
        guard let midnight = calendar.date(from: components) else { return }
        let interval = midnight.timeIntervalSince(now)
        
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        Logger.shared.logLocalized("log_notification_midnight_reset_in %d %d", hours, minutes)
        
        // Timer jednorazowy do północy
        midnightTimer?.invalidate()
        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in
                Logger.shared.logLocalized("log_notification_midnight_reset")
                self.hasShownNotificationToday = false
                self.isSnoozed = false
                self.snoozeEndTime = nil
                self.setupMidnightReset()
            }
        }
    }
    
    /// Rozpoczyna sprawdzanie co minutę czy nadszedł czas powiadomienia
    private func startCheckingForNotificationTime() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                let now = Date()
                let reason: CheckReason = self.isScheduledNotificationMoment(now) ? .scheduledTime : .automatic
                self.checkAndShowNotificationIfNeeded(reason: reason)
            }
        }

        
        // Sprawdź od razu przy starcie (na wypadek gdybyśmy uruchomili się po czasie)
        checkAndShowNotificationIfNeeded(reason: .automatic)
    }

    private func isScheduledNotificationMoment(_ now: Date) -> Bool {
        let configuredTime = (UserDefaults.standard.string(forKey: "notification_hour")?.isEmpty == false)
            ? UserDefaults.standard.string(forKey: "notification_hour")!
            : "09:00"

        let parts = configuredTime.split(separator: ":")
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1])
        else {
            return false
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        return components.hour == hour && components.minute == minute
    }
    
    deinit {
        midnightTimer?.invalidate()
        checkTimer?.invalidate()
    }
}
