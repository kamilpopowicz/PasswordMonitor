//
//  UpdateMonitor.swift
//  PasswordMonitorCore
//
//  Created by Kamil Popowicz on 06/06/2026.
//

import Foundation
import Combine
import UserNotifications

public enum PMUpdateMonitorTrigger: String, Sendable {
    case launch
    case activation
    case menuOpen
    case wake
    case manual
}

@MainActor
public final class PMUpdateMonitor: ObservableObject {
    public static let shared = PMUpdateMonitor()

    @Published public private(set) var state: PMUpdateNotificationState
    @Published public private(set) var checkInProgress = false

    private let service: PMUpdateService
    private let store: UpdateNotificationStateStore
    private let notifier: PMUpdateSystemNotifier
    private let now: () -> Date

    public init(
        service: PMUpdateService = PMUpdateService(),
        store: UpdateNotificationStateStore = .shared,
        notifier: PMUpdateSystemNotifier = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.store = store
        self.notifier = notifier
        self.now = now
        self.state = store.state
    }

    public func reload() {
        state = store.state
    }

    public func setAutomaticChecksEnabled(_ enabled: Bool) {
        store.automaticChecksEnabled = enabled
        reload()
    }

    public func consumePendingInstallRequest() -> Bool {
        let consumed = store.consumePendingInstallRequest()
        reload()
        return consumed
    }

    public func setPendingInstallRequest() {
        store.setPendingInstallRequest(true)
        reload()
    }

    public func remindLater() {
        store.remindLater(until: now().addingTimeInterval(PMUpdateMonitorPolicy.normalRemindLaterInterval))
        reload()
    }

    public func clearDetectedUpdate() {
        store.clearAvailableUpdate()
        reload()
    }

    public func checkIfNeeded(currentVersion: String, trigger: PMUpdateMonitorTrigger) async {
        reload()
        guard store.shouldRunAutomaticCheck(now: now()) else {
            return
        }
        guard store.claimAutomaticCheck(now: now()) else {
            return
        }
        await check(
            currentVersion: currentVersion,
            trigger: trigger,
            updatesUserFacingStatus: false,
            clearsAutomaticCheckClaim: true
        )
    }

    @discardableResult
    public func checkNow(currentVersion: String, trigger: PMUpdateMonitorTrigger = .manual) async -> PMUpdateCheckResult? {
        await check(currentVersion: currentVersion, trigger: trigger, updatesUserFacingStatus: true)
    }

    @discardableResult
    private func check(
        currentVersion: String,
        trigger: PMUpdateMonitorTrigger,
        updatesUserFacingStatus: Bool,
        clearsAutomaticCheckClaim: Bool = false
    ) async -> PMUpdateCheckResult? {
        guard !checkInProgress else {
            if clearsAutomaticCheckClaim {
                store.clearAutomaticCheckClaim()
            }
            return nil
        }
        checkInProgress = true
        defer {
            checkInProgress = false
            if clearsAutomaticCheckClaim {
                store.clearAutomaticCheckClaim()
            }
        }

        do {
            let result = try await service.checkForUpdate(currentVersion: currentVersion)
            store.markAutomaticCheckSucceeded(at: now())
            switch result {
            case .upToDate:
                store.clearAvailableUpdate()
            case let .updateAvailable(candidate):
                store.recordAvailableUpdate(
                    version: candidate.version.description,
                    releaseTag: candidate.releaseTag,
                    urgency: candidate.urgency
                )
            }
            reload()
            await notifyIfNeeded()
            return result
        } catch {
            store.recordBackgroundError(error.localizedDescription, at: now())
            reload()
            if updatesUserFacingStatus {
                Logger.shared.log("Update check failed (trigger=\(trigger.rawValue)): \(error)", level: .error)
            } else {
                Logger.shared.log("Background update check failed (trigger=\(trigger.rawValue)): \(error)", level: .warning)
            }
            return nil
        }
    }

