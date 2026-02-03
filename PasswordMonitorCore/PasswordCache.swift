//
//  PasswordCache.swift
//  PasswordMonitorCore
//
//  Created by Kamil Popowicz on 03/02/2026.
//

import Foundation

/// Cache informacji o haśle zapisany w UserDefaults (lokalnie na Macu)
public final class PasswordCache {
    public static let shared = PasswordCache()

    // Używamy osobnego klucza dla struct PasswordInfo
    private let infoKey = "cached_password_info"

    private init() {}

    /// Zapisuje ostatnio znane informacje o haśle
    public func save(_ info: PasswordInfo) {
        do {
            let data = try JSONEncoder().encode(info)
            UserDefaults.standard.set(data, forKey: infoKey)
        } catch {
            print("⚠️ PasswordCache: błąd zapisu cache: \(error)")
        }
    }

    /// Odczytuje informacje o haśle z cache (jeśli istnieją)
    public func load() -> PasswordInfo? {
        guard let data = UserDefaults.standard.data(forKey: infoKey) else {
            return nil
        }

        do {
            var info = try JSONDecoder().decode(PasswordInfo.self, from: data)

            // Upewnij się, że przy odczycie oznaczamy dane jako pochodzące z cache
            info = PasswordInfo(
                lastSetDate: info.lastSetDate,
                daysUntilExpiration: info.daysUntilExpiration,
                expiryDate: info.expiryDate,
                isFromCache: true
            )

            return info
        } catch {
            print("⚠️ PasswordCache: błąd odczytu cache: \(error)")
            return nil
        }
    }
}
