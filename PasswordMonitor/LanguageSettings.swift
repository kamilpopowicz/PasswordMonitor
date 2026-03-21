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
    var selectedLanguage: AppLanguage {
        get { AppLanguage(rawValue: storedLanguage) ?? .english }
        set {
            storedLanguage = newValue.rawValue
            defaults.set(newValue.rawValue, forKey: languageKey)
        }
    }

    init() {
        // Initialize from UserDefaults or system locale
        self.storedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"

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
        selectedLanguage = language
    }

    /// Detects language of input text using NaturalLanguage framework
    /// Returns detected AppLanguage if confident, nil otherwise
    func detectLanguage(for text: String) -> AppLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let dominant = recognizer.dominantLanguage else { return nil }

        switch dominant.rawValue {
        case "pl": return .polish
        case "en": return .english
        default: return nil
        }
    }

    /// Returns a localized string for the currently selected app language.
    /// - Parameters:
    ///   - key: Localization key in `Localizable.xcstrings`.
    ///   - arguments: Optional format arguments for `%@` / `%d` placeholders.
    static func localizedString(_ key: String, _ arguments: CVarArg...) -> String {
        let languageCode = UserDefaults.standard.string(forKey: "appLanguage")
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"

        let bundle = localizedBundle(for: languageCode)
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)

        guard !arguments.isEmpty else { return format }

        return String(format: format, locale: Locale(identifier: languageCode), arguments: arguments)
    }

    static func localizedString(_ key: String, languageCode: String, _ arguments: CVarArg...) -> String {
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
}
