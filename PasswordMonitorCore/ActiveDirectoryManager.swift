//
//  ActiveDirectoryManager.swift
//  PasswordMonitorCore
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import Foundation

/// Zarządza odczytem informacji o haśle z AD / lokalnego katalogu
public class ActiveDirectoryManager {

    private let maxPasswordAge = 30       // Dni
    private var warningThreshold: Int {
        let configuredThreshold = UserDefaults.standard.integer(forKey: "warning_threshold")
        return configuredThreshold > 0 ? configuredThreshold : 7
    }

    public init() {}

    // MARK: - Public API

    /// Główna metoda:
    /// 1. Próbuje pobrać dane z AD
    /// 2. Gdy AD niedostępne / błąd – próbuje lokalnego `passwordLastSetTime`
    /// 3. Gdy oba źródła zawiodą – próbuje z cache
    public func getPasswordInfo(for username: String) throws -> PasswordInfo {
        if let configuredDomain = SystemADDomainResolver.currentDomain() {
            Logger.shared.logLocalized("log_ad_domain_requested %@", maskDomainPartial(configuredDomain))
            let resolvedNode = SystemADDomainResolver.adNodeName(for: configuredDomain)
            let candidatePaths = buildADNodePaths(configuredDomain: configuredDomain, resolvedNode: resolvedNode)
            if let resolvedNode, resolvedNode.caseInsensitiveCompare(configuredDomain) != .orderedSame {
                Logger.shared.logLocalized("log_ad_node_selected %@", maskDomainPartial(resolvedNode))
            } else if resolvedNode == nil {
                Logger.shared.logLocalized("log_ad_node_fallback %@", "All Domains")
            }

            do {
                var lastError: Error?
                for path in candidatePaths {
                    do {
                        let info = try getPasswordInfoFromAD(username: username, nodePath: path)
                        PasswordCache.shared.markLastFetchWasCache(false)
                        PasswordCache.shared.save(info)
                        return info
                    } catch {
                        lastError = error
                    }
                }
                if let lastError {
                    throw lastError
                }
            } catch {
                Logger.shared.logLocalized("log_ad_read_error %@", String(describing: error))
            }
        } else {
            Logger.shared.logLocalized("log_ad_no_domain_configured")

            // Jeśli nie ma domeny, spróbuj lokalnego Open Directory
            do {
                let info = try getPasswordInfoLocal(username: username)
                PasswordCache.shared.markLastFetchWasCache(false)
                PasswordCache.shared.save(info)
                return info
            } catch {
                Logger.shared.logLocalized("log_ad_local_read_error %@", String(describing: error))
            }
        }

        // 3. Ostateczny fallback: cache
        PasswordCache.shared.markLastFetchWasCache(true)
        if let cached = PasswordCache.shared.load() {
            Logger.shared.logLocalized("log_ad_using_cache")
            return cached
        }

        // 4. Nic się nie udało
        throw ADError.invalidData
    }

    /// Sprawdza czy trzeba pokazać ostrzeżenie
    public func shouldShowWarning(passwordInfo: PasswordInfo) -> Bool {
        let daysRemaining = PasswordExpirationMath.daysRemaining(until: passwordInfo.expiryDate)
        let shouldWarn = daysRemaining <= warningThreshold
        Logger.shared.log("Warning threshold check: daysRemaining=\(daysRemaining), thresholdDays=\(warningThreshold), shouldWarn=\(shouldWarn)")
        return shouldWarn
    }

    // MARK: - AD

