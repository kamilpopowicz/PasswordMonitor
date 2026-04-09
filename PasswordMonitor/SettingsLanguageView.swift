//
//  SettingsLanguageView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 09/02/2026.
//
//  Language selection UI with segmented picker.
//

import SwiftUI
import PasswordMonitorCore

struct SettingsLanguageView: View {
    @EnvironmentObject var languageSettings: LanguageSettings
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker(selection: $languageSettings.selectedLanguageCode) {
                        ForEach(languageSettings.availableLanguageOptions()) { option in
                            Text(option.displayName)
                                .tag(option.code)
                        }
                    } label: {
                        Text(LanguageSettings.localizedString("language_picker_label"))
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(LanguageSettings.localizedString("language_change_footnote"))
                        .font(.caption)
                        .italic()
                        .foregroundColor(PMTheme.textSecondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding()

            Divider()

            PMWindowFooter()
        }
        .navigationTitle(LanguageSettings.localizedString("language_settings_title"))
        // Window panel and min size are applied at the Window level.
    }
}

#if DEBUG
#Preview {
    SettingsLanguageView()
        .environmentObject(LanguageSettings())
}
#endif
