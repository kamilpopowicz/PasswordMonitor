//
//  LanguageSettings.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 09/02/2026.
//
//  Manages app language switching with runtime locale propagation.
//

import SwiftUI
import NaturalLanguage
import Combine
import Foundation
import ObjectiveC
import PasswordMonitorCore

extension Notification.Name {
    static let appLanguageChanged = Notification.Name("appLanguageChanged")
}

/// Centralized language manager for the app
/// Persists user selection to UserDefaults and provides observable locale
final class LanguageSettings: ObservableObject {
    private let languageKey = "appLanguage"
    private let defaults = UserDefaults.standard
    private static let cacheLock = NSLock()
    private static var cachedBundle: (code: String, bundle: Bundle)?
    private static var cachedTranslations: [String: [String: String]] = [:]
    private static let formatTokenRegex = try! NSRegularExpression(
        pattern: "%(?:#@[^@]+@|(?:\\d+\\$)?[-+ #0']*(?:\\d+|\\*)?(?:\\.(?:\\d+|\\*))?(?:hh|h|ll|l|L|z|j|t)?[@diuoxXfFeEgGaAcCsSp%])"
    )

    /// Backing storage for language code - must be stored property for @Observable bindings
    @Published private var storedLanguage: String

    /// Current locale used by SwiftUI environment
    var locale: Locale {
        Locale(identifier: storedLanguage)
    }

