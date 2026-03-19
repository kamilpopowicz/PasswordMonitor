//
//  NotificationManager.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//


import Foundation
import Combine
import AppKit
import ServiceManagement

/// Zarządza powiadomieniami o wygaśnięciu hasła
@MainActor
public final class NotificationManager: ObservableObject {
    public enum CheckReason: String, Sendable {
        case automatic
        case scheduledTime
        case manual
        case menuOpen
    }

    public static let shared = NotificationManager()
    
    // MARK: - State
    
    /// Czy w danym dniu już pokazaliśmy powiadomienie (reset o północy)
    @Published private var hasShownNotificationToday = false

    /// Sprawdza czy powiadomienie już dziś pokazane (dla helpera)
    public var isNotificationShownToday: Bool {
        loadNotificationStateFromStore()
        return hasShownNotificationToday
    }

    /// Oznacza powiadomienie jako pokazane dzisiaj (używane przez helper)
    public func markNotificationAsShown() {
        hasShownNotificationToday = true
        persistNotificationState()
    }

    /// Resetuje dzienny licznik i snooze (np. po zmianie domeny).
    public func resetDailyNotificationState() {
        hasShownNotificationToday = false
        isSnoozed = false
        snoozeEndTime = nil
        persistNotificationState()
    }
    
    /// Czy powiadomienie jest obecnie w trybie snooze (odłożone)
    @Published private var isSnoozed = false
    @Published private var snoozeEndTime: Date?
    @Published public private(set) var latestPasswordInfo: PasswordInfo?
    @Published public private(set) var hasPerformedRefresh = false
    @Published public private(set) var isDomainAvailable = true

    private let automaticRefreshCooldown: TimeInterval = 15 * 60
    private var lastRefreshDate: Date?
    private var isRefreshInFlight = false
    private var isLiveRefreshInFlight = false
    private var liveRefreshToken: UUID?
    private var pendingSuccessCallbacks: [(PasswordInfo) -> Void] = []
    private var pendingErrorCallbacks: [(Error) -> Void] = []
    
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
    private var hasLoggedMissingExpirationDate = false
    private let helperBundleId = "popo.PasswordMonitorHelperApp"
    private let stateStore = NotificationStateStore.shared
    private var lastLogTimestamps: [String: Date] = [:]
    private var lastLoggedDaysRemaining: Int?

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
        guard isWithinQuietHours(now: now, defaults: defaults) else {
            return false
        }
        return reason != .manual && reason != .scheduledTime
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

