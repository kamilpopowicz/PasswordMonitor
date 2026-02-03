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
            // Upewnij się, że flaga isFromCache jest ustawiona
            info = PasswordInfo(
                lastSetDate: info.lastSetDate,
                expiryDate: info.expiryDate,
                daysUntilExpiration: info.daysUntilExpiration,
                isFromCache: true
            )
            return info
        } catch {
            print("⚠️ PasswordCache: błąd odczytu cache: \(error)")
            return nil
        }
    }
}