//
//  PasswordInfo.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//


import Foundation

/// Model informacji o haśle
public struct PasswordInfo {
    public let lastSetDate: Date
    public let daysUntilExpiration: Int
    public let expiryDate: Date
    public let isExpired: Bool
    
    public init(
        lastSetDate: Date,
        daysUntilExpiration: Int,
        expiryDate: Date,
        isExpired: Bool
    ) {
        self.lastSetDate = lastSetDate
        self.daysUntilExpiration = daysUntilExpiration
        self.expiryDate = expiryDate
        self.isExpired = isExpired
    }
}

/// Błędy AD
public enum ADError: Error {
    case notConnected
    case userNotFound
    case invalidData
    case commandFailed(String)
}
