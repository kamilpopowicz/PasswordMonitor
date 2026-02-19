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
                    Picker("language_picker_label", selection: $languageSettings.selectedLanguage) {
                        ForEach(LanguageSettings.AppLanguage.allCases) { language in
                            Text(language.displayName)
                                .tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("language_change_footnote")
                        .font(.caption)
                        .italic()
                        .foregroundColor(PMTheme.textSecondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding()

            Divider()

            VStack(spacing: 2) {
                Text("Copyright (c) 2026 Kamil Popowicz. All rights reserved.")
            }
            .font(.caption2)
            .foregroundColor(PMTheme.textSecondary)
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .navigationTitle("language_settings_title")
        // Window panel and min size are applied at the Window level.
    }
}

#Preview {
    SettingsLanguageView()
        .environmentObject(LanguageSettings())
}
