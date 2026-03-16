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
    private let lastFetchWasCacheKey = "cached_password_info_last_fetch_cache"
    private let sharedDefaults = UserDefaults(suiteName: "popo.PasswordMonitor")

    private init() {}

    /// Zapisuje ostatnio znane informacje o haśle
    public func save(_ info: PasswordInfo) {
        do {
            let data = try JSONEncoder().encode(info)
            sharedDefaults?.set(data, forKey: infoKey)
            UserDefaults.standard.set(data, forKey: infoKey)
        } catch {
            Logger.shared.logLocalized("log_cache_save_error %@", String(describing: error))
        }
    }

    public func markLastFetchWasCache(_ value: Bool) {
        sharedDefaults?.set(value, forKey: lastFetchWasCacheKey)
        UserDefaults.standard.set(value, forKey: lastFetchWasCacheKey)
    }

    public func lastFetchWasCache() -> Bool {
        if let value = sharedDefaults?.object(forKey: lastFetchWasCacheKey) as? Bool {
            return value
        }
        return UserDefaults.standard.bool(forKey: lastFetchWasCacheKey)
    }

    /// Odczytuje informacje o haśle z cache (jeśli istnieją)
    public func load() -> PasswordInfo? {
        let data = sharedDefaults?.data(forKey: infoKey)
            ?? UserDefaults.standard.data(forKey: infoKey)

        guard let data else {
            return nil
        }

        do {
            var info = try JSONDecoder().decode(PasswordInfo.self, from: data)
            let refreshedDaysRemaining = PasswordExpirationMath.daysRemaining(until: info.expiryDate)
            let isFromCache = lastFetchWasCache()

            // Recompute remaining days so cached values do not drift from the alert logic.
            info = PasswordInfo(
                lastSetDate: info.lastSetDate,
                daysUntilExpiration: refreshedDaysRemaining,
                expiryDate: info.expiryDate,
                isFromCache: isFromCache
            )

            // Keep the shared cache warm so the helper sees the same fallback after reboot/login.
            save(info)

            return info
        } catch {
            Logger.shared.logLocalized("log_cache_read_error %@", String(describing: error))
            return nil
        }
    }
}
