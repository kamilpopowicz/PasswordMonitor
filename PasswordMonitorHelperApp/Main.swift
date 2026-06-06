//
//  Main.swift
//  PasswordMonitorHelperApp
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import AppKit
import Foundation
import Darwin
import PasswordMonitorCore
import UserNotifications

final class HelperAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var scheduledCheckTimer: Timer?
    private var wakeObserver: Any?
    private var manualRefreshObserver: NSObjectProtocol?
    private var settingsChangeObserver: NSObjectProtocol?
    private var launchLockFD: Int32 = -1
    private var didRegisterObservers = false
    private var lastHandledTriggerAt: [String: Date] = [:]
    private var helperCycleInFlight = false
    private var activeHelperCycleID: UUID?
    private var lastScheduledNotificationTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("Password Monitor Helper launched")

        guard acquireSingleInstanceLock() else {
            Logger.shared.log("Helper instance already active; exiting duplicate launch")
            NSApplication.shared.terminate(nil)
            return
        }

        terminateDuplicateHelperProcesses()
        registerObserversIfNeeded()
        PMUpdateSystemNotifier.shared.configureCategories()
        UNUserNotificationCenter.current().delegate = self

        Task { @MainActor in
            handleWakeOrLaunchCheck()
            await checkForUpdatesIfNeeded(trigger: .launch)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduledCheckTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let manualRefreshObserver {
            DistributedNotificationCenter.default().removeObserver(manualRefreshObserver)
        }
        if let settingsChangeObserver {
            DistributedNotificationCenter.default().removeObserver(settingsChangeObserver)
        }
        if launchLockFD >= 0 {
            close(launchLockFD)
            launchLockFD = -1
        }
    }

    private func scheduleNextNotificationTimeRefresh() {
        let nextCheckDate = HelperSchedule.nextOccurrence(for: notificationTimeString(), after: Date())
        if let lastScheduledNotificationTime,
           abs(lastScheduledNotificationTime.timeIntervalSince(nextCheckDate)) < 1 {
            Logger.shared.log("Helper already scheduled notification-time refresh for \(nextCheckDate)")
            return
        }

        scheduledCheckTimer?.invalidate()
        lastScheduledNotificationTime = nextCheckDate

        let interval = max(1, nextCheckDate.timeIntervalSinceNow)

        scheduledCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let helper = self else { return }
            Task { @MainActor in
                helper.refreshPasswordStatus(reason: HelperRefreshReason.scheduledTime.rawValue)
            }
        }

        Logger.shared.log("Helper scheduled notification-time refresh for \(nextCheckDate)")
    }

    @MainActor
    private func syncConfigurationAndScheduleNextNotificationTime() {
        syncSharedSettings()
        scheduleNextNotificationTimeRefresh()
    }

    @MainActor
    private func reloadConfigurationFromSettings() {
        syncConfigurationAndScheduleNextNotificationTime()
    }

    @MainActor
    private func refreshPasswordStatus(reason: String) {
        syncSharedSettings()

        let requestID = helperRequestID(for: reason)
        guard claimHelperTrigger(triggerKey: "helper:\(reason):\(requestID)") else {
            return
        }

        let username = NSUserName()
        let refreshMode = (reason == HelperRefreshReason.manual.rawValue) ? "manual" : "automatic"
        Logger.shared.log("Helper refresh mode: \(refreshMode), reason=\(reason)")
        Logger.shared.log("Helper refresh started (reason=\(reason))")

        guard let cycleID = beginHelperCycle(trigger: "refresh:\(reason)") else {
            return
        }

        guard shouldRefreshNow(reason: reason) else {
            endHelperCycle(cycleID: cycleID, trigger: "refresh:\(reason)")
            return
        }

        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                NotificationManager.shared.refreshPasswordStatusLive(
                    reason: self.notificationCheckReason(for: reason),
                    username: username,
                    shouldCheckNotification: reason != HelperRefreshReason.scheduledTime.rawValue,
                    requestID: requestID,
                    onResult: { info in
                        Logger.shared.log("Helper fetched password status: daysRemaining=\(info.daysUntilExpiration), expiryDate=\(info.expiryDate)")
                        if reason == HelperRefreshReason.scheduledTime.rawValue {
                            Logger.shared.log("Helper evaluating scheduled notification once after refresh")
                            NotificationManager.shared.checkAndShowNotificationIfNeeded(
                                reason: .scheduledTime,
                                allowLiveCheck: false,
                                requestID: requestID
                            )
                        }
                        self.endHelperCycle(cycleID: cycleID, trigger: "refresh:\(reason)")
                        if reason == HelperRefreshReason.scheduledTime.rawValue {
                            self.scheduleNextNotificationTimeRefresh()
                        }
                    },
                    onError: { error in
                        Logger.shared.log("Helper refresh failed (reason=\(reason)): \(error)", level: .error)
                        self.endHelperCycle(cycleID: cycleID, trigger: "refresh:\(reason)")
                        if reason == HelperRefreshReason.scheduledTime.rawValue {
                            self.scheduleNextNotificationTimeRefresh()
                        }
                    }
                )
            }
        }
    }

    private func registerObserversIfNeeded() {
        guard !didRegisterObservers else { return }
        didRegisterObservers = true

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let helper = self else { return }
            guard helper.shouldHandleTrigger("wake", minimumInterval: 10) else { return }
            Logger.shared.log("Helper wake detected; refreshing notification state")
            Task { @MainActor in
                helper.handleWakeOrLaunchCheck()
                await helper.checkForUpdatesIfNeeded(trigger: .wake)
            }
        }

        manualRefreshObserver = DistributedNotificationCenter.default().addObserver(
            forName: HelperMessaging.forceRefreshNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let helper = self else { return }
            guard helper.shouldHandleTrigger("manual_refresh", minimumInterval: 2) else { return }
            Logger.shared.log("Helper manual refresh triggered from Settings")
            Task { @MainActor in
                helper.refreshPasswordStatus(reason: HelperRefreshReason.manual.rawValue)
            }
        }

        settingsChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: HelperMessaging.settingsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let helper = self else { return }
            guard helper.shouldHandleTrigger("settings_change", minimumInterval: 2) else { return }
            Logger.shared.log("Helper settings changed in Settings")
            Task { @MainActor in
                helper.reloadConfigurationFromSettings()
            }
        }
    }

    private func shouldHandleTrigger(_ key: String, minimumInterval: TimeInterval) -> Bool {
        let now = Date()
        if let last = lastHandledTriggerAt[key], now.timeIntervalSince(last) < minimumInterval {
            Logger.shared.log("Skipping duplicate helper trigger (\(key))")
            return false
        }
        lastHandledTriggerAt[key] = now
        return true
    }

    private func helperRequestID(for reason: String, now: Date = Date()) -> String {
        switch reason {
        case HelperRefreshReason.scheduledTime.rawValue:
            return "scheduled:\(HelperSchedule.scheduledSlotID(for: now, timeString: notificationTimeString()))"
        case HelperRefreshReason.manual.rawValue:
            return "manual:\(HelperSchedule.triggerBucketID(for: now))"
        case HelperRefreshReason.wake.rawValue:
            return "wake:\(HelperSchedule.triggerBucketID(for: now))"
        default:
            return "\(reason):\(HelperSchedule.triggerBucketID(for: now))"
        }
    }

    @MainActor
    private func claimHelperTrigger(triggerKey: String) -> Bool {
        guard NotificationStateStore.shared.claimHelperTrigger(triggerKey: triggerKey) else {
            Logger.shared.log("Skipping helper trigger because the same trigger was already claimed (\(triggerKey))")
            return false
        }

        return true
    }

    private func acquireSingleInstanceLock() -> Bool {
        let lockPath = "/tmp/popo.PasswordMonitor.helper.lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            return false
        }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }

        launchLockFD = fd
        return true
    }

    private func terminateDuplicateHelperProcesses() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentBundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        let helpers = NSRunningApplication.runningApplications(withBundleIdentifier: "popo.PasswordMonitorHelperApp")
        let duplicateHelpers = HelperProcessCleanup.duplicateHelpers(
            currentProcessIdentifier: currentPID,
            runningHelpers: helpers.map {
                HelperProcessCleanup.RunningHelper(
                    processIdentifier: $0.processIdentifier,
                    bundlePath: $0.bundleURL?.path
                )
            }
        )
        let duplicateHelperPIDs = Set(duplicateHelpers.map(\.processIdentifier))

        for helper in helpers where duplicateHelperPIDs.contains(helper.processIdentifier) {
            let helperPath = helper.bundleURL?.standardizedFileURL.path ?? "unknown"
            Logger.shared.log("Terminating duplicate helper process (pid=\(helper.processIdentifier), path=\(helperPath), currentPath=\(currentBundlePath))")
            if !helper.terminate() {
                helper.forceTerminate()
            }
        }
    }

    private func shouldRefreshNow(reason: String) -> Bool {
        if reason == HelperRefreshReason.scheduledTime.rawValue || reason == HelperRefreshReason.manual.rawValue {
            return true
        }

        let now = Date()
        guard !HelperSchedule.isWithinQuietHours(
            date: now,
            startTime: quietHoursStartString(),
            endTime: quietHoursEndString()
        ) else {
            Logger.shared.log("Helper skipped refresh during quiet hours (reason=\(reason), quietStart=\(quietHoursStartString()), quietEnd=\(quietHoursEndString()))")
            return false
        }

        return true
    }

    private func notificationCheckReason(for refreshReason: String) -> NotificationManager.CheckReason {
        switch refreshReason {
        case HelperRefreshReason.scheduledTime.rawValue:
            return .scheduledTime
        case HelperRefreshReason.manual.rawValue:
            return .manual
        default:
            return .automatic
        }
    }

    private func notificationTimeString() -> String {
        (UserDefaults.standard.string(forKey: "notification_hour")?.isEmpty == false)
            ? UserDefaults.standard.string(forKey: "notification_hour")!
            : "09:00"
    }

    private func quietHoursStartString() -> String {
        (UserDefaults.standard.string(forKey: "quiet_hours_start")?.isEmpty == false)
            ? UserDefaults.standard.string(forKey: "quiet_hours_start")!
            : "18:01"
    }

    private func quietHoursEndString() -> String {
        (UserDefaults.standard.string(forKey: "quiet_hours_end")?.isEmpty == false)
            ? UserDefaults.standard.string(forKey: "quiet_hours_end")!
            : "05:59"
    }

    private func syncSharedSettings() {
        let sourceDefaults = UserDefaults(suiteName: "popo.PasswordMonitor")
        let keys = [
            "max_password_age",
            "warning_threshold",
            "notification_hour",
            "quiet_hours_start",
            "quiet_hours_end",
            "minimal_logging",
            "appLanguage",
            "theme_mode",
            UpdateNotificationStateStore.automaticChecksEnabledKey
        ]

        var copiedKeys = [String]()
        for key in keys {
            if let value = sourceDefaults?.object(forKey: key) {
                UserDefaults.standard.set(value, forKey: key)
                copiedKeys.append(key)
            }
        }

        if copiedKeys.isEmpty {
            Logger.shared.log("Helper settings sync found no shared values")
        } else {
            Logger.shared.log("Helper synced settings keys: \(copiedKeys.joined(separator: ", "))")
        }

        let standard = UserDefaults.standard
        let snapshot = [
            "max_password_age=\(standard.integer(forKey: "max_password_age"))",
            "warning_threshold=\(standard.integer(forKey: "warning_threshold"))",
            "notification_hour=\(standard.string(forKey: "notification_hour") ?? "(default)")",
            "quiet_hours_start=\(standard.string(forKey: "quiet_hours_start") ?? "(default)")",
            "quiet_hours_end=\(standard.string(forKey: "quiet_hours_end") ?? "(default)")",
            "minimal_logging=\(standard.object(forKey: "minimal_logging") as? Bool ?? true)",
            "update_automatic_checks_enabled=\(standard.object(forKey: UpdateNotificationStateStore.automaticChecksEnabledKey) as? Bool ?? true)",
            "appLanguage=\(standard.string(forKey: "appLanguage") ?? "(default)")"
        ]
        Logger.shared.log("Helper settings snapshot after sync: \(snapshot.joined(separator: ", "))")
    }

    @MainActor
    private func checkForUpdatesIfNeeded(trigger: PMUpdateMonitorTrigger) async {
        syncSharedSettings()
        await PMUpdateMonitor.shared.checkIfNeeded(currentVersion: currentAppVersion(), trigger: trigger)
    }

    private func currentAppVersion() -> String {
        if let mainAppURL = containingMainAppURL(),
           let mainBundle = Bundle(url: mainAppURL),
           let version = mainBundle.infoDictionary?["CFBundleShortVersionString"] as? String,
           !version.isEmpty {
            return version
        }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func containingMainAppURL() -> URL? {
        var url = Bundle.main.bundleURL
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        return url.pathExtension == "app" ? url : nil
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.content.categoryIdentifier == PMUpdateSystemNotifier.categoryIdentifier else {
            return
        }
        await MainActor.run {
            PMUpdateMonitor.shared.setPendingInstallRequest()
            DistributedNotificationCenter.default().post(
                name: HelperMessaging.updateInstallRequestedNotification,
                object: nil,
                userInfo: nil
            )
            if let mainAppURL = containingMainAppURL() {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: mainAppURL, configuration: configuration)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.content.categoryIdentifier == PMUpdateSystemNotifier.categoryIdentifier else {
            return []
        }
        return [.banner, .sound, .list]
    }

    @MainActor
    private func handleWakeOrLaunchCheck() {
        syncConfigurationAndScheduleNextNotificationTime()

        Task { @MainActor in
            self.refreshPasswordStatus(reason: HelperRefreshReason.wake.rawValue)
        }
    }

    @MainActor
    private func beginHelperCycle(trigger: String) -> UUID? {
        guard !helperCycleInFlight else {
            Logger.shared.log("Skipping helper cycle because another cycle is already in flight (trigger=\(trigger), cycleID=\(activeHelperCycleID?.uuidString ?? "unknown"))")
            return nil
        }

        let cycleID = UUID()
        helperCycleInFlight = true
        activeHelperCycleID = cycleID
        Logger.shared.log("Helper cycle started (cycleID=\(cycleID.uuidString), trigger=\(trigger))")
        return cycleID
    }

    @MainActor
    private func endHelperCycle(cycleID: UUID, trigger: String) {
        guard activeHelperCycleID == cycleID else {
            return
        }

        helperCycleInFlight = false
        activeHelperCycleID = nil
        Logger.shared.log("Helper cycle finished (cycleID=\(cycleID.uuidString), trigger=\(trigger))")
    }
}

@main
struct PasswordMonitorHelperAppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = HelperAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
