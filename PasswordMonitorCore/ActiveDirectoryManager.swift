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
    private let currentDomain: () -> String?
    private let adNodeName: (String) -> String?
    private let adOutputReader: (_ username: String, _ nodePath: String) throws -> String
    private let localOutputReader: (_ username: String) throws -> String
    private var warningThreshold: Int {
        let configuredThreshold = UserDefaults.standard.integer(forKey: "warning_threshold")
        return configuredThreshold > 0 ? configuredThreshold : 7
    }

    public convenience init() {
        self.init(
            currentDomain: SystemADDomainResolver.currentDomain,
            adNodeName: SystemADDomainResolver.adNodeName(for:),
            adOutputReader: Self.readADPasswordLastSet(username:nodePath:),
            localOutputReader: Self.readLocalPasswordLastSet(username:)
        )
    }

    init(
        currentDomain: @escaping () -> String?,
        adNodeName: @escaping (String) -> String?,
        adOutputReader: @escaping (_ username: String, _ nodePath: String) throws -> String,
        localOutputReader: @escaping (_ username: String) throws -> String
    ) {
        self.currentDomain = currentDomain
        self.adNodeName = adNodeName
        self.adOutputReader = adOutputReader
        self.localOutputReader = localOutputReader
    }

    // MARK: - Public API

    /// Główna metoda:
    /// 1. Próbuje pobrać dane z AD
    /// 2. Gdy AD niedostępne / błąd – próbuje lokalnego `passwordLastSetTime`
    /// 3. Gdy oba źródła zawiodą – próbuje z cache
    public func getPasswordInfo(for username: String) throws -> PasswordInfo {
        if let configuredDomain = currentDomain() {
            Logger.shared.logLocalized("log_ad_domain_requested %@", maskDomainPartial(configuredDomain))
            let resolvedNode = adNodeName(configuredDomain)
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
                        Logger.shared.log("AD password source accepted: \(sourceKind(for: path))")
                        PasswordCache.shared.markLastFetchWasCache(false)
                        PasswordCache.shared.save(info)
                        return info
                    } catch {
                        Logger.shared.log(
                            "AD password source rejected: \(sourceKind(for: path)) (\(safeADErrorDescription(error)))",
                            level: .warning
                        )
                        lastError = error
                    }
                }
                if let lastError {
                    throw lastError
                }
            } catch {
                Logger.shared.log(
                    "AD password read failed (\(safeADErrorDescription(error)))",
                    level: .warning
                )
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
                Logger.shared.log(
                    "Local password status read failed (\(safeADErrorDescription(error)))",
                    level: .warning
                )
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
        let output = try adOutputReader(username, nodePath)
        let lastSetDate = try Self.parseSMBPasswordLastSet(from: output)
        return try calculateExpirationInfo(from: lastSetDate)
    }

    private func sourceKind(for path: String) -> String {
        if path == "/Search" {
            return "search"
        }
        if path == "/Active Directory/All Domains" {
            return "allDomains"
        }
        if path.hasPrefix("/Active Directory/") {
            return "activeDirectoryNode"
        }
        return "unknown"
    }

    private func safeADErrorDescription(_ error: Error) -> String {
        guard let adError = error as? ADError else {
            return "unexpectedError"
        }
        switch adError {
        case .notConnected:
            return "notConnected"
        case .userNotFound:
            return "userNotFound"
        case .invalidData:
            return "invalidData"
        case .commandFailed:
            return "commandFailed"
        }
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
        let output = try localOutputReader(username)

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

    private static func readADPasswordLastSet(username: String, nodePath: String) throws -> String {
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

        _ = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard task.terminationStatus == 0 else {
            Logger.shared.logLocalized("log_dscl_exit_code %d", task.terminationStatus)
            throw ADError.commandFailed("dscl failed with code \(task.terminationStatus)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ADError.invalidData
        }
        return output
    }

    private static func readLocalPasswordLastSet(username: String) throws -> String {
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
        return output
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
            }
        }

        guard let lastSetInt = latestTimestamp else {
            Logger.shared.log("SMBPasswordLastSet parse failed", level: .warning)
            throw ADError.invalidData
        }

        // Konwersja Windows FILETIME → UNIX timestamp
        let unixTimestamp = (lastSetInt / 10_000_000) - 11_644_473_600
        let lastSetDate = Date(timeIntervalSince1970: TimeInterval(unixTimestamp))

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
            Logger.shared.log("Invalid lastSetDate: in the future", level: .warning)
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
