//
//  ActiveDirectoryManager.swift
//  PasswordMonitorCore
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import Foundation

/// Zarządza odczytem informacji o haśle z AD / lokalnego katalogu
public class ActiveDirectoryManager {

    private let domainName = "BP-ITAKA"   // Twoja domena
    private let maxPasswordAge = 30       // Dni
    private let warningThreshold = 7      // Ostrzegaj od 7 dni

    public init() {}

    // MARK: - Connectivity

    /// Sprawdza połączenie z AD
    func checkADConnectivity() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        task.arguments = ["/Active Directory/\(domainName)/All Domains", "list", "/Users"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Public API

    /// Główna metoda:
    /// 1. Próbuje pobrać dane z AD
    /// 2. Gdy AD niedostępne / błąd – próbuje lokalnego `passwordLastSetTime`
    /// 3. Gdy oba źródła zawiodą – próbuje z cache
    public func getPasswordInfo(for username: String) throws -> PasswordInfo {
        // 1. Najpierw próba z AD
        if checkADConnectivity() {
            do {
                let info = try getPasswordInfoFromAD(username: username)
                // ✅ Zapisz do cache przy sukcesie
                PasswordCache.shared.save(info)
                return info
            } catch {
                Logger.shared.logLocalized("log_ad_read_error %@", String(describing: error))
                // Lecimy dalej do lokalnego fallbacku
            }
        } else {
            Logger.shared.logLocalized("log_ad_no_connection %@", domainName)
        }

        // 2. Fallback do lokalnego Open Directory
        do {
            let info = try getPasswordInfoLocal(username: username)
            // ✅ Zapisz do cache przy sukcesie
            PasswordCache.shared.save(info)
            return info
        } catch {
            Logger.shared.logLocalized("log_ad_local_read_error %@", String(describing: error))
        }

        // 3. Ostateczny fallback: cache
        if let cached = PasswordCache.shared.load() {
            Logger.shared.logLocalized("log_ad_using_cache")
            return cached
        }

        // 4. Nic się nie udało
        throw ADError.invalidData
    }

    /// Sprawdza czy trzeba pokazać ostrzeżenie
    public func shouldShowWarning(passwordInfo: PasswordInfo) -> Bool {
        return passwordInfo.daysUntilExpiration <= warningThreshold
    }

    // MARK: - AD

    /// Pobiera SMBPasswordLastSet z AD
    private func getPasswordInfoFromAD(username: String) throws -> PasswordInfo {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        task.arguments = [
            "/Active Directory/\(domainName)/All Domains",
            "-read",
            "/Users/\(username)",
            "SMBPasswordLastSet"
        ]

        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe

        try task.run()
        task.waitUntilExit()

        // DEBUG stderr
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
            Logger.shared.logLocalized("log_dscl_stderr %@", errorOutput)
        }

        guard task.terminationStatus == 0 else {
            Logger.shared.logLocalized("log_dscl_exit_code %d", task.terminationStatus)
            throw ADError.commandFailed("dscl failed with code \(task.terminationStatus)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ADError.invalidData
        }

        // DEBUG stdout
        Logger.shared.logLocalized("log_dscl_output %@", output)

        // Parse: "SMBPasswordLastSet: 133123456789012345"
        let lines = output.components(separatedBy: .newlines)
        guard let lastSetLine = lines.first(where: { $0.contains("SMBPasswordLastSet") }) else {
            Logger.shared.logLocalized("log_dscl_password_last_set_missing")
            throw ADError.invalidData
        }

        Logger.shared.logLocalized("log_dscl_found_line %@", lastSetLine)

        let components = lastSetLine.components(separatedBy: ":")
        guard
            components.count >= 2,
            let lastSetRaw = components.last?.trimmingCharacters(in: .whitespacesAndNewlines),
            let lastSetInt = Int64(lastSetRaw)
        else {
            Logger.shared.logLocalized("log_dscl_parse_failed %@", lastSetLine)
            throw ADError.invalidData
        }

        Logger.shared.logLocalized("log_dscl_parsed_timestamp %lld", lastSetInt)

        // Konwersja Windows FILETIME → UNIX timestamp
        let unixTimestamp = (lastSetInt / 10_000_000) - 11_644_473_600
        let lastSetDate = Date(timeIntervalSince1970: TimeInterval(unixTimestamp))

        Logger.shared.logLocalized("log_dscl_converted_date %@", String(describing: lastSetDate))

        return calculateExpirationInfo(from: lastSetDate)
    }

    // MARK: - Lokalny fallback

    /// Fallback: lokalny passwordLastSetTime
    private func getPasswordInfoLocal(username: String) throws -> PasswordInfo {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        task.arguments = [
            ".",
            "-read",
            "/Users/\(username)",
            "passwordLastSetTime"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw ADError.userNotFound
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ADError.invalidData
        }

        // Parse timestamp lub data string
        guard let timeString = output
            .components(separatedBy: "passwordLastSetTime:")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw ADError.invalidData
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"

        let lastSetDate: Date
        if let date = formatter.date(from: timeString) {
            lastSetDate = date
        } else if let timestamp = Double(timeString) {
            lastSetDate = Date(timeIntervalSince1970: timestamp)
        } else {
            throw ADError.invalidData
        }

        return calculateExpirationInfo(from: lastSetDate)
    }

    // MARK: - Wspólna logika wygasania

    /// Oblicza dni do wygaśnięcia i buduje PasswordInfo
    private func calculateExpirationInfo(from lastSetDate: Date) -> PasswordInfo {
        let expiryDate = Calendar.current.date(
            byAdding: .day,
            value: maxPasswordAge,
            to: lastSetDate
        ) ?? lastSetDate

        let daysUntilExpiration = Calendar.current.dateComponents(
            [.day],
            from: Date(),
            to: expiryDate
        ).day ?? 0

        return PasswordInfo(
            lastSetDate: lastSetDate,
            daysUntilExpiration: daysUntilExpiration,
            expiryDate: expiryDate
        )
    }
}
