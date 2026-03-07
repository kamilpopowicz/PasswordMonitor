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
    static let quietHoursStart = "quiet_hours_start" // Format: "18:01"
    static let quietHoursEnd = "quiet_hours_end"     // Format: "05:59"
    static let minimalLogging = "minimal_logging"
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var languageSettings: LanguageSettings
    @EnvironmentObject var themeManager: ThemeManager

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
    @State private var quietHoursStartString = "18:01"
    @State private var quietHoursStartDate = Date()
    @State private var quietHoursEndString = "05:59"
    @State private var quietHoursEndDate = Date()

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var helperStatus: SMAppService.Status = .notFound
    @State private var showResetConfirm = false
    @State private var showDeleteConfirm = false

    private let helperBundleID = "popo.PasswordMonitorHelperApp"

    // ZAPISANE wartości (AppStorage)
    @AppStorage(SettingsKeys.domainName) private var storedDomainName = ""
    @AppStorage(SettingsKeys.maxPasswordAge) private var storedMaxPasswordAge = 30
    @AppStorage(SettingsKeys.warningThreshold) private var storedWarningThreshold = 7
    @AppStorage(SettingsKeys.notificationHour) private var storedNotificationHour = "09:00"
    @AppStorage(SettingsKeys.quietHoursStart) private var storedQuietHoursStart = "18:01"
    @AppStorage(SettingsKeys.quietHoursEnd) private var storedQuietHoursEnd = "05:59"
    @AppStorage(SettingsKeys.minimalLogging) private var storedMinimalLogging = true
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Form {
                    // MARK: Appearance
                    Section(header: Text("settings_section_appearance").font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        Picker("settings_theme_mode", selection: Binding(
                            get: { themeManager.mode },
                            set: { newValue in
                                guard newValue != themeManager.mode else { return }
                                themeManager.mode = newValue
                            }
                        )) {
                            Text("theme_mode_auto").tag(PMTheme.ThemeMode.auto)
                            Text("theme_mode_light").tag(PMTheme.ThemeMode.light)
                            Text("theme_mode_dark").tag(PMTheme.ThemeMode.dark)
                        }
                        .pickerStyle(.segmented)
                    }

                    // MARK: Startup
                    Section(header: Text("settings_section_startup").font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        Toggle("settings_launch_at_login", isOn: $launchAtLogin)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(LanguageSettings.localizedString("settings_helper_desc %@", notificationHourString))
                            Text("settings_background_helper_info")
                        }
                        .font(.caption)
                        .foregroundColor(PMTheme.textSecondary)
                        .italic()
                    }

                    // MARK: Powiadomienia
                    Section(header: Text("settings_section_notifications").font(.headline).foregroundColor(PMTheme.textSecondary)) {
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
                            .foregroundColor(PMTheme.textSecondary)
                            .italic()

                        HStack {
                            DatePicker(
                                "settings_quiet_hours_start",
                                selection: $quietHoursStartDate,
                                displayedComponents: .hourAndMinute
                            )
                            .onChange(of: quietHoursStartDate) { _, newValue in
                                quietHoursStartString = dateToTimeString(newValue) ?? "18:01"
                                Logger.shared.log("Quiet hours start changed to \(quietHoursStartString)")
                            }

                            DatePicker(
                                "settings_quiet_hours_end",
                                selection: $quietHoursEndDate,
                                displayedComponents: .hourAndMinute
                            )
                            .onChange(of: quietHoursEndDate) { _, newValue in
                                quietHoursEndString = dateToTimeString(newValue) ?? "05:59"
                                Logger.shared.log("Quiet hours end changed to \(quietHoursEndString)")
                            }
                        }

                        Text("settings_quiet_hours_footnote")
                            .font(.caption)
                            .foregroundColor(PMTheme.textSecondary)
                            .italic()

                        #if DEBUG
                        Button("settings_force_helper_refresh") {
                            forceHelperRefresh()
                        }
                        .buttonStyle(.bordered)
                        .tint(PMTheme.accent)
                        #endif

                        Button("menu_test_notification") {
                            let testDate = Date().addingTimeInterval(23 * 3600)
                            NotificationManager.shared.showTestNotification(expirationDate: testDate)
                        }
                        .buttonStyle(.bordered)
                        .tint(PMTheme.warning)
                    }

                    // MARK: Active Directory
                    Section(header: Text("settings_section_ad").font(.headline).foregroundColor(PMTheme.textSecondary)) {
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
                    Section(header: Text("language_settings_title").font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        Picker("language_picker_label", selection: $selectedLanguage) {
                            ForEach(LanguageSettings.AppLanguage.allCases) { language in
                                Text(language.displayName)
                                    .tag(language)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("language_change_footnote")
                            .font(.caption)
                            .foregroundColor(PMTheme.textSecondary)
                            .italic()
                    }
                    
                    // MARK: Language Assist (On-Device)
                    Section(header: Text("language_assist_title").font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $languageAssistText)
                                .font(.body)
                                .frame(minHeight: 80)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(PMTheme.fieldBackground)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(PMTheme.fieldStroke, lineWidth: 1)
                                        )
                                )
                                .onChange(of: languageAssistText) { _, newValue in
                                    debounceLanguageAssistChange(newValue)
                                }

                            if languageAssistText.isEmpty {
                                Text("language_assist_placeholder")
                                    .foregroundColor(PMTheme.textSecondary)
                                    .padding(8)
                                    .allowsHitTesting(false)
                            }
                        }

                        Text("language_assist_footnote")
                            .font(.caption)
                            .foregroundColor(PMTheme.textSecondary)
                            .italic()
                    }

                    // MARK: Prywatność / Logi
                    Section(header: Text("settings_section_privacy").font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        Toggle("settings_minimal_logging", isOn: $minimalLogging)

                        Text("settings_minimal_logging_footnote")
                            .font(.caption)
                            .foregroundColor(PMTheme.textSecondary)
                            .italic()
                    }

                    // MARK: Informacje
                    Section(header: Text("settings_section_info").font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        HStack {
                            Text("settings_version")
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                .foregroundColor(PMTheme.textSecondary)
                        }

                        HStack {
                            Text("settings_helper_status")
                            Spacer()
                            Circle()
                                .fill(helperStatusColor)
                                .frame(width: 10, height: 10)
                            Text(helperStatusDescriptionKey)
                                .foregroundColor(PMTheme.textSecondary)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
            .padding()

            Divider()

            HStack {
                HStack(spacing: 8) {
                    Button("settings_reset_defaults") {
                        showResetConfirm = true
                    }
                    .pmButton()
                    Button("settings_delete_app") {
                        showDeleteConfirm = true
                    }
                    .pmButton(role: .destructive)
                }
                Spacer()
                Button("common_cancel") {
                    cancelChanges()
                }
                .pmButton()
                Button("common_save") {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isDirty)
                .pmButton(role: .primary)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 0)

            .alert("settings_reset_confirm_title", isPresented: $showResetConfirm) {
                Button("settings_reset_confirm_action", role: .destructive) {
                    resetDefaults()
                }
                Button("common_cancel", role: .cancel) {}
            } message: {
                Text("settings_reset_confirm_message")
            }
            .alert("settings_delete_confirm_title", isPresented: $showDeleteConfirm) {
                Button("settings_delete_confirm_yes", role: .destructive) {
                    deleteAppAndData()
                }
                Button("common_cancel", role: .cancel) {}
            } message: {
                Text("settings_delete_confirm_message")
            }

            VStack(spacing: 2) {
                Text("Copyright (c) 2026 Kamil Popowicz. All rights reserved.")
            }
            .font(.caption2)
            .foregroundColor(PMTheme.textSecondary)
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        // Window panel and min size are applied at the Window level.
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
            || quietHoursStartString != storedQuietHoursStart
            || quietHoursEndString != storedQuietHoursEnd
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
        case .enabled: return PMTheme.success
        case .requiresApproval: return PMTheme.warning
        case .notRegistered, .notFound: return PMTheme.danger
        @unknown default: return PMTheme.textMuted
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
        quietHoursStartString = storedQuietHoursStart
        quietHoursStartDate = timeStringToDate(quietHoursStartString) ?? Date()
        quietHoursEndString = storedQuietHoursEnd
        quietHoursEndDate = timeStringToDate(quietHoursEndString) ?? Date()
        selectedLanguage = languageSettings.selectedLanguage
        minimalLogging = storedMinimalLogging

        // Helper service status
        let service = SMAppService.loginItem(identifier: helperBundleID)
        helperStatus = service.status
        launchAtLogin = (service.status == .enabled)

        Logger.shared.logLocalized("log_settings_loaded_notification_time %@", notificationHourString)
    }

    private func toggleLaunchAtLogin(_ enabled: Bool, showUserAlert: Bool = true) {
        let service = SMAppService.loginItem(identifier: helperBundleID)
        do {
            if enabled {
                try service.register()
                Logger.shared.logLocalized("log_helper_registered")
                helperStatus = service.status
                if showUserAlert {
                    if helperStatus == .requiresApproval {
                        alertMessage = LanguageSettings.localizedString("helper_requires_approval")
                    } else {
                        alertMessage = LanguageSettings.localizedString("helper_enabled")
                    }
                }
            } else {
                try service.unregister()
                helperStatus = .notRegistered
                Logger.shared.logLocalized("log_helper_unregistered")
                if showUserAlert {
                    alertMessage = LanguageSettings.localizedString("helper_disabled")
                }
            }
            if showUserAlert {
                showAlert = true
            }
        } catch {
            Logger.shared.logLocalized("log_helper_toggle_error %@", error.localizedDescription)
            if showUserAlert {
                alertMessage = LanguageSettings.localizedString("error_prefix %@", error.localizedDescription)
                showAlert = true
            }
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

    private func forceHelperRefresh() {
        DistributedNotificationCenter.default().post(
            name: HelperMessaging.forceRefreshNotification,
            object: nil,
            userInfo: nil
        )
        Logger.shared.log("Manual helper refresh requested from Settings")
        alertMessage = LanguageSettings.localizedString("settings_force_helper_refresh_sent")
        showAlert = true
    }

    /// Zapisuje wprowadzone zmiany do AppStorage i helpera
    private func saveChanges() {
        let domainChanged = (domainName != storedDomainName)

        // Zapisz do AppStorage
        storedDomainName = domainName
        storedMaxPasswordAge = maxPasswordAge
        storedWarningThreshold = warningThreshold
        storedNotificationHour = notificationHourString
        storedQuietHoursStart = quietHoursStartString
        storedQuietHoursEnd = quietHoursEndString
        storedMinimalLogging = minimalLogging

        // Zastosuj stan helpera tylko jeśli zmieniony
        let savedLaunchAtLogin = (helperStatus == .enabled)
        if launchAtLogin != savedLaunchAtLogin {
            toggleLaunchAtLogin(launchAtLogin, showUserAlert: false)
        }

        // Ustaw język na wybrany po zapisie
        languageSettings.selectedLanguage = selectedLanguage

        if domainChanged {
            NotificationManager.shared.refreshPasswordStatus(
                reason: .automatic,
                onResult: { _ in
                    NotificationManager.shared.resetDailyNotificationState()
                },
                onError: { error in
                    Logger.shared.logLocalized("log_settings_domain_check_error %@", String(describing: error))
                }
            )
        }

        // Pozostajemy w oknie – stan "dirty" wynika z aktualnych wartości
    }

    /// Odrzuca zmiany i przywraca stan zapisany
    private func cancelChanges() {
        dismiss()
    }

    private func resetDefaults() {
        disableLaunchAtLoginIfNeeded()

        let bundleID = Bundle.main.bundleIdentifier ?? "popo.PasswordMonitor"
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()

        storedDomainName = ""
        storedMaxPasswordAge = 30
        storedWarningThreshold = 7
        storedNotificationHour = "09:00"
        storedQuietHoursStart = "18:01"
        storedQuietHoursEnd = "05:59"
        storedMinimalLogging = true

        let systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        languageSettings.selectedLanguage = LanguageSettings.AppLanguage(rawValue: systemLanguage) ?? .english

        loadSettings()
    }

    private func deleteAppAndData() {
        disableLaunchAtLoginIfNeeded()
        resetDefaults()

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let paths: [URL] = [
            home.appendingPathComponent(".password_monitor.log"),
            home.appendingPathComponent("Library/Logs/popo.PasswordMonitor"),
            home.appendingPathComponent("Library/Logs/PasswordMonitor"),
            home.appendingPathComponent("Library/Caches/popo.PasswordMonitor"),
            home.appendingPathComponent("Library/Caches/PasswordMonitor"),
            home.appendingPathComponent("Library/Application Support/PasswordMonitor"),
            home.appendingPathComponent("Library/Saved Application State/popo.PasswordMonitor.savedState"),
            home.appendingPathComponent("Library/Preferences/popo.PasswordMonitor.plist"),
            home.appendingPathComponent("Library/Containers/popo.PasswordMonitor"),
            home.appendingPathComponent("Library/LaunchAgents/popo.PasswordMonitorHelperApp.plist"),
            URL(fileURLWithPath: "/Applications/PasswordMonitor.app"),
            home.appendingPathComponent("Desktop/PasswordMonitor/PasswordMonitor.app")
        ]

        for url in paths {
            try? fm.removeItem(at: url)
        }

        NSApplication.shared.terminate(nil)
    }

    private func disableLaunchAtLoginIfNeeded() {
        let service = SMAppService.loginItem(identifier: helperBundleID)
        try? service.unregister()
        helperStatus = service.status
        launchAtLogin = false
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(LanguageSettings())
}