    private func notifyIfNeeded() async {
        guard store.shouldNotifyUser(now: now()) else { return }
        let current = store.state
        guard let version = current.availableVersion else { return }
        await notifier.deliverUpdateNotification(version: version, urgency: current.urgency)
        store.markUserNotified()
        reload()
    }
}

public final class PMUpdateSystemNotifier: NSObject {
    public static let shared = PMUpdateSystemNotifier()

    public static let categoryIdentifier = "PASSWORD_MONITOR_UPDATE"
    public static let requestIdentifier = "password-monitor-update-available"
    public static let installActionIdentifier = "PASSWORD_MONITOR_UPDATE_INSTALL"

    private override init() {}

    public func configureCategories() {
        let copy = PMUpdateNotificationCopy.current()
        let installAction = UNNotificationAction(
            identifier: Self.installActionIdentifier,
            title: copy.actionTitle,
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [installAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    public func deliverUpdateNotification(version: String, urgency: PMUpdateUrgency) async {
        configureCategories()
        do {
            try await requestAuthorizationIfNeeded()
            let content = UNMutableNotificationContent()
            content.categoryIdentifier = Self.categoryIdentifier
            content.threadIdentifier = Self.categoryIdentifier
            content.sound = .default
            content.userInfo = [
                "kind": "update",
                "version": version,
                "urgency": urgency.rawValue
            ]

            switch urgency {
            case .normal:
                let copy = PMUpdateNotificationCopy.current()
                content.title = copy.normalTitle
                content.body = copy.normalBody(version)
                content.interruptionLevel = .active
            case .critical:
                let copy = PMUpdateNotificationCopy.current()
                content.title = copy.criticalTitle
                content.body = copy.criticalBody
                content.interruptionLevel = .timeSensitive
            }

            let request = UNNotificationRequest(
                identifier: "\(Self.requestIdentifier)-\(version)-\(urgency.rawValue)",
                content: content,
                trigger: nil
            )
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Logger.shared.log("Update notification delivery failed: \(error)", level: .warning)
        }
    }

    private func requestAuthorizationIfNeeded() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .notDetermined:
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        case .denied:
            throw PMUpdateNotificationError.authorizationDenied
        @unknown default:
            throw PMUpdateNotificationError.authorizationDenied
        }
    }
}

public struct PMUpdateNotificationCopy: Sendable {
    public let actionTitle: String
    public let normalTitle: String
    public let normalBody: @Sendable (String) -> String
    public let criticalTitle: String
    public let criticalBody: String

    public static func current(
        defaults: UserDefaults = UserDefaults(suiteName: AppUninstallCleanupPlan.sharedSuiteName) ?? .standard
    ) -> PMUpdateNotificationCopy {
        let code = defaults.string(forKey: "appLanguage")
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        return localized(languageCode: code)
    }

    // Kept in core so the helper can localize update notifications without linking app-only UI settings.
    private static func localized(languageCode: String) -> PMUpdateNotificationCopy {
        switch languageCode.lowercased().split(separator: "-").first {
        case "pl":
            return PMUpdateNotificationCopy(
                actionTitle: "Aktualizuj",
                normalTitle: "Dostępna aktualizacja PasswordMonitor",
                normalBody: { "Wersja \($0) jest gotowa do instalacji." },
                criticalTitle: "Wymagana krytyczna aktualizacja PasswordMonitor",
                criticalBody: "Krytyczna aktualizacja jest wymagana przed dalszym używaniem PasswordMonitor."
            )
        default:
            return PMUpdateNotificationCopy(
                actionTitle: "Update",
                normalTitle: "PasswordMonitor update available",
                normalBody: { "Version \($0) is ready to install." },
                criticalTitle: "Critical PasswordMonitor update required",
                criticalBody: "A critical update is required before using PasswordMonitor."
            )
        }
    }
}

public enum PMUpdateNotificationError: LocalizedError {
    case authorizationDenied

    public var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Notification authorization is denied."
        }
    }
}
