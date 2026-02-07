//
//  SettingsLanguageView.swift
//  PasswordMonitor
//
//  Language selection UI with segmented picker.
//

import SwiftUI

struct SettingsLanguageView: View {
    @EnvironmentObject var languageSettings: LanguageSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $languageSettings.selectedLanguage) {
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
        .environmentObject(LanguageSettings())
}
