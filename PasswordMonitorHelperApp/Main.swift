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
    private var scheduledCheckTimer: Timer?
    private var wakeObserver: Any?
    private var manualRefreshObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("Password Monitor Helper launched")

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Logger.shared.log("Helper wake detected; checking notification from cache")
            guard let helper = self else { return }
            helper.handleWakeOrLaunchCheck()
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

        handleWakeOrLaunchCheck()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduledCheckTimer?.invalidate()
        if let wakeObserver {
            NotificationCenter.default.removeObserver(wakeObserver)
        }
        if let manualRefreshObserver {
            DistributedNotificationCenter.default().removeObserver(manualRefreshObserver)
        }
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
            await MainActor.run {
                NotificationManager.shared.refreshPasswordStatusLive(
                    reason: self.notificationCheckReason(for: reason),
                    username: username,
                    shouldCheckNotification: true,
                    onResult: { info in
                        Logger.shared.log("Helper fetched password status: daysRemaining=\(info.daysUntilExpiration), expiryDate=\(info.expiryDate)")
                    },
                    onError: { error in
                        Logger.shared.log("Helper refresh failed (reason=\(reason)): \(error)", level: .error)
                    }
                )
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

        let standard = UserDefaults.standard
        let snapshot = [
            "max_password_age=\(standard.integer(forKey: "max_password_age"))",
            "warning_threshold=\(standard.integer(forKey: "warning_threshold"))",
            "notification_hour=\(standard.string(forKey: "notification_hour") ?? "(default)")",
            "quiet_hours_start=\(standard.string(forKey: "quiet_hours_start") ?? "(default)")",
            "quiet_hours_end=\(standard.string(forKey: "quiet_hours_end") ?? "(default)")",
            "minimal_logging=\(standard.object(forKey: "minimal_logging") as? Bool ?? true)",
            "appLanguage=\(standard.string(forKey: "appLanguage") ?? "(default)")"
        ]
        Logger.shared.log("Helper settings snapshot after sync: \(snapshot.joined(separator: ", "))")
    }

    private func handleWakeOrLaunchCheck() {
        syncSharedSettings()
        scheduleNextNotificationTimeRefresh()

        Task { @MainActor in
            if NotificationManager.shared.latestPasswordInfo != nil || PasswordCache.shared.load() != nil {
                NotificationManager.shared.checkAndShowNotificationIfNeeded(reason: .automatic)
                return
            }

            self.refreshPasswordStatus(reason: HelperRefreshReason.wake.rawValue)
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
