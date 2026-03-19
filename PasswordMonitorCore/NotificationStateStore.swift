//
//  NotificationStateStore.swift
//  PasswordMonitorCore
//
//  Created by Codex on 14/03/2026.
//

import Foundation

public final class NotificationStateStore {
    public static let shared = NotificationStateStore()

    private let defaults: UserDefaults
    private let hasShownKey = "notification_has_shown_today"
    private let isSnoozedKey = "notification_is_snoozed"
    private let snoozeEndKey = "notification_snooze_end"

    private init() {
        self.defaults = UserDefaults(suiteName: "popo.PasswordMonitor") ?? .standard
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
}
