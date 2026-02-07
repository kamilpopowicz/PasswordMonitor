//
//  LanguageSettings.swift
//  PasswordMonitor
//
//  Manages app language switching with runtime locale propagation.
//

import SwiftUI
import NaturalLanguage

/// Centralized language manager for the app
/// Persists user selection to UserDefaults and provides observable locale
@Observable
final class LanguageSettings {
    private let languageKey = "appLanguage"
    private let defaults = UserDefaults.standard

    /// Backing storage for language code - must be stored property for @Observable bindings
    private var storedLanguage: String

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
}
