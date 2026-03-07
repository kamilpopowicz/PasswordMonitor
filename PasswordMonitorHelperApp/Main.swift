//
//  Main.swift
//  PasswordMonitorHelperApp
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import AppKit
import Foundation
import PasswordMonitorCore

final class HelperAppDelegate: NSObject, NSApplicationDelegate {
    private let refreshInterval: TimeInterval = 60 * 60
    private var refreshTimer: Timer?
    private var scheduledCheckTimer: Timer?
    private var wakeObserver: Any?
    private var manualRefreshObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("Password Monitor Helper launched")
        syncSharedSettings()
        schedulePeriodicRefresh()
        scheduleNextNotificationTimeRefresh()

        wakeObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Logger.shared.log("Helper automatic refresh triggered by system wake")
            guard let helper = self else { return }
            Task { @MainActor in
                helper.refreshPasswordStatus(reason: HelperRefreshReason.wake.rawValue)
            }
        }

        manualRefreshObserver = DistributedNotificationCenter.default().addObserver(
            forName: HelperMessaging.forceRefreshNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Logger.shared.log("Helper manual refresh triggered from Settings")
            guard let helper = self else { return }
            Task { @MainActor in
                helper.refreshPasswordStatus(reason: HelperRefreshReason.manual.rawValue)
            }
        }

        Task { @MainActor in
            refreshPasswordStatus(reason: HelperRefreshReason.launch.rawValue)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        scheduledCheckTimer?.invalidate()
        if let wakeObserver {
            NotificationCenter.default.removeObserver(wakeObserver)
        }
        if let manualRefreshObserver {
            DistributedNotificationCenter.default().removeObserver(manualRefreshObserver)
        }
    }

    private func schedulePeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let helper = self else { return }
            Task { @MainActor in
                helper.refreshPasswordStatus(reason: HelperRefreshReason.timer.rawValue)
            }
        }

        Logger.shared.log("Helper scheduled periodic refresh every \(Int(refreshInterval / 60)) minutes")
    }

    private func scheduleNextNotificationTimeRefresh() {
        scheduledCheckTimer?.invalidate()

        let nextCheckDate = HelperSchedule.nextOccurrence(for: notificationTimeString(), after: Date())
        let interval = max(1, nextCheckDate.timeIntervalSinceNow)

        scheduledCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let helper = self else { return }
            Task { @MainActor in
                helper.refreshPasswordStatus(reason: HelperRefreshReason.scheduledTime.rawValue)
                helper.scheduleNextNotificationTimeRefresh()
            }
        }

        Logger.shared.log("Helper scheduled notification-time refresh for \(nextCheckDate)")
    }

    @MainActor
    private func refreshPasswordStatus(reason: String) {
        syncSharedSettings()
        scheduleNextNotificationTimeRefresh()

        let username = NSUserName()
        let refreshMode = (reason == HelperRefreshReason.manual.rawValue) ? "manual" : "automatic"
        Logger.shared.log("Helper refresh mode: \(refreshMode), reason=\(reason)")
        Logger.shared.log("Helper refresh started (reason=\(reason))")

        guard shouldRefreshNow(reason: reason) else {
            return
        }

        Task.detached(priority: .userInitiated) {
            let manager = ActiveDirectoryManager()

            do {
                let info = try manager.getPasswordInfo(for: username)
                await MainActor.run {
                    Logger.shared.log("Helper fetched password status: daysRemaining=\(info.daysUntilExpiration), expiryDate=\(info.expiryDate)")
                    NotificationManager.shared.updateExpirationDate(info.expiryDate)
                    NotificationManager.shared.checkAndShowNotificationIfNeeded()
                }
            } catch {
                await MainActor.run {
                    Logger.shared.log("Helper refresh failed (reason=\(reason)): \(error)", level: .error)
                }
            }
        }
    }

    private func shouldRefreshNow(reason: String) -> Bool {
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
            "ad_domain",
            "max_password_age",
            "warning_threshold",
            "notification_hour",
            "quiet_hours_start",
            "quiet_hours_end",
            "minimal_logging",
            "appLanguage",
            "theme_mode"
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