    /// Pobiera SMBPasswordLastSet z AD
    private func getPasswordInfoFromAD(username: String, nodePath: String) throws -> PasswordInfo {
        Logger.shared.log("dscl query path: \(nodePath)")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        task.arguments = [
            nodePath,
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
        Logger.shared.logLocalized("log_dscl_local_output %@", output)

        // DEBUG stdout
        Logger.shared.logLocalized("log_dscl_output %@", output)

        let lastSetDate = try Self.parseSMBPasswordLastSet(from: output)
        return try calculateExpirationInfo(from: lastSetDate)
    }

    private func buildADNodePaths(configuredDomain: String, resolvedNode: String?) -> [String] {
        var paths = [String]()

        if let resolvedNode {
            paths.append("/Active Directory/\(resolvedNode)/All Domains")
            if resolvedNode.caseInsensitiveCompare(configuredDomain) != .orderedSame {
                paths.append("/Active Directory/\(configuredDomain)/All Domains")
            }
            return paths
        }

        paths.append("/Active Directory/All Domains")
        paths.append("/Search")
        paths.append("/Active Directory/\(configuredDomain)/All Domains")
        return paths
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

        let lastSetDate: Date
        if let date = parseDateString(timeString) {
            lastSetDate = date
        } else if let timestamp = Double(timeString) {
            lastSetDate = Date(timeIntervalSince1970: timestamp)
        } else if let timestamp = firstNumericTimestamp(in: timeString) {
            lastSetDate = Date(timeIntervalSince1970: timestamp)
        } else {
            throw ADError.invalidData
        }

        return try calculateExpirationInfo(from: lastSetDate)
    }

    // MARK: - Parsing (internal for tests)

    /// Parse: "SMBPasswordLastSet: 133123456789012345"
    static func parseSMBPasswordLastSet(from output: String) throws -> Date {
        let lines = output.components(separatedBy: .newlines)
        let matchingLines = lines.filter { $0.contains("SMBPasswordLastSet") }
        guard !matchingLines.isEmpty else {
            Logger.shared.logLocalized("log_dscl_password_last_set_missing")
            throw ADError.invalidData
        }

        if matchingLines.count > 1 {
            Logger.shared.log("Multiple SMBPasswordLastSet lines found: \(matchingLines.count). Selecting the latest timestamp.")
        }

        var latestTimestamp: Int64?
        var latestLine: String?

        for line in matchingLines {
            let components = line.components(separatedBy: ":")
            guard
                components.count >= 2,
                let lastSetRaw = components.last?.trimmingCharacters(in: .whitespacesAndNewlines),
                let lastSetInt = Int64(lastSetRaw)
            else {
                continue
            }

            if latestTimestamp == nil || lastSetInt > (latestTimestamp ?? 0) {
                latestTimestamp = lastSetInt
                latestLine = line
            }
        }

        guard let lastSetInt = latestTimestamp, let lastSetLine = latestLine else {
            Logger.shared.logLocalized("log_dscl_parse_failed %@", matchingLines.first ?? "unknown")
            throw ADError.invalidData
        }

        Logger.shared.logLocalized("log_dscl_found_line %@", lastSetLine)
        Logger.shared.logLocalized("log_dscl_parsed_timestamp %lld", lastSetInt)

        // Konwersja Windows FILETIME → UNIX timestamp
        let unixTimestamp = (lastSetInt / 10_000_000) - 11_644_473_600
        let lastSetDate = Date(timeIntervalSince1970: TimeInterval(unixTimestamp))

        Logger.shared.logLocalized("log_dscl_converted_date %@", String(describing: lastSetDate))
        return lastSetDate
    }

    private func parseDateString(_ value: String) -> Date? {
        let posix = Locale(identifier: "en_US_POSIX")

        let formatter1 = DateFormatter()
        formatter1.locale = posix
        formatter1.dateFormat = "MM/dd/yyyy HH:mm:ss"
        if let date = formatter1.date(from: value) { return date }

        let formatter2 = DateFormatter()
        formatter2.locale = posix
        formatter2.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        if let date = formatter2.date(from: value) { return date }

        let formatter3 = DateFormatter()
        formatter3.locale = posix
        formatter3.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter3.date(from: value) { return date }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: value)
    }

    private func firstNumericTimestamp(in value: String) -> TimeInterval? {
        let pattern = #"(?:\d{10,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range),
              let r = Range(match.range, in: value) else { return nil }
        return TimeInterval(value[r]) ?? nil
    }

    private func maskDomainPartial(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return String(repeating: "*", count: max(1, trimmed.count)) }
        let first = trimmed.prefix(1)
        let last = trimmed.suffix(2)
        let maskCount = max(0, trimmed.count - 3)
        return "\(first)\(String(repeating: "*", count: maskCount))\(last)"
    }

    // MARK: - Wspólna logika wygasania

    /// Oblicza dni do wygaśnięcia i buduje PasswordInfo
    private func calculateExpirationInfo(from lastSetDate: Date) throws -> PasswordInfo {
        try validateExpirationInfo(lastSetDate: lastSetDate)
        let expiryDate = Calendar.current.date(
            byAdding: .day,
            value: maxPasswordAge,
            to: lastSetDate
        ) ?? lastSetDate

        let daysUntilExpiration = PasswordExpirationMath.daysRemaining(until: expiryDate)
        try validateExpirationRange(daysUntilExpiration: daysUntilExpiration)

        return PasswordInfo(
            lastSetDate: lastSetDate,
            daysUntilExpiration: daysUntilExpiration,
            expiryDate: expiryDate
        )
    }

    private func validateExpirationInfo(lastSetDate: Date) throws {
        let now = Date()
        let futureLimit = now.addingTimeInterval(24 * 3600)
        if lastSetDate > futureLimit {
            Logger.shared.log("Invalid lastSetDate: in the future (\(lastSetDate))")
            throw ADError.invalidData
        }
    }

    private func validateExpirationRange(daysUntilExpiration: Int) throws {
        let minimumOverdue = max(maxPasswordAge * 2, 90)
        if daysUntilExpiration < -minimumOverdue {
            Logger.shared.log("Invalid expiration range: daysUntilExpiration=\(daysUntilExpiration)")
            throw ADError.invalidData
        }
    }
}
