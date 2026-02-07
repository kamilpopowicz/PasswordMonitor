//
//  SettingsLanguageView.swift
//  PasswordMonitor
//
//  Language selection UI with segmented picker.
//

import SwiftUI

struct SettingsLanguageView: View {
    @Environment(LanguageSettings.self) private var languageSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Create Bindable wrapper to enable $ binding syntax for @Observable
        @Bindable var settings = languageSettings

        Form {
            Section {
                Picker("Language", selection: $settings.selectedLanguage) {
                    ForEach(LanguageSettings.AppLanguage.allCases) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("language_change_footnote")
                    .font(.caption)
            }
        }
        .navigationTitle("language_settings_title")
        .frame(minWidth: 300, minHeight: 120)
    }
}

#Preview {
    SettingsLanguageView()
        .environment(LanguageSettings())
}
