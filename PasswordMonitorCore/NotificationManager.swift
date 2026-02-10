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
    
    /// Timer do resetu o północy
    private var midnightTimer: Timer?
    
    /// Timer do sprawdzania czy nadszedł czas powiadomienia
    private var checkTimer: Timer?
    
    /// Data wygaśnięcia hasła (ustawiana z zewnątrz przez MainApp)
    private var currentExpirationDate: Date?
    
    /// Timer do jednorazowego sprawdzenia po zmianie hasła (30 minut)
    private var passwordChangeCheckTimer: Timer?
    
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
    }
    
    /// Sprawdza czy powinniśmy pokazać powiadomienie (wywoływane cyklicznie)
    public func checkAndShowNotificationIfNeeded() {
        guard let expirationDate = currentExpirationDate else {
            Logger.shared.logLocalized("log_notification_no_expiration_date")
            return
        }
        
        guard !hasShownNotificationToday else {
            Logger.shared.logLocalized("log_notification_already_shown_today")
            return
        }
        
        guard !isSnoozed || hasSnoozeExpired() else {
            Logger.shared.logLocalized("log_notification_snooze_until %@", snoozeEndTime?.formatted() ?? "unknown")
            return
        }
        
        let notificationTime = getNotificationTime()
        let now = Date()

        let warningThresholdDays = UserDefaults.standard.integer(forKey: "warning_threshold")
        let thresholdDays = warningThresholdDays > 0 ? warningThresholdDays : 7
        let daysRemaining = Calendar.current.dateComponents([.day], from: now, to: expirationDate).day ?? 0

        // Jeśli hasło wygasa w progu ostrzeżenia, pokaż alert od razu (nie czekaj na godzinę).
        if daysRemaining <= thresholdDays {
            Logger.shared.logLocalized("log_notification_threshold_reached %d", daysRemaining)
            showNotification(passwordExpirationDate: expirationDate)
            return
        }
        
        // Czy nadszedł czas powiadomienia (lub minął i komputer był uśpiony)?
        if now >= notificationTime {
            Logger.shared.logLocalized("log_notification_time_reached %@", String(describing: expirationDate))
            showNotification(passwordExpirationDate: expirationDate)
        } else {
            let diff = notificationTime.timeIntervalSince(now)
            Logger.shared.logLocalized("log_notification_minutes_remaining %d", Int(diff / 60))
        }
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
    
    // MARK: - Private Methods
    
    /// Zwraca dzisiejszą datę z godziną z ustawień
    private func getNotificationTime() -> Date {
        let defaults = UserDefaults.standard
        let timeString = defaults.string(forKey: "notification_hour") ?? "09:00"
        
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        
        let timeParts = timeString.split(separator: ":")
        components.hour = Int(timeParts[0]) ?? 9
        components.minute = Int(timeParts[1]) ?? 0
        components.second = 0
        
        return calendar.date(from: components) ?? Date()
    }
    
    /// Sprawdza czy snooze się skończył
    private func hasSnoozeExpired() -> Bool {
        guard let endTime = snoozeEndTime else { return true }
        return Date() >= endTime
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
        let alert = PasswordExpirationAlert(
            expirationDate: expirationDate,
            onSnooze: { },
            onChangePassword: { [weak self] in
                Logger.shared.logLocalized("log_notification_test_change_password_selected")
                // TODO: Otwórz panel zmiany hasła systemowego
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/TouchID.prefPane"))
                self?.dismissNotification()
            }
        )
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
            Task.detached {
                let manager = ActiveDirectoryManager()
                let username = NSUserName()

                do {
                    let info = try manager.getPasswordInfo(for: username)
                    await MainActor.run {
                        let newExpiry = info.expiryDate

                        if newExpiry > previousExpiry {
                            Logger.shared.logLocalized("log_notification_password_changed %@", String(describing: newExpiry))
                            self.updateExpirationDate(newExpiry)
                            self.hasShownNotificationToday = false
                        } else {
                            Logger.shared.logLocalized("log_notification_password_unchanged %@", String(describing: newExpiry))
                        }
                    }
                } catch {
                    await MainActor.run {
                        Logger.shared.logLocalized("log_notification_recheck_error %@", String(describing: error))
                    }
                }
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
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
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
        checkTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in
                self.checkAndShowNotificationIfNeeded()
            }
        }

        
        // Sprawdź od razu przy starcie (na wypadek gdybyśmy uruchomili się po czasie)
        checkAndShowNotificationIfNeeded()
    }
    
    deinit {
        midnightTimer?.invalidate()
        checkTimer?.invalidate()
    }
}
