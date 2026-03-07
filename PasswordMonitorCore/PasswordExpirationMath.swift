//
//  PasswordExpirationMath.swift
//  PasswordMonitorCore
//

import Foundation

public enum PasswordExpirationMath {
    public static func daysRemaining(
        until expirationDate: Date,
        from referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        calendar.dateComponents([.day], from: referenceDate, to: expirationDate).day ?? 0
    }
}
