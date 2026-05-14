//
//  NotificationStateStore.swift
//  PasswordMonitorCore
//
//  Created by Codex on 14/03/2026.
//

import Foundation
import Darwin

public final class NotificationStateStore {
    public static let shared = NotificationStateStore()

    private struct DeliveryClaim: Codable {
        let claimedAt: Date
        let expirationDate: Date
    }

    private struct ScheduledEventClaim: Codable {
        let claimedAt: Date
        let eventKey: String
    }

    private struct HelperTriggerClaims: Codable {
        var claims: [String: Date]
    }

    private let defaults: UserDefaults
    private let lockFilePath: String
    private let hasShownKey = "notification_has_shown_today"
    private let isSnoozedKey = "notification_is_snoozed"
    private let snoozeEndKey = "notification_snooze_end"
    private let deliveryClaimFilePath: String
    private let scheduledEventClaimFilePath: String
    private let helperTriggerClaimFilePath: String
    private let deliveryClaimWindow: TimeInterval = 120
    private let scheduledEventClaimWindow: TimeInterval = 5 * 60
    private let lockDirectory = "/tmp"

    private init() {
        self.defaults = UserDefaults(suiteName: "popo.PasswordMonitor") ?? .standard
        self.lockFilePath = (lockDirectory as NSString).appendingPathComponent("popo.PasswordMonitor.notification.lock")
        self.deliveryClaimFilePath = (lockDirectory as NSString).appendingPathComponent("popo.PasswordMonitor.notification.claim.json")
        self.scheduledEventClaimFilePath = (lockDirectory as NSString).appendingPathComponent("popo.PasswordMonitor.notification.scheduled.claim.json")
        self.helperTriggerClaimFilePath = (lockDirectory as NSString).appendingPathComponent("popo.PasswordMonitor.helper.trigger.claim.json")
    }

    public var hasShownNotificationToday: Bool {
        get { defaults.bool(forKey: hasShownKey) }
        set { defaults.set(newValue, forKey: hasShownKey) }
    }

    public var isSnoozed: Bool {
        get { defaults.bool(forKey: isSnoozedKey) }
        set { defaults.set(newValue, forKey: isSnoozedKey) }
    }

    public var snoozeEndTime: Date? {
        get { defaults.object(forKey: snoozeEndKey) as? Date }
        set { defaults.set(newValue, forKey: snoozeEndKey) }
    }

    public func claimNotificationDelivery(expirationDate: Date, now: Date = Date()) -> Bool {
        withFileLock {
            if let lastClaim = loadDeliveryClaim(),
               sameExpirationDate(lastClaim.expirationDate, expirationDate),
               now.timeIntervalSince(lastClaim.claimedAt) < deliveryClaimWindow {
                return false
            }

            let claim = DeliveryClaim(claimedAt: now, expirationDate: expirationDate)
            guard let data = try? JSONEncoder().encode(claim) else {
                return false
            }

            do {
                try data.write(to: URL(fileURLWithPath: deliveryClaimFilePath), options: .atomic)
            } catch {
                return false
            }

            defaults.set(true, forKey: hasShownKey)
            return true
        }
    }

    public func clearNotificationDeliveryClaim() {
        withFileLock {
            try? FileManager.default.removeItem(atPath: deliveryClaimFilePath)
        }
    }

    public func claimScheduledNotificationEvent(eventKey: String, now: Date = Date()) -> Bool {
        withFileLock {
            if let lastClaim = loadScheduledEventClaim(),
               lastClaim.eventKey == eventKey,
               now.timeIntervalSince(lastClaim.claimedAt) < scheduledEventClaimWindow {
                return false
            }

            let claim = ScheduledEventClaim(claimedAt: now, eventKey: eventKey)
            guard let data = try? JSONEncoder().encode(claim) else {
                return false
            }

            do {
                try data.write(to: URL(fileURLWithPath: scheduledEventClaimFilePath), options: .atomic)
            } catch {
                return false
            }

            return true
        }
    }

    public func clearScheduledNotificationEventClaim() {
        withFileLock {
            try? FileManager.default.removeItem(atPath: scheduledEventClaimFilePath)
        }
    }

    public func claimHelperTrigger(triggerKey: String, now: Date = Date()) -> Bool {
        withFileLock {
            var claims = loadHelperTriggerClaims()
            if let lastClaim = claims.claims[triggerKey],
               sameDayAndMinute(lastClaim, now) {
                return false
            }

            claims.claims[triggerKey] = now
            guard let data = try? JSONEncoder().encode(claims) else {
                return false
            }

            do {
                try data.write(to: URL(fileURLWithPath: helperTriggerClaimFilePath), options: .atomic)
            } catch {
                return false
            }

            return true
        }
    }

    public func clearHelperTriggerClaim() {
        withFileLock {
            try? FileManager.default.removeItem(atPath: helperTriggerClaimFilePath)
        }
    }

    private func loadDeliveryClaim() -> DeliveryClaim? {
        let url = URL(fileURLWithPath: deliveryClaimFilePath)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(DeliveryClaim.self, from: data)
    }

    private func loadScheduledEventClaim() -> ScheduledEventClaim? {
        let url = URL(fileURLWithPath: scheduledEventClaimFilePath)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(ScheduledEventClaim.self, from: data)
    }

    private func loadHelperTriggerClaims() -> HelperTriggerClaims {
        let url = URL(fileURLWithPath: helperTriggerClaimFilePath)
        guard let data = try? Data(contentsOf: url),
              let claims = try? JSONDecoder().decode(HelperTriggerClaims.self, from: data) else {
            return HelperTriggerClaims(claims: [:])
        }
        return claims
    }

    private func sameExpirationDate(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 1
    }

    private func sameDayAndMinute(_ lhs: Date, _ rhs: Date) -> Bool {
        let calendar = Calendar.current
        let lhsComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: lhs)
        let rhsComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rhs)
        return lhsComponents.year == rhsComponents.year &&
            lhsComponents.month == rhsComponents.month &&
            lhsComponents.day == rhsComponents.day &&
            lhsComponents.hour == rhsComponents.hour &&
            lhsComponents.minute == rhsComponents.minute
    }

    private func withFileLock<T>(_ body: () -> T) -> T {
        let fd = open(lockFilePath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            return body()
        }

        defer { close(fd) }

        if flock(fd, LOCK_EX) != 0 {
            return body()
        }

        defer { flock(fd, LOCK_UN) }
        return body()
    }
}
