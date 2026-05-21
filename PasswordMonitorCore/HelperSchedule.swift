//
//  HelperSchedule.swift
//  PasswordMonitorCore
//
//  Created by Codex on 07/03/2026.
//

import Foundation

public enum HelperRefreshReason: String {
    case launch
    case wake
    case timer
    case scheduledTime = "scheduled_time"
    case manual
}

public enum HelperMessaging {
    public static let forceRefreshNotification = Notification.Name("PasswordMonitor.HelperForceRefresh")
    public static let settingsDidChangeNotification = Notification.Name("PasswordMonitor.HelperSettingsDidChange")
    public static let passwordChangeRequestedNotification = Notification.Name("PasswordMonitor.PasswordChangeRequested")
}

public enum HelperSchedule {
    public static func nextOccurrence(for timeString: String, after date: Date, calendar: Calendar = .current) -> Date {
        let (hour, minute) = hourAndMinute(from: timeString, defaultHour: 9, defaultMinute: 0)

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0

        let candidate = calendar.date(from: components) ?? date
        if candidate > date {
            return candidate
        }

        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? date.addingTimeInterval(24 * 3600)
    }

    public static func scheduledSlotID(for date: Date, timeString: String, calendar: Calendar = .current) -> String {
        let (hour, minute) = hourAndMinute(from: timeString, defaultHour: 9, defaultMinute: 0)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d@%02d:%02d", year, month, day, hour, minute)
    }

    public static func triggerBucketID(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(format: "%04d-%02d-%02d@%02d:%02d", year, month, day, hour, minute)
    }

    public static func isWithinQuietHours(
        date: Date,
        startTime: String,
        endTime: String,
        calendar: Calendar = .current
    ) -> Bool {
        let start = minutesFromTimeString(startTime)
        let end = minutesFromTimeString(endTime)
        let now = minutesSinceMidnight(for: date, calendar: calendar)

        if start == end {
            return false
        }

        if start < end {
            return now >= start && now <= end
        }

        return now >= start || now <= end
    }

    public static func minutesFromTimeString(_ timeString: String) -> Int {
        let (hour, minute) = hourAndMinute(from: timeString, defaultHour: 0, defaultMinute: 0)
        return (hour * 60) + minute
    }

    private static func minutesSinceMidnight(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return ((components.hour ?? 0) * 60) + (components.minute ?? 0)
    }

    private static func hourAndMinute(from timeString: String, defaultHour: Int, defaultMinute: Int) -> (Int, Int) {
        let parts = timeString.split(separator: ":")
        let hour = Int(parts.first ?? "") ?? defaultHour
        let minute = Int(parts.dropFirst().first ?? "") ?? defaultMinute
        return (hour, minute)
    }
}
