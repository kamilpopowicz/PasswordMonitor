//
//  Logger.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//


import Foundation
import Darwin

/// Shared logger dla obu targets
public final class Logger: @unchecked Sendable {
    public enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private let logFileURL: URL
    private let rotatedLogFileURL: URL
    private let lockFileURL: URL
    private let maxBytes: Int
    private let emitToStdout: Bool
    private static let fileAccessLock = NSLock()
    private static let cacheLock = NSLock()
    private static var cachedBundle: (code: String, bundle: Bundle)?
    private static let formatTokenRegex = try! NSRegularExpression(
        pattern: "%(?:#@[^@]+@|(?:\\d+\\$)?[-+ #0']*(?:\\d+|\\*)?(?:\\.(?:\\d+|\\*))?(?:hh|h|ll|l|L|z|j|t)?[@diuoxXfFeEgGaAcCsSp%])"
    )
    public static let shared = Logger()

    public var fileURL: URL {
        logFileURL
    }

    public convenience init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.init(
            fileURL: homeDir.appendingPathComponent(".password_monitor.log"),
            maxBytes: 1_000_000,
            emitToStdout: true
        )
    }

    init(fileURL: URL, maxBytes: Int, emitToStdout: Bool = false) {
        logFileURL = fileURL
        rotatedLogFileURL = fileURL.deletingPathExtension().appendingPathExtension("log.1")
        lockFileURL = fileURL.appendingPathExtension("lock")
        self.maxBytes = maxBytes
        self.emitToStdout = emitToStdout
        prepareLogFile()
    }
    
    public func log(_ message: String, level: Level = .info) {
        if Self.isMinimalLoggingEnabled, level == .debug { return }

        let timestamp = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .short,
            timeStyle: .medium
        )
        let sanitizedMessage = Self.sanitizeForSingleLineLog(Self.maskSensitive(message))
        let logMessage = "[\(timestamp)] [\(level.rawValue)] \(sanitizedMessage)\n"
        
        if let data = logMessage.data(using: .utf8) {
            _ = withExclusiveFileLock(fallback: false) {
                guard secureExistingLogFiles(),
                      rotateIfNeeded(appendBytes: data.count) else {
                    return false
                }
                return append(data)
            }
        }
        
        #if DEBUG
        if emitToStdout {
            print(logMessage, terminator: "")
        }
        #endif
    }

    public func logLocalized(_ key: String, _ arguments: CVarArg...) {
        let message = Self.localizedString(key, arguments)
        log(message)
    }

    public func logLocalized(_ key: String, level: Level, _ arguments: CVarArg...) {
        let message = Self.localizedString(key, arguments)
        log(message, level: level)
    }

    public static func localizedString(_ key: String, _ arguments: CVarArg...) -> String {
        localizedString(key, arguments)
    }

    public func prepareLogFile() {
        _ = withExclusiveFileLock(fallback: false) {
            secureExistingLogFiles()
        }
    }

    public func readContents() -> String {
        withExclusiveFileLock(fallback: "") {
            guard secureExistingLogFiles() else { return "" }
            guard let data = try? Data(contentsOf: logFileURL) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    @discardableResult
    public func clear() -> Bool {
        withExclusiveFileLock(fallback: false) {
            if FileManager.default.fileExists(atPath: rotatedLogFileURL.path) {
                do {
                    try FileManager.default.removeItem(at: rotatedLogFileURL)
                } catch {
                    return false
                }
            }
            let descriptor = open(logFileURL.path, O_CREAT | O_TRUNC | O_WRONLY, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { return false }
            defer { close(descriptor) }
            return fchmod(descriptor, S_IRUSR | S_IWUSR) == 0
        }
    }

    private func rotateIfNeeded(appendBytes: Int) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? NSNumber else { return true }

        if size.intValue + appendBytes <= maxBytes { return true }

        try? FileManager.default.removeItem(at: rotatedLogFileURL)
        do {
            try FileManager.default.moveItem(at: logFileURL, to: rotatedLogFileURL)
        } catch {
            return false
        }
        return secureFileIfPresent(at: rotatedLogFileURL) && ensureSecureFile(at: logFileURL)
    }

    private func append(_ data: Data) -> Bool {
        let descriptor = open(logFileURL.path, O_CREAT | O_APPEND | O_WRONLY, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { return false }
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return true }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written < 0, errno == EINTR {
                    continue
                }
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }

    private func secureExistingLogFiles() -> Bool {
        ensureSecureFile(at: logFileURL)
            && secureFileIfPresent(at: rotatedLogFileURL)
            && secureFileIfPresent(at: lockFileURL)
    }

    private func secureFileIfPresent(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        return chmod(url.path, S_IRUSR | S_IWUSR) == 0
    }

    private func ensureSecureFile(at url: URL) -> Bool {
        let descriptor = open(url.path, O_CREAT | O_APPEND | O_WRONLY, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return fchmod(descriptor, S_IRUSR | S_IWUSR) == 0
    }

    private func withExclusiveFileLock<T>(fallback: T, _ body: () -> T) -> T {
        Self.fileAccessLock.lock()
        defer { Self.fileAccessLock.unlock() }

        let descriptor = open(lockFileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return fallback }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }

        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { return fallback }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno == EINTR {
                continue
            }
            return fallback
        }
        return body()
    }

    private static func localizedString(_ key: String, _ arguments: [CVarArg]) -> String {
        let languageCode = UserDefaults.standard.string(forKey: "appLanguage")
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"

        let bundle = localizedBundle(for: languageCode)
        let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
        let baseFormat = englishFormat(for: key) ?? localized
        let format = (localized == key && baseFormat != key) ? baseFormat : localized

        guard !arguments.isEmpty else {
            if isBrokenLocalizedValue(format, key: key), baseFormat != key {
                return baseFormat
            }
            return format
        }

        let safeFormat = isFormatCompatible(format, base: baseFormat) ? format : baseFormat
        if isBrokenLocalizedValue(safeFormat, key: key), baseFormat != key {
            return baseFormat
        }
        guard containsFormatToken(safeFormat) else { return safeFormat }
        return String(format: safeFormat, locale: Locale(identifier: languageCode), arguments: arguments)
    }

    private static func localizedBundle(for languageCode: String) -> Bundle {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cachedBundle, cached.code == languageCode {
            return cached.bundle
        }

        if let bundle = bundleForLanguage(languageCode, in: Bundle.main) {
            cachedBundle = (languageCode, bundle)
            return bundle
        }

        if let hostBundle = hostAppBundle(), let bundle = bundleForLanguage(languageCode, in: hostBundle) {
            cachedBundle = (languageCode, bundle)
            return bundle
        }

        cachedBundle = (languageCode, .main)
        return .main
    }

    private static func bundleForLanguage(_ languageCode: String, in bundle: Bundle) -> Bundle? {
        guard let path = bundle.path(forResource: languageCode, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    private static func hostAppBundle() -> Bundle? {
        // Helper lives at .../PasswordMonitor.app/Contents/Library/LoginItems/PasswordMonitorHelperApp.app
        // Go up 4 levels to reach the host app bundle.
        var url = Bundle.main.bundleURL
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        guard url.pathExtension == "app" else {
            return nil
        }
        return Bundle(url: url)
    }

    private static func englishFormat(for key: String) -> String? {
        if let enBundle = bundleForLanguage("en", in: Bundle.main) {
            let format = enBundle.localizedString(forKey: key, value: nil, table: nil)
            if format != key { return format }
        }

        if let host = hostAppBundle(), let enBundle = bundleForLanguage("en", in: host) {
            let format = enBundle.localizedString(forKey: key, value: nil, table: nil)
            if format != key { return format }
        }

        return nil
    }

    private static func isFormatCompatible(_ candidate: String, base: String) -> Bool {
        let candidateTokens = formatTokens(in: candidate)
        let baseTokens = formatTokens(in: base)
        guard candidateTokens.count == baseTokens.count else { return false }

        for (lhs, rhs) in zip(candidateTokens, baseTokens) {
            guard let left = formatFamily(for: lhs), let right = formatFamily(for: rhs) else {
                if lhs != rhs { return false }
                continue
            }
            if left == right { continue }
            if (left == .plural && right == .integer) || (left == .integer && right == .plural) {
                continue
            }
            return false
        }
        return true
    }

    private static func containsFormatToken(_ format: String) -> Bool {
        !formatTokens(in: format).isEmpty
    }

    private static func looksLikeLocalizationKey(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(
            of: #"^[a-z0-9]+(?:_[a-z0-9]+)+(?:\s+%[-+ #0'\d\.\@\w]+)?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func hasPlaceholderMarker(_ text: String) -> Bool {
        text.range(of: #"(?i)\[{1,2}\s*PH\s*[_-]?\s*\d+\s*\]{1,2}"#, options: .regularExpression) != nil
    }

    private static func isBrokenLocalizedValue(_ text: String, key: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed == key { return true }
        if hasPlaceholderMarker(trimmed) { return true }
        if looksLikeLocalizationKey(trimmed) { return true }
        return false
    }

    private static func formatTokens(in format: String) -> [String] {
        let ns = format as NSString
        let range = NSRange(location: 0, length: ns.length)
        return formatTokenRegex.matches(in: format, range: range)
            .compactMap { match in
                guard match.range.location != NSNotFound else { return nil }
                let token = ns.substring(with: match.range)
                return token == "%%" ? nil : token
            }
    }

    private enum FormatFamily {
        case object
        case integer
        case floating
        case character
        case cString
        case pointer
        case plural
    }

    private static func formatFamily(for token: String) -> FormatFamily? {
        if token.hasPrefix("%#@"), token.hasSuffix("@") {
            return .plural
        }
        guard let conversion = token.last else { return nil }
        switch conversion {
        case "@":
            return .object
        case "d", "i", "u", "o", "x", "X":
            return .integer
        case "f", "F", "e", "E", "g", "G", "a", "A":
            return .floating
        case "c", "C":
            return .character
        case "s", "S":
            return .cString
        case "p":
            return .pointer
        default:
            return nil
        }
    }

    private static var isMinimalLoggingEnabled: Bool {
        let value = UserDefaults.standard.object(forKey: "minimal_logging") as? Bool
        return value ?? true
    }

    private static func maskSensitive(_ input: String) -> String {
        var result = input

        let username = NSUserName()
        if !username.isEmpty {
            result = result.replacingOccurrences(of: username, with: "<user>")
        }

        let fullName = NSFullUserName()
        if !fullName.isEmpty {
            result = result.replacingOccurrences(of: fullName, with: "<user>")
        }

        let domain = SystemADDomainResolver.currentDomain() ?? ""
        if !domain.isEmpty {
            result = result.replacingOccurrences(of: domain, with: "<domain>")
        }

        // /Users/<name> → /Users/<user>
        result = replaceRegex(
            pattern: "/Users/[^/\\s]+",
            in: result,
            with: "/Users/<user>"
        )

        // Email masking
        result = replaceRegex(
            pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
            in: result,
            with: "<email>",
            options: [.caseInsensitive]
        )

        // Domain / host masking
        result = replaceRegex(
            pattern: "\\b([A-Z0-9-]+\\.)+[A-Z]{2,}\\b",
            in: result,
            with: "<host>",
            options: [.caseInsensitive]
        )

        return result
    }

    private static func sanitizeForSingleLineLog(_ input: String) -> String {
        input.unicodeScalars.reduce(into: "") { result, scalar in
            switch scalar {
            case "\n":
                result.append("\\n")
            case "\r":
                result.append("\\r")
            case "\t":
                result.append("\\t")
            case _ where CharacterSet.controlCharacters.contains(scalar):
                result.append("\\u{\(String(scalar.value, radix: 16, uppercase: true))}")
            default:
                result.unicodeScalars.append(scalar)
            }
        }
    }

    private static func replaceRegex(
        pattern: String,
        in input: String,
        with replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: replacement)
    }
}
