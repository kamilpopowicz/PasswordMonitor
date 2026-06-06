//
//  UpdateNotificationStateStore.swift
//  PasswordMonitorCore
//
//  Created by Kamil Popowicz on 06/06/2026.
//

import Foundation

public struct PMUpdateNotificationState: Equatable, Sendable {
    public let automaticChecksEnabled: Bool
    public let lastAutomaticCheckAt: Date?
    public let lastBackgroundErrorAt: Date?
    public let checkInFlightUntil: Date?
    public let availableVersion: String?
    public let releaseTag: String?
    public let urgency: PMUpdateUrgency
    public let remindLaterUntil: Date?
    public let lastBackgroundError: String?
    public let pendingInstallRequest: Bool

    public var isUpdateAvailable: Bool {
        availableVersion?.isEmpty == false
    }

    public var isCriticalBlocking: Bool {
        isUpdateAvailable && urgency == .critical
    }

    public var notificationKey: String? {
        guard let availableVersion else { return nil }
        return "\(availableVersion):\(urgency.rawValue)"
    }
}

public final class UpdateNotificationStateStore {
    public static let shared = UpdateNotificationStateStore()

    public static let automaticChecksEnabledKey = "update_automatic_checks_enabled"
    public static let lastAutomaticCheckAtKey = "update_last_automatic_check_at"
    public static let availableVersionKey = "update_available_version"
    public static let releaseTagKey = "update_release_tag"
    public static let urgencyKey = "update_urgency"
    public static let remindLaterUntilKey = "update_remind_later_until"
    public static let lastBackgroundErrorKey = "update_last_background_error"
    public static let lastBackgroundErrorAtKey = "update_last_background_error_at"
    public static let checkInFlightUntilKey = "update_check_in_flight_until"
    public static let lastNotifiedKey = "update_last_notified_key"
    public static let pendingInstallRequestKey = "update_pending_install_request"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = UserDefaults(suiteName: AppUninstallCleanupPlan.sharedSuiteName) ?? .standard) {
        self.defaults = defaults
    }

    public var state: PMUpdateNotificationState {
        PMUpdateNotificationState(
            automaticChecksEnabled: automaticChecksEnabled,
            lastAutomaticCheckAt: defaults.object(forKey: Self.lastAutomaticCheckAtKey) as? Date,
            lastBackgroundErrorAt: defaults.object(forKey: Self.lastBackgroundErrorAtKey) as? Date,
            checkInFlightUntil: defaults.object(forKey: Self.checkInFlightUntilKey) as? Date,
            availableVersion: defaults.string(forKey: Self.availableVersionKey),
            releaseTag: defaults.string(forKey: Self.releaseTagKey),
            urgency: PMUpdateUrgency(rawValue: defaults.string(forKey: Self.urgencyKey) ?? "") ?? .normal,
            remindLaterUntil: defaults.object(forKey: Self.remindLaterUntilKey) as? Date,
            lastBackgroundError: defaults.string(forKey: Self.lastBackgroundErrorKey),
            pendingInstallRequest: defaults.bool(forKey: Self.pendingInstallRequestKey)
        )
    }

    public var automaticChecksEnabled: Bool {
        get {
            guard defaults.object(forKey: Self.automaticChecksEnabledKey) != nil else {
                return true
            }
            return defaults.bool(forKey: Self.automaticChecksEnabledKey)
        }
        set { defaults.set(newValue, forKey: Self.automaticChecksEnabledKey) }
    }

    public func markAutomaticCheckSucceeded(at date: Date) {
        defaults.set(date, forKey: Self.lastAutomaticCheckAtKey)
        defaults.removeObject(forKey: Self.lastBackgroundErrorKey)
        defaults.removeObject(forKey: Self.lastBackgroundErrorAtKey)
        clearAutomaticCheckClaim()
    }

    public func recordAvailableUpdate(version: String, releaseTag: String, urgency: PMUpdateUrgency) {
        defaults.set(version, forKey: Self.availableVersionKey)
        defaults.set(releaseTag, forKey: Self.releaseTagKey)
        defaults.set(urgency.rawValue, forKey: Self.urgencyKey)
        if urgency == .critical {
            defaults.removeObject(forKey: Self.remindLaterUntilKey)
        }
    }

    public func clearAvailableUpdate() {
        defaults.removeObject(forKey: Self.availableVersionKey)
        defaults.removeObject(forKey: Self.releaseTagKey)
        defaults.removeObject(forKey: Self.urgencyKey)
        defaults.removeObject(forKey: Self.remindLaterUntilKey)
        defaults.removeObject(forKey: Self.lastBackgroundErrorKey)
        defaults.removeObject(forKey: Self.lastBackgroundErrorAtKey)
        defaults.removeObject(forKey: Self.lastNotifiedKey)
        defaults.removeObject(forKey: Self.pendingInstallRequestKey)
    }

    public func recordBackgroundError(_ message: String, at date: Date = Date()) {
        defaults.set(message, forKey: Self.lastBackgroundErrorKey)
        defaults.set(date, forKey: Self.lastBackgroundErrorAtKey)
        clearAutomaticCheckClaim()
    }

    public func remindLater(until date: Date) {
        defaults.set(date, forKey: Self.remindLaterUntilKey)
    }

    public func setPendingInstallRequest(_ value: Bool) {
        defaults.set(value, forKey: Self.pendingInstallRequestKey)
    }

    public func consumePendingInstallRequest() -> Bool {
        let value = defaults.bool(forKey: Self.pendingInstallRequestKey)
        defaults.set(false, forKey: Self.pendingInstallRequestKey)
        return value
    }

    public func claimAutomaticCheck(now: Date = Date(), ttl: TimeInterval = PMUpdateMonitorPolicy.defaultInFlightTTL) -> Bool {
        if let inFlightUntil = defaults.object(forKey: Self.checkInFlightUntilKey) as? Date,
           inFlightUntil > now {
            return false
        }
        defaults.set(now.addingTimeInterval(ttl), forKey: Self.checkInFlightUntilKey)
        return true
    }

    public func clearAutomaticCheckClaim() {
        defaults.removeObject(forKey: Self.checkInFlightUntilKey)
    }

    public func shouldRunAutomaticCheck(
        now: Date = Date(),
        successCooldown: TimeInterval = PMUpdateMonitorPolicy.defaultSuccessCooldown,
        failureCooldown: TimeInterval = PMUpdateMonitorPolicy.defaultFailureCooldown
    ) -> Bool {
        Self.shouldRunAutomaticCheck(
            automaticChecksEnabled: automaticChecksEnabled,
            lastAutomaticCheckAt: state.lastAutomaticCheckAt,
            lastBackgroundErrorAt: state.lastBackgroundErrorAt,
            now: now,
            successCooldown: successCooldown,
            failureCooldown: failureCooldown
        )
    }

    public func shouldNotifyUser(now: Date = Date()) -> Bool {
        let current = state
        guard current.isUpdateAvailable, let notificationKey = current.notificationKey else {
            return false
        }
        if current.urgency != .critical,
           let remindLaterUntil = current.remindLaterUntil,
           remindLaterUntil > now {
            return false
        }
        return defaults.string(forKey: Self.lastNotifiedKey) != notificationKey
    }

    public func markUserNotified() {
        guard let key = state.notificationKey else { return }
        defaults.set(key, forKey: Self.lastNotifiedKey)
    }

    public static func shouldRunAutomaticCheck(
        automaticChecksEnabled: Bool,
        lastAutomaticCheckAt: Date?,
        lastBackgroundErrorAt: Date?,
        now: Date,
        successCooldown: TimeInterval,
        failureCooldown: TimeInterval
    ) -> Bool {
        guard automaticChecksEnabled else { return false }
        if let lastAutomaticCheckAt,
           now.timeIntervalSince(lastAutomaticCheckAt) < successCooldown {
            return false
        }
        if let lastBackgroundErrorAt,
           now.timeIntervalSince(lastBackgroundErrorAt) < failureCooldown {
            return false
        }
        return true
    }
}

public enum PMUpdateMonitorPolicy {
    public static let defaultSuccessCooldown: TimeInterval = 168 * 60 * 60
    public static let defaultFailureCooldown: TimeInterval = 60 * 60
    public static let defaultInFlightTTL: TimeInterval = 2 * 60
    public static let normalRemindLaterInterval: TimeInterval = 168 * 60 * 60
    public static let candidateManifestTTL: TimeInterval = 30 * 60
}
