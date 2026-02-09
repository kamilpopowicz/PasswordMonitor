//
//  SettingsView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import SwiftUI
import ServiceManagement
import Combine
import PasswordMonitorCore

private enum SettingsKeys {
    static let domainName = "ad_domain"
    static let maxPasswordAge = "max_password_age"
    static let warningThreshold = "warning_threshold"
    static let notificationHour = "notification_hour" // Format: "09:00"
    static let minimalLogging = "minimal_logging"
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var languageSettings: LanguageSettings

    // EDYTOWANE wartości (UI)
    @State private var launchAtLogin = false
    @State private var domainName = ""
    @State private var maxPasswordAge = 30
    @State private var warningThreshold = 7
    @State private var selectedLanguage: LanguageSettings.AppLanguage = .english
    @State private var minimalLogging = true
    @State private var languageAssistText = ""
    @State private var languageAssistCancellable: AnyCancellable?
    @State private var showLanguageSuggestion = false
    @State private var suggestedLanguage: LanguageSettings.AppLanguage?
    @State private var lastSuggestedLanguage: LanguageSettings.AppLanguage?

    // Godzina w UI
    @State private var notificationHourString = "09:00"
    @State private var notificationDate = Date()

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var helperStatus: SMAppService.Status = .notFound

    private let helperBundleID = "popo.PasswordMonitorHelperApp"

    // ZAPISANE wartości (AppStorage)
    @AppStorage(SettingsKeys.domainName) private var storedDomainName = ""
    @AppStorage(SettingsKeys.maxPasswordAge) private var storedMaxPasswordAge = 30
    @AppStorage(SettingsKeys.warningThreshold) private var storedWarningThreshold = 7
    @AppStorage(SettingsKeys.notificationHour) private var storedNotificationHour = "09:00"
    @AppStorage(SettingsKeys.minimalLogging) private var storedMinimalLogging = true

