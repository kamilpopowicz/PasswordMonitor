//
//  PasswordInfo.swift
//  PasswordMonitorCore
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import Foundation

/// Model informacji o haśle
public struct PasswordInfo: Codable {
    /// Data ostatniej zmiany hasła
    public let lastSetDate: Date
    /// Liczba dni do wygaśnięcia (może być ujemna, jeśli hasło już wygasło)
    public let daysUntilExpiration: Int
    /// Data wygaśnięcia hasła
    public let expiryDate: Date
    /// Czy dane pochodzą z cache (ostatnio znane, nie z bieżącego odczytu AD)
    public let isFromCache: Bool

    /// Aktualna liczba dni do wygaśnięcia liczona z daty wygaśnięcia.
    public var currentDaysUntilExpiration: Int {
        PasswordExpirationMath.daysRemaining(until: expiryDate)
    }

    /// Czy hasło jest już wygasłe (pochodna od daysUntilExpiration)
    public var isExpired: Bool {
        currentDaysUntilExpiration <= 0
    }

    public init(
        lastSetDate: Date,
        daysUntilExpiration: Int,
        expiryDate: Date,
        isFromCache: Bool = false
    ) {
        self.lastSetDate = lastSetDate
        self.daysUntilExpiration = daysUntilExpiration
        self.expiryDate = expiryDate
        self.isFromCache = isFromCache
    }
}

/// Błędy AD
public enum ADError: Error {
    case notConnected
    case userNotFound
    case invalidData
    case commandFailed(String)
}
