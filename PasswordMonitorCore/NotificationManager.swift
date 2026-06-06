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
        case checkNow
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
        lastPresentedNotificationExpirationDate = nil
        lastPresentedNotificationAt = nil
        lastHandledScheduledNotificationSlotID = nil
        persistNotificationState()
        stateStore.clearNotificationDeliveryClaim()
        stateStore.clearScheduledNotificationEventClaim()
    }
    
    /// Czy powiadomienie jest obecnie w trybie snooze (odłożone)
    @Published private var isSnoozed = false
    @Published private var snoozeEndTime: Date?
    @Published public private(set) var latestPasswordInfo: PasswordInfo?
    @Published public private(set) var hasPerformedRefresh = false
    @Published public private(set) var isDomainAvailable = false

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

    /// Ostatni slot scheduledTime obsłużony w tej instancji procesu.
    private var lastHandledScheduledNotificationSlotID: String?
    
    /// Data wygaśnięcia hasła (ustawiana z zewnątrz przez MainApp)
    private var currentExpirationDate: Date?
    
    /// Timer do jednorazowego sprawdzenia po zmianie hasła (30 minut)
    private var passwordChangeCheckTimer: Timer?
    private var hasLoggedMissingExpirationDate = false
    private let helperBundleId = "popo.PasswordMonitorHelperApp"
    private let mainAppBundleId = "popo.PasswordMonitor"
    private let stateStore = NotificationStateStore.shared
    private var lastLogTimestamps: [String: Date] = [:]
    private var lastLoggedDaysRemaining: Int?
    private var lastPresentedNotificationExpirationDate: Date?
    private var lastPresentedNotificationAt: Date?
    private let duplicatePresentationWindow: TimeInterval = 5 * 60
    // Temporary testing gate: set to true only for local QA sessions.
    private let forceBypassShownTodayForTesting = false

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
        return reason != .manual && reason != .scheduledTime && reason != .checkNow
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

        return reason != .manual && reason != .checkNow && reason != .scheduledTime
    }

    static func scheduledNotificationEventKey(
        now: Date,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> String? {
        let configuredTime = (defaults.string(forKey: "notification_hour")?.isEmpty == false)
            ? defaults.string(forKey: "notification_hour")!
            : "09:00"

        let parts = configuredTime.split(separator: ":")
        guard parts.count == 2 else {
            return nil
        }

        return HelperSchedule.scheduledSlotID(for: now, timeString: configuredTime, calendar: calendar)
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
        requestID: String? = nil,
        onResult: ((PasswordInfo) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        if reason == .scheduledTime && requestID == nil {
            Logger.shared.log("Skipping scheduledTime live refresh without helper requestID")
            return
        }

        if let requestID {
            let triggerKey = "live:\(reason.rawValue):\(requestID)"
            guard NotificationStateStore.shared.claimHelperTrigger(triggerKey: triggerKey) else {
                Logger.shared.log("Skipping live refresh because the same request was already handled recently (reason=\(reason.rawValue), requestID=\(requestID))")
                return
            }
        }

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
                    requestID: requestID,
                    onResult: onResult,
                    onError: onError
                )
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

        Task.detached(priority: .userInitiated) {
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
                    requestID: requestID,
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
        requestID: String?,
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
            requestID: requestID,
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
            evaluateNotificationState(reason: reason, now: Date())
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
        requestID: String?,
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
                evaluateNotificationState(reason: reason, requestID: requestID, now: Date())
            }
        case .failure(let error):
            handleLiveRefreshFallback(
                reason: reason,
                error: error,
                shouldCheckNotification: shouldCheckNotification,
                requestID: requestID,
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
        requestID: String?,
        onResult: ((PasswordInfo) -> Void)?,
        onError: ((Error) -> Void)?
    ) {
        hasPerformedRefresh = true
        isDomainAvailable = false
        if deliverCachedInfo(reason: reason, shouldCheckNotification: false, requestID: requestID, onResult: onResult) {
            if shouldCheckNotification {
                evaluateNotificationState(reason: reason, requestID: requestID, now: Date())
            }
        } else {
            onError?(error)
        }
    }

    @discardableResult
    private func deliverCachedInfo(
        reason: CheckReason,
        shouldCheckNotification: Bool = true,
        requestID: String? = nil,
        onResult: ((PasswordInfo) -> Void)?
    ) -> Bool {
        guard let info = latestPasswordInfo ?? PasswordCache.shared.load() else {
            return false
        }
        latestPasswordInfo = info
        updateExpirationDate(info.expiryDate)
        if shouldCheckNotification {
            evaluateNotificationState(reason: reason, requestID: requestID, now: Date())
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
    public func checkAndShowNotificationIfNeeded(
        reason: CheckReason = .automatic,
        allowLiveCheck: Bool = true,
        requestID: String? = nil
    ) {
        let now = Date()

        if UpdateNotificationStateStore.shared.state.isCriticalBlocking {
            if shouldLog(key: "notification_skip_critical_update", interval: 5 * 60) {
                Logger.shared.log("Skipping password notification because a critical app update is pending (reason=\(reason.rawValue))")
            }
            return
        }

        if let requestID {
            let triggerKey = "decision:\(reason.rawValue):\(requestID)"
            guard NotificationStateStore.shared.claimHelperTrigger(triggerKey: triggerKey) else {
                Logger.shared.log("Skipping notification decision because the same request was already handled recently (reason=\(reason.rawValue), requestID=\(requestID))")
                return
            }
        }

        guard shouldHandleNotifications(for: reason) else {
            if shouldLog(key: "notification_skip_helper_enabled", interval: 5 * 60) {
                Logger.shared.log("Skipping notification check in main app because helper is enabled (reason=\(reason.rawValue))")
            }
            return
        }

        if reason == .scheduledTime {
            let scheduledSlotID = Self.scheduledNotificationEventKey(now: now)
            if let scheduledSlotID,
               lastHandledScheduledNotificationSlotID == scheduledSlotID {
                if shouldLog(key: "notification_scheduled_slot_claim", interval: 60) {
                    Logger.shared.log("Skipping scheduled notification because the slot was already handled in this process (slotID=\(scheduledSlotID))")
                }
                return
            }

            guard claimScheduledNotificationEvent(now: now) else {
                return
            }

            lastHandledScheduledNotificationSlotID = scheduledSlotID
        }

        evaluateNotificationState(reason: reason, allowLiveCheck: allowLiveCheck, requestID: requestID, now: now)
    }

    private func evaluateNotificationState(
        reason: CheckReason,
        allowLiveCheck: Bool = false,
        requestID: String? = nil,
        now: Date = Date()
    ) {
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
                    requestID: requestID,
                    onResult: { [weak self] _ in
                        self?.evaluateNotificationState(reason: reason, allowLiveCheck: false, requestID: requestID, now: Date())
                    },
                    onError: { [weak self] _ in
                        self?.logMissingExpirationDateOnce()
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

        if shouldSuppressNotificationBecauseMainAppIsActive(reason: reason) {
            if shouldLog(key: "notification_main_app_active", interval: 5 * 60) {
                Logger.shared.log("Skipping notification because PasswordMonitor.app is active (reason=\(reason.rawValue))")
            }
            return
        }

        if shouldSuppressDuplicateNotificationPresentation(reason: reason, expirationDate: expirationDate, now: now) {
            if shouldLog(key: "notification_duplicate_presentation", interval: 60) {
                Logger.shared.log("Skipping notification presentation because the same expirationDate was already handled recently (reason=\(reason.rawValue), expirationDate=\(expirationDate))")
            }
            return
        }
        
        let bypassShownToday = forceBypassShownTodayForTesting || reason == .checkNow || reason == .scheduledTime
        guard !hasShownNotificationToday || bypassShownToday else {
            if shouldLog(key: "notification_already_shown", interval: 30 * 60) {
                Logger.shared.logLocalized("log_notification_already_shown_today")
            }
            return
        }
        if hasShownNotificationToday && bypassShownToday {
            if shouldLog(key: "notification_shown_today_bypass", interval: 10) {
                Logger.shared.log("Bypassing shownToday gate for testing (reason=\(reason.rawValue))")
            }
        }
        
        let snoozeStillActive = !hasSnoozeExpired()

        if snoozeStillActive && reason == .scheduledTime {
            Logger.shared.log("Scheduled moment overrides active snooze (snoozeUntil=\(snoozeEndTime?.formatted() ?? "unknown"))")
            isSnoozed = false
            snoozeEndTime = nil
            persistNotificationState()
        }

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

        if Self.isWithinWarningThreshold(now: now, expirationDate: expirationDate, thresholdDays: thresholdDays) {
            Logger.shared.logLocalized("log_notification_threshold_reached %d", daysRemaining)
            showNotification(passwordExpirationDate: expirationDate, reason: reason)
            return
        }

        if lastLoggedDaysRemaining != daysRemaining || shouldLog(key: "notification_below_threshold", interval: 60 * 60) {
            Logger.shared.log("Skipping notification; password expires in \(daysRemaining) days, threshold is \(thresholdDays)")
            lastLoggedDaysRemaining = daysRemaining
        }
    }

    private func claimScheduledNotificationEvent(now: Date = Date()) -> Bool {
        guard let eventKey = Self.scheduledNotificationEventKey(now: now) else {
            return true
        }

        guard stateStore.claimScheduledNotificationEvent(eventKey: eventKey, now: now) else {
            if shouldLog(key: "notification_scheduled_slot_claim", interval: 60) {
                Logger.shared.log("Skipping scheduled notification because the slot was already handled recently (slotID=\(eventKey))")
            }
            return false
        }

        return true
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
    private func showNotification(passwordExpirationDate: Date, reason: CheckReason) {
        guard currentAlert == nil else {
            Logger.shared.logLocalized("log_notification_window_already_open")
            return
        }

        if shouldProtectAgainstDuplicateDeliveryClaim(reason: reason) {
            if !stateStore.claimNotificationDelivery(expirationDate: passwordExpirationDate) {
                Logger.shared.log("Skipping notification presentation because another process already claimed it (reason=\(reason.rawValue))")
                return
            }
        }

        lastPresentedNotificationExpirationDate = passwordExpirationDate
        lastPresentedNotificationAt = Date()
        
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
                    shouldScheduleLiveRecheck: reason == .scheduledTime && useOfflineFlow
                )
            },
            onChangePassword: { [weak self] in
                guard let self = self else { return }
                Logger.shared.logLocalized("log_notification_change_password_selected")
                PasswordChangeHelper.requestPasswordChange()
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
                PasswordChangeHelper.requestPasswordChange()
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
        // Helper ma własny one-shot scheduler + wakeObserver w HelperAppDelegate.
        // Uruchamianie dodatkowego 60s-timera w helperze duplikuje logi
        // i odczytuje stale UserDefaults przed kolejnym `syncSharedSettings`.
        if Bundle.main.bundleIdentifier == helperBundleId {
            Logger.shared.log("Skipping periodic checkTimer in helper process (helper uses its own scheduler)")
            return
        }

        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                if self.isHelperProcessRunning() {
                    if self.shouldLog(key: "notification_skip_main_timer_helper_running", interval: 60) {
                        Logger.shared.log("Skipping periodic notification timer in main app because helper process is running")
                    }
                    return
                }

                let now = Date()
                if self.isScheduledNotificationMoment(now) {
                    if self.shouldLog(key: "notification_skip_main_timer_scheduled_time", interval: 60) {
                        Logger.shared.log("Skipping scheduledTime in main app timer; helper owns scheduled notifications")
                    }
                    return
                }

                self.checkAndShowNotificationIfNeeded(reason: .automatic)
            }
        }

        // Sprawdź od razu przy starcie (na wypadek gdybyśmy uruchomili się po czasie)
        checkAndShowNotificationIfNeeded(reason: .automatic)
    }

    private func shouldHandleNotifications(for reason: CheckReason) -> Bool {
        if reason == .manual || reason == .menuOpen || reason == .checkNow {
            return true
        }

        if Bundle.main.bundleIdentifier == helperBundleId {
            return true
        }

        return !isHelperProcessRunning()
    }

    private func shouldSuppressNotificationBecauseMainAppIsActive(reason: CheckReason) -> Bool {
        guard reason == .automatic || reason == .scheduledTime else {
            return false
        }

        return NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == mainAppBundleId && application.isActive
        }
    }

    private func isHelperProcessRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == helperBundleId
        }
    }

    private func shouldSuppressDuplicateNotificationPresentation(reason: CheckReason, expirationDate: Date, now: Date) -> Bool {
        Self.shouldSuppressDuplicateNotificationPresentation(
            reason: reason,
            expirationDate: expirationDate,
            lastPresentedExpirationDate: lastPresentedNotificationExpirationDate,
            lastPresentedAt: lastPresentedNotificationAt,
            now: now,
            duplicatePresentationWindow: duplicatePresentationWindow
        )
    }

    public static func shouldSuppressDuplicateNotificationPresentation(
        reason: CheckReason,
        expirationDate: Date,
        lastPresentedExpirationDate: Date?,
        lastPresentedAt: Date?,
        now: Date = Date(),
        duplicatePresentationWindow: TimeInterval = 5 * 60
    ) -> Bool {
        guard reason == .automatic || reason == .scheduledTime else {
            return false
        }

        guard let lastPresentedExpirationDate,
              let lastPresentedAt else {
            return false
        }

        guard abs(lastPresentedExpirationDate.timeIntervalSince(expirationDate)) < 1 else {
            return false
        }

        return now.timeIntervalSince(lastPresentedAt) < duplicatePresentationWindow
    }

    private func shouldProtectAgainstDuplicateDeliveryClaim(reason: CheckReason) -> Bool {
        reason == .automatic || reason == .scheduledTime
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