        return reason != .manual
    }
    
    // MARK: - Initialization
    
    private init() {
        loadNotificationStateFromStore()
        setupMidnightReset()
        startCheckingForNotificationTime()
        loadCachedPasswordInfo()
    }

    private func loadNotificationStateFromStore() {
        hasShownNotificationToday = stateStore.hasShownNotificationToday
        isSnoozed = stateStore.isSnoozed
        snoozeEndTime = stateStore.snoozeEndTime
    }

    private func persistNotificationState() {
        stateStore.hasShownNotificationToday = hasShownNotificationToday
        stateStore.isSnoozed = isSnoozed
        stateStore.snoozeEndTime = snoozeEndTime
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

        if isRefreshInFlight {
            if let onResult {
                pendingSuccessCallbacks.append(onResult)
            }
            if let onError {
                pendingErrorCallbacks.append(onError)
            }
            return
        }

        let bypassCooldown = (reason != .automatic)
        guard shouldStartRefresh(reason: reason, bypassCooldown: bypassCooldown) else {
            deliverCachedInfo(reason: reason, onResult: onResult)
            return
        }

        if let onResult {
            pendingSuccessCallbacks.append(onResult)
        }
        if let onError {
            pendingErrorCallbacks.append(onError)
        }

        isRefreshInFlight = true

        let requestReason = reason
        Task.detached(priority: .userInitiated) {
            let result: Result<PasswordInfo, Error>
            do {
                let info = try ActiveDirectoryManager().getPasswordInfo(for: username)
                result = .success(info)
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                NotificationManager.shared.completeRefresh(with: result, reason: requestReason)
            }
        }
    }

    public func refreshPasswordStatusLive(
        reason: CheckReason,
        timeout: TimeInterval = 30,
        username: String = NSUserName(),
        shouldCheckNotification: Bool = true,
        onResult: ((PasswordInfo) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        Logger.shared.log("Live password status refresh requested (reason=\(reason.rawValue), username=\(username), timeout=\(timeout))")

        if isLiveRefreshInFlight {
            Logger.shared.log("Live refresh already in flight; returning cached info")
            _ = deliverCachedInfo(reason: reason, shouldCheckNotification: false, onResult: onResult)
            return
        }

        isLiveRefreshInFlight = true
        let token = UUID()
        liveRefreshToken = token

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.liveRefreshToken == token else { return }
                self.isLiveRefreshInFlight = false
                self.liveRefreshToken = nil
                Logger.shared.log("Live refresh timed out after \(timeout)s")
                self.handleLiveRefreshFallback(
                    reason: reason,
                    error: ADError.notConnected,
                    shouldCheckNotification: shouldCheckNotification,
                    onResult: onResult,
                    onError: onError
                )
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

        Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<PasswordInfo, Error>
            do {
                let info = try ActiveDirectoryManager().getPasswordInfo(for: username)
                result = .success(info)
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                NotificationManager.shared.finalizeLiveRefresh(
                    result: result,
                    token: token,
                    timeoutWorkItem: timeoutWorkItem,
                    reason: reason,
                    shouldCheckNotification: shouldCheckNotification,
                    onResult: onResult,
                    onError: onError
                )
            }
        }
    }

    @MainActor
    private func finalizeLiveRefresh(
        result: Result<PasswordInfo, Error>,
        token: UUID,
        timeoutWorkItem: DispatchWorkItem,
        reason: CheckReason,
        shouldCheckNotification: Bool,
        onResult: ((PasswordInfo) -> Void)?,
        onError: ((Error) -> Void)?
    ) {
        guard liveRefreshToken == token else { return }
        timeoutWorkItem.cancel()
        isLiveRefreshInFlight = false
        liveRefreshToken = nil
        completeLiveRefresh(
            with: result,
            reason: reason,
            shouldCheckNotification: shouldCheckNotification,
            onResult: onResult,
            onError: onError
        )
    }

    private func shouldStartRefresh(reason: CheckReason, bypassCooldown: Bool) -> Bool {
        guard !bypassCooldown else { return true }
        guard let last = lastRefreshDate else { return true }
        return Date().timeIntervalSince(last) >= automaticRefreshCooldown
    }

    @MainActor
    private func completeRefresh(with result: Result<PasswordInfo, Error>, reason: CheckReason) {
        isRefreshInFlight = false
        switch result {
        case .success(let info):
            latestPasswordInfo = info
            lastRefreshDate = Date()
            hasPerformedRefresh = true
            isDomainAvailable = !info.isFromCache
            updateExpirationDate(info.expiryDate)
            pendingSuccessCallbacks.forEach { $0(info) }
            pendingSuccessCallbacks.removeAll()
            pendingErrorCallbacks.removeAll()
            checkAndShowNotificationIfNeeded(reason: reason, allowLiveCheck: false)
        case .failure(let error):
            pendingErrorCallbacks.forEach { $0(error) }
            pendingErrorCallbacks.removeAll()
            pendingSuccessCallbacks.removeAll()
        }
    }

    @MainActor
    private func completeLiveRefresh(
        with result: Result<PasswordInfo, Error>,
        reason: CheckReason,
        shouldCheckNotification: Bool,
        onResult: ((PasswordInfo) -> Void)?,
        onError: ((Error) -> Void)?
    ) {
        switch result {
        case .success(let info):
            latestPasswordInfo = info
            lastRefreshDate = Date()
            hasPerformedRefresh = true
            isDomainAvailable = !info.isFromCache
            updateExpirationDate(info.expiryDate)
            onResult?(info)
            if shouldCheckNotification {
                checkAndShowNotificationIfNeeded(reason: reason, allowLiveCheck: false)
            }
        case .failure(let error):
            handleLiveRefreshFallback(
                reason: reason,
                error: error,
                shouldCheckNotification: shouldCheckNotification,
                onResult: onResult,
                onError: onError
            )
        }
    }

    @MainActor
    private func handleLiveRefreshFallback(
        reason: CheckReason,
        error: Error,
        shouldCheckNotification: Bool,
        onResult: ((PasswordInfo) -> Void)?,
        onError: ((Error) -> Void)?
    ) {
        hasPerformedRefresh = true
        isDomainAvailable = false
        if deliverCachedInfo(reason: reason, shouldCheckNotification: false, onResult: onResult) {
            if shouldCheckNotification {
                checkAndShowNotificationIfNeeded(reason: reason, allowLiveCheck: false)
            }
        } else {
            onError?(error)
        }
    }

    @discardableResult
    private func deliverCachedInfo(
        reason: CheckReason,
        shouldCheckNotification: Bool = true,
        onResult: ((PasswordInfo) -> Void)?
    ) -> Bool {
        guard let info = latestPasswordInfo ?? PasswordCache.shared.load() else {
            return false
        }
        latestPasswordInfo = info
        updateExpirationDate(info.expiryDate)
        if shouldCheckNotification {
            checkAndShowNotificationIfNeeded(reason: reason)
        }
        onResult?(info)
        return true
    }

    private func loadCachedPasswordInfo() {
        guard let cached = PasswordCache.shared.load() else { return }
        latestPasswordInfo = cached
        currentExpirationDate = cached.expiryDate
        hasLoggedMissingExpirationDate = false
    }

    public func refreshFromCache() {
        _ = deliverCachedInfo(reason: .automatic, onResult: nil)
    }

    /// Wczytuje cache tylko do wyświetlenia w UI (bez wywoływania alertów).
    public func refreshFromCacheForDisplay() {
        guard let cached = PasswordCache.shared.load() else { return }
        latestPasswordInfo = cached
        currentExpirationDate = cached.expiryDate
        hasLoggedMissingExpirationDate = false
    }
    
    /// Sprawdza czy powinniśmy pokazać powiadomienie (wywoływane cyklicznie)
    public func checkAndShowNotificationIfNeeded(reason: CheckReason = .automatic, allowLiveCheck: Bool = true) {
        guard shouldHandleNotifications(for: reason) else {
            Logger.shared.log("Skipping notification check in main app because helper is enabled (reason=\(reason.rawValue))")
            return
        }
        loadNotificationStateFromStore()
        let cachedInfo = PasswordCache.shared.load()
        if let cachedInfo {
            let shouldUpdateCache = latestPasswordInfo == nil
                || latestPasswordInfo?.expiryDate != cachedInfo.expiryDate
                || latestPasswordInfo?.lastSetDate != cachedInfo.lastSetDate
                || latestPasswordInfo?.isFromCache != cachedInfo.isFromCache
            if shouldUpdateCache {
                latestPasswordInfo = cachedInfo
                currentExpirationDate = cachedInfo.expiryDate
            }
        }

        if currentExpirationDate == nil && cachedInfo?.expiryDate == nil {
            if allowLiveCheck && reason != .automatic {
                refreshPasswordStatusLive(
                    reason: reason,
                    shouldCheckNotification: false,
                    onResult: { _ in
                        self.checkAndShowNotificationIfNeeded(reason: reason, allowLiveCheck: false)
                    },
                    onError: { _ in
                        self.logMissingExpirationDateOnce()
                    }
                )
                return
            }

            logMissingExpirationDateOnce()
            return
        }

        guard let expirationDate = currentExpirationDate ?? cachedInfo?.expiryDate else {
            logMissingExpirationDateOnce()
            return
        }
        
        guard !hasShownNotificationToday else {
            if shouldLog(key: "notification_already_shown", interval: 30 * 60) {
                Logger.shared.logLocalized("log_notification_already_shown_today")
            }
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
            if shouldLog(key: "notification_snoozed", interval: 10 * 60) {
                Logger.shared.logLocalized("log_notification_snooze_until %@", snoozeEndTime?.formatted() ?? "unknown")
                Logger.shared.log("Skipping notification because snooze is active (reason=\(reason.rawValue))")
            }
            return
        }

        if snoozeStillActive && reason == .manual {
            Logger.shared.log("Bypassing active snooze for notification (reason=\(reason.rawValue), snoozeUntil=\(snoozeEndTime?.formatted() ?? "unknown"))")
            isSnoozed = false
            snoozeEndTime = nil
            persistNotificationState()
        }

        let thresholdDays = Self.resolvedWarningThreshold()
        let daysRemaining = PasswordExpirationMath.daysRemaining(until: expirationDate, from: now)
        let isQuietHours = Self.isWithinQuietHours(now: now)
        Logger.shared.log("Notification check: reason=\(reason.rawValue), daysRemaining=\(daysRemaining), thresholdDays=\(thresholdDays), shownToday=\(hasShownNotificationToday), snoozed=\(isSnoozed), quietHours=\(isQuietHours)")

        if Self.isNotificationSuppressedForQuietHours(reason: reason, now: now) {
            if shouldLog(key: "notification_quiet_hours", interval: 30 * 60) {
                Logger.shared.log("Skipping notification during quiet hours (reason=\(reason.rawValue))")
            }
            return
        }

        // Jeśli hasło wygasa w progu ostrzeżenia, pokaż alert od razu (nie czekaj na godzinę).
        if Self.isWithinWarningThreshold(now: now, expirationDate: expirationDate, thresholdDays: thresholdDays) {
            if allowLiveCheck {
                refreshPasswordStatusLive(
                    reason: reason,
                    shouldCheckNotification: false,
                    onResult: { _ in
                        self.checkAndShowNotificationIfNeeded(reason: reason, allowLiveCheck: false)
                    },
                    onError: { _ in
                        self.checkAndShowNotificationIfNeeded(reason: reason, allowLiveCheck: false)
                    }
                )
                return
            }

            Logger.shared.logLocalized("log_notification_threshold_reached %d", daysRemaining)
            showNotification(passwordExpirationDate: expirationDate)
            return
        }

        if lastLoggedDaysRemaining != daysRemaining || shouldLog(key: "notification_below_threshold", interval: 60 * 60) {
            Logger.shared.log("Skipping notification; password expires in \(daysRemaining) days, threshold is \(thresholdDays)")
            lastLoggedDaysRemaining = daysRemaining
        }
    }
    
    /// Odłóż powiadomienie o określony czas
    func snooze(
        passwordExpirationDate: Date,
        allowDuringUrgent: Bool = false,
        overrideInterval: TimeInterval? = nil,
        shouldScheduleLiveRecheck: Bool = false
    ) {
        let hoursToExpiration = passwordExpirationDate.timeIntervalSinceNow / 3600
        
        // Nie można odłożyć jeśli hasło wygasa za < 24h
        guard hoursToExpiration > 24 || allowDuringUrgent else {
            Logger.shared.logLocalized("log_notification_snooze_blocked %d", Int(hoursToExpiration))
            return
        }

        let interval = overrideInterval ?? (3 * 3600)
        isSnoozed = true
        snoozeEndTime = Date().addingTimeInterval(interval)
        hasShownNotificationToday = false // Pozwól pokazać ponownie po snooze
        persistNotificationState()
        
        // Schowaj aktualne okienko
        currentAlert?.close()
        currentAlert = nil
        
        Logger.shared.logLocalized("log_notification_snooze_enabled %@", snoozeEndTime!.formatted())

        if shouldScheduleLiveRecheck {
            scheduleLiveRecheck(after: interval, reason: .manual)
        }
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
        loadNotificationStateFromStore()
        guard let endTime = snoozeEndTime else { return true }
        let expired = Date() >= endTime
        if expired {
            isSnoozed = false
            snoozeEndTime = nil
            persistNotificationState()
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
        persistNotificationState()
        let domainAvailable = isDomainAvailable
        
        let alert = PasswordExpirationAlert(
            expirationDate: passwordExpirationDate,
            isDomainAvailable: domainAvailable,
            onSnooze: { [weak self] in
                guard let self = self else { return }
                let useOfflineFlow = !domainAvailable
                self.snooze(
                    passwordExpirationDate: passwordExpirationDate,
                    allowDuringUrgent: useOfflineFlow,
                    overrideInterval: useOfflineFlow ? 3600 : nil,
                    shouldScheduleLiveRecheck: useOfflineFlow
                )
            },
            onChangePassword: { [weak self] in
                guard let self = self else { return }
                Logger.shared.logLocalized("log_notification_change_password_selected")
                PasswordChangeHelper.openSystemPasswordSettings()
                self.scheduleUrgentPasswordChangeVerification(expirationDate: passwordExpirationDate)
                self.dismissNotification()
            }
        )
        
        currentAlert = alert
        alert.show()
    }

    private func logMissingExpirationDateOnce() {
        guard !hasLoggedMissingExpirationDate else { return }
        Logger.shared.logLocalized("log_notification_no_expiration_date")
        hasLoggedMissingExpirationDate = true
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
    private func scheduleUrgentPasswordChangeVerification(expirationDate: Date) {
        let hoursToExpiration = expirationDate.timeIntervalSinceNow / 3600
        guard hoursToExpiration <= 24 else {
            return
        }
        scheduleLiveRecheck(after: 3600, reason: .manual)
    }

    private func scheduleLiveRecheck(after interval: TimeInterval, reason: CheckReason) {
        passwordChangeCheckTimer?.invalidate()

        passwordChangeCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in
                self.refreshPasswordStatusLive(
                    reason: reason,
                    shouldCheckNotification: true,
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
                self.resetDailyNotificationState()
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

    private func shouldHandleNotifications(for reason: CheckReason) -> Bool {
        if reason == .manual || reason == .menuOpen {
            return true
        }

        if Bundle.main.bundleIdentifier == helperBundleId {
            return true
        }

        let service = SMAppService.loginItem(identifier: helperBundleId)
        return service.status != .enabled
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

    private func shouldLog(key: String, interval: TimeInterval) -> Bool {
        let now = Date()
        if let last = lastLogTimestamps[key], now.timeIntervalSince(last) < interval {
            return false
        }
        lastLogTimestamps[key] = now
        return true
    }
    
    deinit {
        midnightTimer?.invalidate()
        checkTimer?.invalidate()
    }
}
