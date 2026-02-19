//
//  Logger.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//


import Foundation

/// Shared logger dla obu targets
public class Logger {
    public enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private let logFileURL: URL
    private static let cacheLock = NSLock()
    private static var cachedBundle: (code: String, bundle: Bundle)?
    private let maxBytes: Int = 1_000_000
    
    public static let shared = Logger()

    public var fileURL: URL {
        logFileURL
    }

    public init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        logFileURL = homeDir.appendingPathComponent(".password_monitor.log")
    }
    
    public func log(_ message: String, level: Level = .info) {
        if Self.isMinimalLoggingEnabled, level == .debug { return }

        let timestamp = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .short,
            timeStyle: .medium
        )
        let maskedMessage = Self.maskSensitive(message)
        let logMessage = "[\(timestamp)] [\(level.rawValue)] \(maskedMessage)\n"
        
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                rotateIfNeeded(appendBytes: data.count)
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
        
        // Też print do stdout dla debugging
        print(logMessage, terminator: "")
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

    private func rotateIfNeeded(appendBytes: Int) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? NSNumber else { return }

        if size.intValue + appendBytes <= maxBytes { return }

        let rotatedURL = logFileURL.deletingPathExtension().appendingPathExtension("log.1")
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: logFileURL, to: rotatedURL)
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    private static func localizedString(_ key: String, _ arguments: [CVarArg]) -> String {
        let languageCode = UserDefaults.standard.string(forKey: "appLanguage")
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"

        let bundle = localizedBundle(for: languageCode)
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)

        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: languageCode), arguments: arguments)
    }

    private static func localizedBundle(for languageCode: String) -> Bundle {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cachedBundle, cached.code == languageCode {
            return cached.bundle
        }

        if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            cachedBundle = (languageCode, bundle)
            return bundle
        }

        cachedBundle = (languageCode, .main)
        return .main
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

        let domain = UserDefaults.standard.string(forKey: "ad_domain") ?? ""
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
