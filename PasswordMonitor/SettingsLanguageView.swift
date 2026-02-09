//
//  SettingsLanguageView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 09/02/2026.
//
//  Language selection UI with segmented picker.
//

import SwiftUI

struct SettingsLanguageView: View {
    @EnvironmentObject var languageSettings: LanguageSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
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
                }
            }
            .frame(minWidth: 300, minHeight: 120)

            Text("Copyright (c) 2026 Kamil Popowicz. All rights reserved.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .navigationTitle("language_settings_title")
    }
}

#Preview {
    SettingsLanguageView()
        .environmentObject(LanguageSettings())
}