    var body: some View {
        VStack(spacing: 0) {
            // Główna zawartość ustawień
            ScrollView {
                Form {
                    // MARK: Powiadomienia
                    Section(header: Text("settings_section_notifications").font(.headline)) {
                        DatePicker(
                            "settings_notification_time",
                            selection: $notificationDate,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: notificationDate) { _, newValue in
                            // Konwersja Date -> String "HH:mm" dla EDYTOWANEJ wartości
                            notificationHourString = dateToTimeString(newValue) ?? "09:00"
                            Logger.shared.logLocalized("log_settings_notification_time_changed %@", notificationHourString)
                        }

                        Text("settings_notification_footnote")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    // MARK: Startup
                    Section(header: Text("settings_section_startup").font(.headline)) {
                        Toggle("settings_launch_at_login", isOn: $launchAtLogin)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(LanguageSettings.localizedString("settings_helper_desc %@", notificationHourString))
                            Text("settings_background_helper_info")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                    }

                    // MARK: Test powiadomień
                    Section {
                        Button("menu_test_notification") {
                            let testDate = Date().addingTimeInterval(23 * 3600)
                            NotificationManager.shared.showTestNotification(expirationDate: testDate)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }

                    // MARK: Active Directory
                    Section(header: Text("settings_section_ad").font(.headline)) {
                        TextField("settings_domain_name", text: $domainName)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Text("settings_max_password_age")
                            Spacer()
                            TextField("", value: $maxPasswordAge, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: maxPasswordAge) { _, newValue in
                                    if newValue < 1 { maxPasswordAge = 1 }
                                    if newValue > 365 { maxPasswordAge = 365 }
                                }
                        }

                        HStack {
                            Text("settings_warning_threshold")
                            Spacer()
                            TextField("", value: $warningThreshold, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: warningThreshold) { _, newValue in
                                    if newValue < 1 { warningThreshold = 1 }
                                    if newValue > maxPasswordAge {
                                        warningThreshold = maxPasswordAge
                                    }
                                }
                        }
                    }

                    // MARK: Język / Language
                    Section(header: Text("language_settings_title").font(.headline)) {
                        Picker("language_picker_label", selection: $selectedLanguage) {
                            ForEach(LanguageSettings.AppLanguage.allCases) { language in
                                Text(language.displayName)
                                    .tag(language)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("language_change_footnote")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    
                    // MARK: Language Assist (On-Device)
                    Section(header: Text("language_assist_title").font(.headline)) {
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $languageAssistText)
                                .font(.body)
                                .frame(minHeight: 80)
                                .padding(4)
                                .background(Color(NSColor.textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .onChange(of: languageAssistText) { _, newValue in
                                    debounceLanguageAssistChange(newValue)
                                }

                            if languageAssistText.isEmpty {
                                Text("language_assist_placeholder")
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    .allowsHitTesting(false)
                            }
                        }

                        Text("language_assist_footnote")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    // MARK: Prywatność / Logi
                    Section(header: Text("settings_section_privacy").font(.headline)) {
                        Toggle("settings_minimal_logging", isOn: $minimalLogging)

                        Text("settings_minimal_logging_footnote")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    // MARK: Informacje
                    Section(header: Text("settings_section_info").font(.headline)) {
                        HStack {
                            Text("settings_version")
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("settings_helper_status")
                            Spacer()
                            Circle()
                                .fill(helperStatusColor)
                                .frame(width: 10, height: 10)
                            Text(helperStatusDescriptionKey)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
                .padding()
            }

            // Dolny pasek przycisków
            HStack {
                Spacer()
                Button("common_cancel") {
                    cancelChanges()
                }
                Button("common_save") {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isDirty)
            }
            .padding([.horizontal, .bottom])

            Text("Copyright (c) 2026 Kamil Popowicz. All rights reserved.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear {
            loadSettings()
            appState.windowOpened()
        }
        .onDisappear {
            appState.windowClosed()
        }
        .alert("helper_alert_title", isPresented: $showAlert) {
            Button("common_ok") {}
        } message: {
            Text(alertMessage)
        }
        .alert("language_suggestion_title", isPresented: $showLanguageSuggestion) {
            Button("language_suggestion_switch") {
                guard let suggestedLanguage else { return }
                selectedLanguage = suggestedLanguage
                languageSettings.selectedLanguage = suggestedLanguage
            }
            Button("language_suggestion_keep", role: .cancel) {}
        } message: {
            if let suggestedLanguage {
                Text(LanguageSettings.localizedString("language_suggestion_message %@", suggestedLanguage.displayName))
            }
        }
    }

    /// Czy wartości edytowane różnią się od zapisanych
    private var isDirty: Bool {
        let savedLaunchAtLogin = (helperStatus == .enabled)
        return domainName != storedDomainName
            || maxPasswordAge != storedMaxPasswordAge
            || warningThreshold != storedWarningThreshold
            || notificationHourString != storedNotificationHour
            || launchAtLogin != savedLaunchAtLogin
            || selectedLanguage != languageSettings.selectedLanguage
            || minimalLogging != storedMinimalLogging
    }

    // MARK: - Helpers

    private func timeStringToDate(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: timeString)
    }

    private func dateToTimeString(_ date: Date) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var helperStatusColor: Color {
        switch helperStatus {
        case .enabled: return .green
        case .requiresApproval: return .orange
        case .notRegistered, .notFound: return .red
        @unknown default: return .gray
        }
    }

    private var helperStatusDescriptionKey: LocalizedStringKey {
        switch helperStatus {
        case .enabled: return LocalizedStringKey("status_active")
        case .notRegistered: return LocalizedStringKey("status_not_registered")
        case .requiresApproval: return LocalizedStringKey("status_requires_approval")
        case .notFound: return LocalizedStringKey("status_not_found")
        @unknown default: return LocalizedStringKey("status_unknown")
        }
    }

    private func loadSettings() {
        // AppStorage -> edytowane wartości
        domainName = storedDomainName
        maxPasswordAge = storedMaxPasswordAge
        warningThreshold = storedWarningThreshold
        notificationHourString = storedNotificationHour
        notificationDate = timeStringToDate(notificationHourString) ?? Date()
        selectedLanguage = languageSettings.selectedLanguage
        minimalLogging = storedMinimalLogging

        // Helper service status
        let service = SMAppService.loginItem(identifier: helperBundleID)
        helperStatus = service.status
        launchAtLogin = (service.status == .enabled)

        Logger.shared.logLocalized("log_settings_loaded_notification_time %@", notificationHourString)
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.loginItem(identifier: helperBundleID)
        do {
            if enabled {
                try service.register()
                Logger.shared.logLocalized("log_helper_registered")
                helperStatus = service.status
                if helperStatus == .requiresApproval {
                    alertMessage = LanguageSettings.localizedString("helper_requires_approval")
                } else {
                    alertMessage = LanguageSettings.localizedString("helper_enabled")
                }
            } else {
                try service.unregister()
                helperStatus = .notRegistered
                Logger.shared.logLocalized("log_helper_unregistered")
                alertMessage = LanguageSettings.localizedString("helper_disabled")
            }
            showAlert = true
        } catch {
            Logger.shared.logLocalized("log_helper_toggle_error %@", error.localizedDescription)
            alertMessage = LanguageSettings.localizedString("error_prefix %@", error.localizedDescription)
            showAlert = true
            launchAtLogin = !enabled
            helperStatus = service.status
        }
    }

    private func handleLanguageAssistChange(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return }

        guard let detected = languageSettings.detectLanguage(for: trimmed) else { return }
        guard detected != selectedLanguage else { return }
        guard detected != lastSuggestedLanguage else { return }

        lastSuggestedLanguage = detected
        suggestedLanguage = detected
        showLanguageSuggestion = true
    }

    private func debounceLanguageAssistChange(_ text: String) {
        languageAssistCancellable?.cancel()
        languageAssistCancellable = Just(text)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { value in
                handleLanguageAssistChange(value)
            }
    }

    /// Zapisuje wprowadzone zmiany do AppStorage i helpera
    private func saveChanges() {
        // Zapisz do AppStorage
        storedDomainName = domainName
        storedMaxPasswordAge = maxPasswordAge
        storedWarningThreshold = warningThreshold
        storedNotificationHour = notificationHourString
        storedMinimalLogging = minimalLogging

        // Zastosuj stan helpera
        toggleLaunchAtLogin(launchAtLogin)

        // Ustaw język na wybrany po zapisie
        languageSettings.selectedLanguage = selectedLanguage

        // Ponownie wczytaj, żeby zsynchronizować helperStatus i wyzerować "dirty"
        dismiss()
    }

    /// Odrzuca zmiany i przywraca stan zapisany
    private func cancelChanges() {
        dismiss()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(LanguageSettings())
}