    enum AppLanguage: String, CaseIterable, Identifiable {
        case polish = "pl"
        case english = "en"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .polish: return "Polski"
            case .english: return "English"
            }
        }
    }

    /// Selected language with UserDefaults persistence
    var selectedLanguage: AppLanguage? {
        AppLanguage(rawValue: storedLanguage)
    }

    var selectedLanguageCode: String {
        get { storedLanguage }
        set {
            storedLanguage = newValue
            defaults.set(newValue, forKey: languageKey)
        }
    }

    init() {
        // Initialize from UserDefaults or system locale
        self.storedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
            ?? "en"

        LanguageSettings.enableCustomLocalization()

        NotificationCenter.default.addObserver(
            forName: .appLanguageChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let code = notification.userInfo?["code"] as? String {
                self.storedLanguage = code
            }
        }
    }

    func setLanguage(_ language: AppLanguage) {
        selectedLanguageCode = language.rawValue
    }

    func setLanguage(code: String) {
        selectedLanguageCode = code
    }

    /// Returns raw language code (ISO 639-1) when available.
    func detectLanguageCode(for text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    func displayName(for code: String) -> String {
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        return "\(name) (\(code.uppercased()))"
    }

    func availableLanguageOptions() -> [LanguageOption] {
        var options = AppLanguage.allCases.map { LanguageOption(code: $0.rawValue, displayName: $0.displayName) }
        if !options.contains(where: { $0.code == storedLanguage }) {
            options.append(LanguageOption(code: storedLanguage, displayName: displayName(for: storedLanguage)))
        }
        return options
    }

    /// Returns a localized string for the currently selected app language.
    /// - Parameters:
    ///   - key: Localization key in `Localizable.xcstrings`.
    ///   - arguments: Optional format arguments for `%@` / `%d` placeholders.
    static func localizedString(_ key: String, _ arguments: CVarArg...) -> String {
        let languageCode = UserDefaults.standard.string(forKey: "appLanguage")
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        let format = resolvedFormat(for: key, languageCode: languageCode, requiresFormatting: !arguments.isEmpty)

        guard !arguments.isEmpty else { return format }

        return String(format: format, locale: Locale(identifier: languageCode), arguments: arguments)
    }

    static func localizedString(_ key: String, languageCode: String, _ arguments: CVarArg...) -> String {
        let format = resolvedFormat(for: key, languageCode: languageCode, requiresFormatting: !arguments.isEmpty)
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

    private static func englishBundle() -> Bundle {
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    private static func resolvedFormat(for key: String, languageCode: String, requiresFormatting: Bool) -> String {
        let bundle = localizedBundle(for: languageCode)
        let base = englishBundle().localizedString(forKey: key, value: nil, table: nil)

        if let rawCustom = customTranslation(for: key, languageCode: languageCode) {
            let custom = sanitizeCustomTranslation(rawCustom, base: base)
            if custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return base
            }
            if requiresFormatting && base != key && !isFormatCompatible(custom, base: base) {
                return base
            }
            return custom
        }

        logMissingCustomTranslationIfNeeded(key: key, languageCode: languageCode)
        let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
        if shouldFallbackToBase(localized: localized, base: base, key: key, requiresFormatting: requiresFormatting) {
            return base
        }
        return localized
    }

    static func saveCustomTranslations(_ translations: [String: String], for languageCode: String) {
        var sanitized = translations
        _ = sanitizeLoadedTranslations(&sanitized)

        cacheLock.lock()
        cachedTranslations[languageCode] = sanitized
        cacheLock.unlock()

        guard let url = customTranslationsURL(for: languageCode) else {
            Logger.shared.log("Failed to save custom translations: unresolved path for \(languageCode)")
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: [.atomic])
        } catch {
            Logger.shared.log("Failed to save custom translations: \(error.localizedDescription)")
        }
    }

    static func loadCustomTranslations(for languageCode: String) -> [String: String]? {
        cacheLock.lock()
        if let cached = cachedTranslations[languageCode] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let url = customTranslationsURL(for: languageCode) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              var dict = object as? [String: String] else {
            return nil
        }

        var changed = false
        if sanitizeLoadedTranslations(&dict) {
            changed = true
        }
        if changed,
           let updated = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? updated.write(to: url, options: [.atomic])
        }

        cacheLock.lock()
        cachedTranslations[languageCode] = dict
        cacheLock.unlock()
        return dict
    }

    fileprivate static func customTranslation(for key: String, languageCode: String) -> String? {
        if let cached = cachedTranslations[languageCode] {
            if let value = cached[key] {
                return value
            }
            if let base = baseKey(for: key),
               let value = cached[base] {
                return value
            }
        }
        if let loaded = loadCustomTranslations(for: languageCode) {
            if let value = loaded[key] {
                return value
            }
            if let base = baseKey(for: key),
               let value = loaded[base] {
                return value
            }
        }
        return nil
    }

    private static func customTranslationsURL(for languageCode: String) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.shared.log("Custom localization path unavailable (Application Support not found)")
            return nil
        }
        let dir = base.appendingPathComponent("PasswordMonitor/Localization", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                Logger.shared.log("Failed to create localization directory: \(error.localizedDescription)")
                return nil
            }
        }
        return dir.appendingPathComponent("Localizable-\(languageCode).json")
    }

    private static var customLocalizationEnabled = false
    fileprivate static var missingKeyLogCount = 0
    fileprivate static let missingKeyLogLimit = 20

    fileprivate static func logMissingCustomTranslationIfNeeded(key: String, languageCode: String) {
        guard languageCode != "en" else { return }
        guard missingKeyLogCount < missingKeyLogLimit else { return }
        missingKeyLogCount += 1
        Logger.shared.log("Missing custom translation for key: \(key)")
    }

    static func enableCustomLocalization() {
        guard !customLocalizationEnabled else { return }
        object_setClass(Bundle.main, PMCustomBundle.self)
        customLocalizationEnabled = true
    }

    static func currentLanguageCode() -> String {
        UserDefaults.standard.string(forKey: "appLanguage")
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
    }

    fileprivate static func baseKey(for key: String) -> String? {
        guard let range = key.range(of: " %") else { return nil }
        let base = String(key[..<range.lowerBound])
        return base.isEmpty ? nil : base
    }

    fileprivate static func sanitizeCustomTranslation(_ text: String, base: String) -> String {
        let hadNoFormatTokens = formatTokens(in: base).isEmpty
        var cleaned = text.replacingOccurrences(
            of: #"(?i)\s*[\[\{\(]{1,2}\s*PH\s*[_-]?\s*\d+\s*[\]\}\)]{1,2}"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?i)\bPH\s*[_-]?\s*\d+\b"#,
            with: "",
            options: .regularExpression
        )
        if hadNoFormatTokens {
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        cleaned = cleaned.replacingOccurrences(of: #"^\*\*(.+)\*\*$"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^__(.+)__$"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"`"#, with: "", options: .regularExpression)
        if looksLikeLocalizationKey(cleaned), cleaned != base {
            return ""
        }
        if hadNoFormatTokens {
            let hasWordLikeContent = cleaned.range(of: #"[[:alnum:]]"#, options: .regularExpression) != nil
            if !hasWordLikeContent {
                return ""
            }
        }
        return cleaned
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
        text.range(of: #"(?i)[\[\{\(]{1,2}\s*PH\s*[_-]?\s*\d+\s*[\]\}\)]{1,2}"#, options: .regularExpression) != nil
            || text.range(of: #"(?i)\bPH\s*[_-]?\s*\d+\b"#, options: .regularExpression) != nil
    }

    fileprivate static func shouldFallbackToBase(localized: String, base: String, key: String, requiresFormatting: Bool) -> Bool {
        if localized == key, base != key { return true }
        if hasPlaceholderMarker(localized) { return true }
        if looksLikeLocalizationKey(localized), localized != base { return true }
        if requiresFormatting && !isFormatCompatible(localized, base: base) { return true }
        return false
    }

    private static func sanitizeLoadedTranslations(_ translations: inout [String: String]) -> Bool {
        let en = englishBundle()
        var changed = false
        var keysToRemove: [String] = []
        for (key, value) in translations {
            let base = en.localizedString(forKey: key, value: nil, table: nil)
            let sanitized = sanitizeCustomTranslation(value, base: base)
            if sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                keysToRemove.append(key)
                changed = true
                continue
            }
            if sanitized != value {
                translations[key] = sanitized
                changed = true
            }
        }
        for key in keysToRemove {
            translations.removeValue(forKey: key)
        }
        return changed
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
}

struct LanguageOption: Identifiable, Hashable {
    let code: String
    let displayName: String

    var id: String { code }
}

private final class PMCustomBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let languageCode = LanguageSettings.currentLanguageCode()
        let localized = super.localizedString(forKey: key, value: value, table: tableName)
        let english = Bundle.main.path(forResource: "en", ofType: "lproj")
            .flatMap(Bundle.init(path:))?
            .localizedString(forKey: key, value: value, table: tableName) ?? localized
        let base = LanguageSettings.shouldFallbackToBase(
            localized: localized,
            base: english,
            key: key,
            requiresFormatting: false
        ) ? english : localized
        if let custom = LanguageSettings.customTranslation(for: key, languageCode: languageCode) {
            let sanitized = LanguageSettings.sanitizeCustomTranslation(custom, base: base)
            if sanitized.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                return base
            }
            return sanitized
        }
        if let baseKey = LanguageSettings.baseKey(for: key),
           let custom = LanguageSettings.customTranslation(for: baseKey, languageCode: languageCode) {
            let sanitized = LanguageSettings.sanitizeCustomTranslation(custom, base: base)
            if sanitized.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                return base
            }
            return sanitized
        }
        LanguageSettings.logMissingCustomTranslationIfNeeded(key: key, languageCode: languageCode)
        return base
    }
}
