//
//  SettingsView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import SwiftUI
import AppKit
import ServiceManagement
import PasswordMonitorCore
#if canImport(FoundationModels)
import FoundationModels
#endif

private enum SettingsKeys {
    static let maxPasswordAge = "max_password_age"
    static let warningThreshold = "warning_threshold"
    static let notificationHour = "notification_hour" // Format: "09:00"
    static let quietHoursStart = "quiet_hours_start" // Format: "18:01"
    static let quietHoursEnd = "quiet_hours_end"     // Format: "05:59"
    static let minimalLogging = "minimal_logging"
}

private enum LanguageAssistStatusKind {
    case info
    case success
    case error
}

struct SettingsView: View {
    private struct TranslationBatchResult {
        let translations: [String: String]
        let problematicKeys: [String]
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var languageSettings: LanguageSettings
    @EnvironmentObject var themeManager: ThemeManager

    // EDYTOWANE wartości (UI)
    @State private var launchAtLogin = false
    @State private var systemDomain: String?
    @State private var maxPasswordAge = 30
    @State private var warningThreshold = 7
    @State private var selectedLanguageCode = "en"
    @State private var minimalLogging = true
    @State private var languageAssistText = ""
    @State private var aiDetectInProgress = false
    @State private var aiRetryInProgress = false
    @State private var aiDetectStatus: String?
    @State private var aiDetectStatusKind: LanguageAssistStatusKind = .info
    @State private var pendingTranslationRetryCount = 0
    @State private var showTranslationPrompt = false
    @State private var detectedLanguageCode: String?
    @State private var translationPromptTitle = ""
    @State private var translationPromptMessage = ""
    @State private var translationPromptConfirm = ""
    @State private var translationPromptCancel = ""

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
    @AppStorage(SettingsKeys.maxPasswordAge) private var storedMaxPasswordAge = 30
    @AppStorage(SettingsKeys.warningThreshold) private var storedWarningThreshold = 7
    @AppStorage(SettingsKeys.notificationHour) private var storedNotificationHour = "09:00"
    @AppStorage(SettingsKeys.quietHoursStart) private var storedQuietHoursStart = "18:01"
    @AppStorage(SettingsKeys.quietHoursEnd) private var storedQuietHoursEnd = "05:59"
    @AppStorage(SettingsKeys.minimalLogging) private var storedMinimalLogging = true
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
            ScrollView {
                Form {
                    // MARK: Appearance
                    Section(header: Text(LanguageSettings.localizedString("settings_section_appearance")).font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        Picker(selection: Binding(
                            get: { themeManager.mode },
                            set: { newValue in
                                guard newValue != themeManager.mode else { return }
                                themeManager.mode = newValue
                            }
                        )) {
                            Text(LanguageSettings.localizedString("theme_mode_auto")).tag(PMTheme.ThemeMode.auto)
                            Text(LanguageSettings.localizedString("theme_mode_light")).tag(PMTheme.ThemeMode.light)
                            Text(LanguageSettings.localizedString("theme_mode_dark")).tag(PMTheme.ThemeMode.dark)
                        } label: {
                            Text(LanguageSettings.localizedString("settings_theme_mode"))
                        }
                        .pickerStyle(.segmented)
                    }

                    // MARK: Startup
                    Section(header: Text(LanguageSettings.localizedString("settings_section_startup")).font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        Toggle(isOn: $launchAtLogin) {
                            Text(LanguageSettings.localizedString("settings_launch_at_login"))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(LanguageSettings.localizedString("settings_helper_desc %@", notificationHourString))
                            Text(LanguageSettings.localizedString("settings_background_helper_info"))
                        }
                        .font(.caption)
                        .foregroundColor(PMTheme.textSecondary)
                        .italic()
                    }

                    // MARK: Powiadomienia
                    Section(header: Text(LanguageSettings.localizedString("settings_section_notifications")).font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        DatePicker(selection: $notificationDate, displayedComponents: .hourAndMinute) {
                            Text(LanguageSettings.localizedString("settings_notification_time"))
                        }
                        .onChange(of: notificationDate) { _, newValue in
                            // Konwersja Date -> String "HH:mm" dla EDYTOWANEJ wartości
                            notificationHourString = dateToTimeString(newValue) ?? "09:00"
                        }

                        Text(LanguageSettings.localizedString("settings_notification_footnote"))
                            .font(.caption)
                            .foregroundColor(PMTheme.textSecondary)
                            .italic()

                        HStack {
                            DatePicker(selection: $quietHoursStartDate, displayedComponents: .hourAndMinute) {
                                Text(LanguageSettings.localizedString("settings_quiet_hours_start"))
                            }
                            .onChange(of: quietHoursStartDate) { _, newValue in
                                quietHoursStartString = dateToTimeString(newValue) ?? "18:01"
                            }

                            DatePicker(selection: $quietHoursEndDate, displayedComponents: .hourAndMinute) {
                                Text(LanguageSettings.localizedString("settings_quiet_hours_end"))
                            }
                            .onChange(of: quietHoursEndDate) { _, newValue in
                                quietHoursEndString = dateToTimeString(newValue) ?? "05:59"
                            }
                        }

                        Text(LanguageSettings.localizedString("settings_quiet_hours_footnote"))
                            .font(.caption)
                            .foregroundColor(PMTheme.textSecondary)
                            .italic()

                        HStack(spacing: 8) {
                            #if DEBUG
                            Button(LanguageSettings.localizedString("settings_force_helper_refresh")) {
                                forceHelperRefresh()
                            }
                            .buttonStyle(.bordered)
                            .tint(PMTheme.accent)
                            #endif

                            Button(LanguageSettings.localizedString("menu_test_notification")) {
                                let testDate = Date().addingTimeInterval(23 * 3600)
                                NotificationManager.shared.showTestNotification(expirationDate: testDate)
                            }
                            .buttonStyle(.bordered)
                            .tint(PMTheme.warning)

                            Spacer()
                        }
                    }

                    // MARK: Active Directory
                    Section(header: Text(LanguageSettings.localizedString("settings_section_ad")).font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LanguageSettings.localizedString("settings_domain_name"))
                                .font(.caption)
                                .foregroundColor(PMTheme.textSecondary)
                            if let domain = systemDomain, !domain.isEmpty {
                                Text(domain)
                                    .font(.body)
                                    .foregroundColor(PMTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(LanguageSettings.localizedString("settings_domain_not_configured"))
                                    .font(.body)
                                    .foregroundColor(PMTheme.textSecondary)
                            }
                            Text(LanguageSettings.localizedString("settings_domain_source_info"))
                                .font(.caption)
                                .foregroundColor(PMTheme.textSecondary)
                                .italic()
                        }
                        .padding(.vertical, 2)

                        HStack {
                            Text(LanguageSettings.localizedString("settings_max_password_age"))
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
                            Text(LanguageSettings.localizedString("settings_warning_threshold"))
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
                    Section(header: Text(LanguageSettings.localizedString("language_settings_title")).font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        Picker(selection: $selectedLanguageCode) {
                            ForEach(languageSettings.availableLanguageOptions()) { option in
                                Text(option.displayName)
                                    .tag(option.code)
                            }
                        } label: {
                            Text(LanguageSettings.localizedString("language_picker_label"))
                        }
                        .pickerStyle(.segmented)

                        Text(LanguageSettings.localizedString("language_change_footnote"))
                            .font(.caption)
                            .foregroundColor(PMTheme.textSecondary)
                            .italic()
                    }
                    
                    // MARK: Language Assist (On-Device)
                    Section(header: Text(LanguageSettings.localizedString("language_assist_title")).font(.headline).foregroundColor(PMTheme.textSecondary)) {
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

                            if languageAssistText.isEmpty {
                                Text(LanguageSettings.localizedString("language_assist_placeholder"))
                                    .foregroundColor(PMTheme.textSecondary)
                                    .padding(8)
                                    .allowsHitTesting(false)
                            }
                        }

                        HStack(spacing: 8) {
                            Button(LanguageSettings.localizedString("language_assist_detect")) {
                                handleDetectLanguageTap()
                            }
                            .pmButton(role: .primary)
                            .disabled(aiDetectInProgress)

                            Button(LanguageSettings.localizedString("language_assist_permissions")) {
                                openWindow(id: "ai-check-window")
                            }
                            .pmButton()

                            Button(retryProblematicButtonTitle) {
                                handleRetryProblematicTap()
                            }
                            .pmButton()
                            .disabled(aiDetectInProgress || aiRetryInProgress || pendingTranslationRetryCount == 0)

                            Spacer()
                        }

                        if let aiDetectStatus {
                            Text(aiDetectStatus)
                                .font(.caption)
                                .foregroundColor(aiDetectStatusColor)
                        }

                        Text(LanguageSettings.localizedString("language_assist_ai_requirements"))
                            .font(.caption)
                            .foregroundColor(PMTheme.danger)
                            .italic()

                        Text(LanguageSettings.localizedString("language_assist_footnote"))
                            .font(.caption)
                            .foregroundColor(PMTheme.textSecondary)
                            .italic()
                    }

                    // MARK: Prywatność / Logi
                    Section(header: Text(LanguageSettings.localizedString("settings_section_privacy")).font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        Toggle(isOn: $minimalLogging) {
                            Text(LanguageSettings.localizedString("settings_minimal_logging"))
                        }

                        Text(LanguageSettings.localizedString("settings_minimal_logging_footnote"))
                            .font(.caption)
                            .foregroundColor(PMTheme.textSecondary)
                            .italic()
                    }

                    // MARK: Informacje
                    Section(header: Text(LanguageSettings.localizedString("settings_section_info")).font(.headline).foregroundColor(PMTheme.textSecondary)) {
                        HStack {
                            Text(LanguageSettings.localizedString("settings_version"))
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                .foregroundColor(PMTheme.textSecondary)
                        }

                        HStack {
                            Text(LanguageSettings.localizedString("settings_helper_status"))
                            Spacer()
                            Circle()
                                .fill(helperStatusColor)
                                .frame(width: 10, height: 10)
                            Text(LanguageSettings.localizedString(helperStatusDescriptionKey))
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
                    Button(LanguageSettings.localizedString("settings_reset_defaults")) {
                        showResetConfirm = true
                    }
                    .pmButton()
                    Button(LanguageSettings.localizedString("settings_delete_app")) {
                        showDeleteConfirm = true
                    }
                    .pmButton(role: .destructive)
                }
                Spacer()
                Button(LanguageSettings.localizedString("common_cancel")) {
                    cancelChanges()
                }
                .pmButton()
                Button(LanguageSettings.localizedString("common_save")) {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isDirty)
                .pmButton(role: .primary)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 0)

            .alert(LanguageSettings.localizedString("settings_reset_confirm_title"), isPresented: $showResetConfirm) {
                Button(LanguageSettings.localizedString("settings_reset_confirm_action"), role: .destructive) {
                    resetDefaults()
                }
                Button(LanguageSettings.localizedString("common_cancel"), role: .cancel) {}
            } message: {
                Text(LanguageSettings.localizedString("settings_reset_confirm_message"))
            }
            .alert(LanguageSettings.localizedString("settings_delete_confirm_title"), isPresented: $showDeleteConfirm) {
                Button(LanguageSettings.localizedString("settings_delete_confirm_yes"), role: .destructive) {
                    deleteAppAndData()
                }
                Button(LanguageSettings.localizedString("common_cancel"), role: .cancel) {}
            } message: {
                Text(LanguageSettings.localizedString("settings_delete_confirm_message"))
            }

            PMWindowFooter()
            }
            .blur(radius: aiDetectInProgress ? 6 : 0)
            .allowsHitTesting(!aiDetectInProgress)

            if aiDetectInProgress {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
                    .tint(PMTheme.textPrimary)
            }
        }
        // Window panel and min size are applied at the Window level.
        .onAppear {
            loadSettings()
            appState.windowOpened()
            DispatchQueue.main.async {
                appState.activateApp()
                refreshWindowTitle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            refreshWindowTitle()
            refreshPendingRetryCount()
        }
        .onChange(of: selectedLanguageCode) { _, _ in
            refreshPendingRetryCount()
        }
        .onDisappear {
            appState.windowClosed()
        }
        .alert(LanguageSettings.localizedString("helper_alert_title"), isPresented: $showAlert) {
            Button(LanguageSettings.localizedString("common_ok")) {}
        } message: {
            Text(alertMessage)
        }
        .alert(translationPromptTitle, isPresented: $showTranslationPrompt) {
            Button(translationPromptConfirm) {
                Task { await translateAndApplyDetectedLanguage() }
            }
            Button(translationPromptCancel, role: .cancel) {}
        } message: {
            Text(translationPromptMessage)
        }
    }

    /// Czy wartości edytowane różnią się od zapisanych
    private var isDirty: Bool {
        let savedLaunchAtLogin = (helperStatus == .enabled)
        return maxPasswordAge != storedMaxPasswordAge
            || warningThreshold != storedWarningThreshold
            || notificationHourString != storedNotificationHour
            || quietHoursStartString != storedQuietHoursStart
            || quietHoursEndString != storedQuietHoursEnd
            || launchAtLogin != savedLaunchAtLogin
            || selectedLanguageCode != languageSettings.selectedLanguageCode
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

    private func refreshWindowTitle() {
        let title = LanguageSettings.localizedString("settings_window_title")
        if let keyWindow = NSApp.keyWindow {
            keyWindow.title = title
            return
        }
        if let settingsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings-window" }) {
            settingsWindow.title = title
        }
    }

    private var helperStatusColor: Color {
        switch helperStatus {
        case .enabled: return PMTheme.success
        case .requiresApproval: return PMTheme.warning
        case .notRegistered, .notFound: return PMTheme.danger
        @unknown default: return PMTheme.textMuted
        }
    }

    private var helperStatusDescriptionKey: String {
        switch helperStatus {
        case .enabled: return "status_active"
        case .notRegistered: return "status_not_registered"
        case .requiresApproval: return "status_requires_approval"
        case .notFound: return "status_not_found"
        @unknown default: return "status_unknown"
        }
    }

    private var aiDetectStatusColor: Color {
        switch aiDetectStatusKind {
        case .info: return PMTheme.textSecondary
        case .success: return PMTheme.success
        case .error: return PMTheme.danger
        }
    }

    private var retryProblematicButtonTitle: String {
        LanguageSettings.localizedString(
            "language_assist_retry_problematic_count %d",
            pendingTranslationRetryCount
        )
    }

    private func loadSettings() {
        // AppStorage -> edytowane wartości
        systemDomain = SystemADDomainResolver.currentDomain()
        maxPasswordAge = storedMaxPasswordAge
        warningThreshold = storedWarningThreshold
        notificationHourString = storedNotificationHour
        notificationDate = timeStringToDate(notificationHourString) ?? Date()
        quietHoursStartString = storedQuietHoursStart
        quietHoursStartDate = timeStringToDate(quietHoursStartString) ?? Date()
        quietHoursEndString = storedQuietHoursEnd
        quietHoursEndDate = timeStringToDate(quietHoursEndString) ?? Date()
        selectedLanguageCode = languageSettings.selectedLanguageCode
        minimalLogging = storedMinimalLogging
        refreshPendingRetryCount()

        // Helper service status
        let service = SMAppService.loginItem(identifier: helperBundleID)
        helperStatus = service.status
        launchAtLogin = (service.status == .enabled)
    }

    private func refreshPendingRetryCount() {
        pendingTranslationRetryCount = LocalizationRetryManager.shared.pendingCount(for: selectedLanguageCode)
    }

    private func handleRetryProblematicTap() {
        Task {
            aiRetryInProgress = true
            defer { aiRetryInProgress = false }

            let result = await LocalizationRetryManager.shared.retryNow(for: selectedLanguageCode)
            refreshPendingRetryCount()

            if result.attempted == 0 {
                setDetectStatus(
                    LanguageSettings.localizedString("language_assist_retry_no_pending"),
                    kind: .info
                )
                return
            }
            if result.fixed > 0 {
                setDetectStatus(
                    LanguageSettings.localizedString(
                        "language_assist_retry_result_fixed %d %d %d",
                        result.attempted,
                        result.fixed,
                        result.remaining
                    ),
                    kind: .success
                )
                return
            }
            setDetectStatus(
                LanguageSettings.localizedString(
                    "language_assist_retry_result_no_change %d %d",
                    result.attempted,
                    result.remaining
                ),
                kind: .info
            )
        }
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

    private func handleDetectLanguageTap() {
        Task { await detectLanguageAndPrompt() }
    }

    @MainActor
    private func detectLanguageAndPrompt() async {
        let trimmed = languageAssistText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else {
            setDetectStatus(LanguageSettings.localizedString("language_assist_ai_no_text"), kind: .error)
            return
        }

        aiDetectInProgress = true
        defer { aiDetectInProgress = false }
        aiDetectStatus = nil

        Logger.shared.log("Language detection started (chars=\(trimmed.count))")

        guard let code = languageSettings.detectLanguageCode(for: trimmed) else {
            setDetectStatus(LanguageSettings.localizedString("language_assist_ai_failed"), kind: .error)
            Logger.shared.log("Language detection failed: no dominant language")
            return
        }

        if code.lowercased() == selectedLanguageCode.lowercased() {
            setDetectStatus(LanguageSettings.localizedString("language_assist_ai_same"), kind: .info)
            return
        }

        let aiAvailable = await isAppleIntelligenceAvailable()
        guard aiAvailable else {
            setDetectStatus(LanguageSettings.localizedString("language_assist_ai_unavailable"), kind: .error)
            openWindow(id: "ai-check-window")
            Logger.shared.log("Language detection blocked: Apple Intelligence unavailable")
            return
        }

        detectedLanguageCode = code
        await prepareTranslationPrompt(for: code)
        showTranslationPrompt = true
    }

    private func setDetectStatus(_ message: String?, kind: LanguageAssistStatusKind) {
        aiDetectStatus = message
        aiDetectStatusKind = kind
    }

    @MainActor
    private func prepareTranslationPrompt(for languageCode: String) async {
        let languageName = languageSettings.displayName(for: languageCode)
        let baseTitle = LanguageSettings.localizedString("language_assist_detect_title")
        let baseMessage = LanguageSettings.localizedString("language_assist_detect_message %@", languageName)
        let baseConfirm = LanguageSettings.localizedString("language_assist_detect_confirm")
        let baseCancel = LanguageSettings.localizedString("language_assist_detect_cancel")

        translationPromptTitle = baseTitle
        translationPromptMessage = baseMessage
        translationPromptConfirm = baseConfirm
        translationPromptCancel = baseCancel

        guard await isAppleIntelligenceAvailable() else { return }
        guard let translated = try? await translateStrings(
            [
                "title": baseTitle,
                "message": baseMessage,
                "confirm": baseConfirm,
                "cancel": baseCancel
            ],
            to: languageCode
        ) else { return }

        translationPromptTitle = sanitizedPromptText(
            source: baseTitle,
            translated: translated.translations["title"],
            fallback: baseTitle,
            key: "language_assist_detect_title"
        )
        translationPromptMessage = sanitizedPromptText(
            source: baseMessage,
            translated: translated.translations["message"],
            fallback: baseMessage,
            key: "language_assist_detect_message"
        )
        translationPromptConfirm = sanitizedPromptText(
            source: baseConfirm,
            translated: translated.translations["confirm"],
            fallback: baseConfirm,
            key: "language_assist_detect_confirm"
        )
        translationPromptCancel = sanitizedPromptText(
            source: baseCancel,
            translated: translated.translations["cancel"],
            fallback: baseCancel,
            key: "language_assist_detect_cancel"
        )
    }

    private func sanitizedPromptText(source: String, translated: String?, fallback: String, key: String) -> String {
        guard let translated else { return fallback }
        if shouldRetryTranslation(source: source, translated: translated) {
            Logger.shared.log("Prompt translation rejected (quality) for key \(key); using fallback")
            return fallback
        }
        if !hasCompatiblePlaceholders(source: source, translated: translated) {
            Logger.shared.log("Prompt translation rejected (placeholder mismatch) for key \(key); using fallback")
            return fallback
        }
        return translated
    }

    @MainActor
    private func translateAndApplyDetectedLanguage() async {
        guard let languageCode = detectedLanguageCode else { return }

        aiDetectInProgress = true
        defer { aiDetectInProgress = false }
        aiDetectStatus = nil

        Logger.shared.log("Translation started for language: \(languageCode)")

        guard await isAppleIntelligenceAvailable() else {
            setDetectStatus(LanguageSettings.localizedString("language_assist_ai_unavailable"), kind: .error)
            openWindow(id: "ai-check-window")
            Logger.shared.log("Translation blocked: Apple Intelligence unavailable")
            return
        }

        guard let baseStrings = loadBaseLocalizations() else {
            setDetectStatus(LanguageSettings.localizedString("language_assist_translation_failed"), kind: .error)
            Logger.shared.log("Translation failed: base localizations not found")
            return
        }

        do {
            let translated = try await translateStrings(baseStrings, to: languageCode)
            LanguageSettings.saveCustomTranslations(translated.translations, for: languageCode)
            LocalizationRetryManager.shared.recordProblematicKeys(translated.problematicKeys, for: languageCode)
            LocalizationRetryManager.shared.scheduleOneHourRetry(for: languageCode)
            languageSettings.selectedLanguageCode = languageCode
            selectedLanguageCode = languageCode
            refreshPendingRetryCount()
            setDetectStatus(LanguageSettings.localizedString("language_assist_translation_done"), kind: .success)
            Logger.shared.log("Translation completed for language: \(languageCode)")
        } catch {
            setDetectStatus(LanguageSettings.localizedString("language_assist_translation_failed"), kind: .error)
            Logger.shared.log("Translation failed: \(error.localizedDescription)")
        }
    }

    private func loadBaseLocalizations() -> [String: String]? {
        var result: [String: String] = [:]

        if let stringsURL = Bundle.main.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: "en"
        ),
           let dict = NSDictionary(contentsOf: stringsURL) as? [String: String] {
            result.merge(dict) { _, new in new }
        }

        if let stringsDictURL = Bundle.main.url(
            forResource: "Localizable",
            withExtension: "stringsdict",
            subdirectory: nil,
            localization: "en"
        ),
           let data = try? Data(contentsOf: stringsDictURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let root = plist as? [String: Any] {
            for (key, value) in root {
                guard let entry = value as? [String: Any],
                      let valueNode = entry["value"] as? [String: Any] else { continue }
                if let other = valueNode["other"] as? String {
                    result[key] = other
                } else if let one = valueNode["one"] as? String {
                    result[key] = one
                }
            }
        }

        guard !result.isEmpty else { return nil }
        Logger.shared.log("Loaded base localizations for translation: \(result.count) keys")
        return result
    }

    private func isAppleIntelligenceAvailable() async -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession()
                _ = try await session.respond(to: "Reply only with OK")
                return true
            } catch {
                return false
            }
        }
        #endif
        return false
    }

    private func translateStrings(_ strings: [String: String], to languageCode: String) async throws -> TranslationBatchResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            var result: [String: String] = [:]
            var problematicKeys: [String] = []
            for (key, value) in strings {
                var accepted: String?
                var lastError: Error?

                for attempt in 1...3 {
                    do {
                        let translated = try await translateText(
                            value,
                            to: languageCode,
                            key: key,
                            strict: attempt > 1
                        )

                        if shouldRetryTranslation(source: value, translated: translated) {
                            Logger.shared.log("Translation rejected (quality) for key \(key), attempt \(attempt)")
                            continue
                        }

                        if !hasCompatiblePlaceholders(source: value, translated: translated) {
                            Logger.shared.log("Translation rejected (placeholder mismatch) for key \(key), attempt \(attempt)")
                            continue
                        }

                        accepted = translated
                        break
                    } catch {
                        lastError = error
                        let message = error.localizedDescription
                        if message.localizedCaseInsensitiveContains("unsafe") {
                            Logger.shared.log("Translation unsafe refusal for key \(key), attempt \(attempt)")
                            continue
                        }
                        Logger.shared.log("Translation attempt \(attempt) failed for key \(key): \(message)")
                    }
                }

                if let accepted {
                    result[key] = accepted
                    continue
                }

                if let lastError {
                    let message = lastError.localizedDescription
                    if !message.localizedCaseInsensitiveContains("unsafe") {
                        Logger.shared.log("Translation failed for key \(key) after 3 attempts; keeping original text")
                    }
                } else {
                    Logger.shared.log("Translation rejected for key \(key) after 3 attempts; keeping original text")
                }
                result[key] = value
                problematicKeys.append(key)
            }
            return TranslationBatchResult(
                translations: result,
                problematicKeys: problematicKeys
            )
        }
        #endif
        throw NSError(domain: "Localization", code: 2, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence unavailable"])
    }

    private func hasCompatiblePlaceholders(source: String, translated: String) -> Bool {
        func tokens(_ text: String) -> [String] {
            let pattern = "%(?:#@[^@]+@|(?:\\d+\\$)?[-+ #0']*(?:\\d+|\\*)?(?:\\.(?:\\d+|\\*))?(?:hh|h|ll|l|L|z|j|t)?[@diuoxXfFeEgGaAcCsSp%])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            return regex.matches(in: text, range: range).compactMap { match in
                guard match.range.location != NSNotFound else { return nil }
                let token = ns.substring(with: match.range)
                return token == "%%" ? nil : token
            }
        }

        func family(_ token: String) -> String {
            if token.hasPrefix("%#@"), token.hasSuffix("@") {
                return "plural"
            }
            guard let conversion = token.last else { return token }
            switch conversion {
            case "@":
                return "object"
            case "d", "i", "u", "o", "x", "X":
                return "int"
            case "f", "F", "e", "E", "g", "G", "a", "A":
                return "float"
            case "c", "C":
                return "char"
            case "s", "S":
                return "cstring"
            case "p":
                return "pointer"
            default:
                return token
            }
        }

        let sourceTokens = tokens(source)
        let translatedTokens = tokens(translated)
        guard sourceTokens.count == translatedTokens.count else { return false }

        for (lhs, rhs) in zip(sourceTokens, translatedTokens) {
            let left = family(lhs)
            let right = family(rhs)
            if left == right { continue }
            if (left == "plural" && right == "int") || (left == "int" && right == "plural") {
                continue
            }
            return false
        }
        return true
    }

    private func extractJson(from text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else { return nil }
        return String(cleaned[start...end])
    }

    private func extractResponseText(from response: Any) -> String {
        if let string = extractPreferredString(from: response, depth: 0) {
            return string
        }
        return String(describing: response)
    }

    private func extractPreferredString(from value: Any, depth: Int) -> String? {
        if depth > 6 { return nil }
        if let string = value as? String {
            return string
        }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional, let child = mirror.children.first {
            return extractPreferredString(from: child.value, depth: depth + 1)
        }

        let preferredLabels: Set<String> = ["content", "message", "text", "value", "output", "response"]
        for child in mirror.children {
            if let label = child.label, preferredLabels.contains(label) {
                if let string = extractPreferredString(from: child.value, depth: depth + 1) {
                    return string
                }
            }
        }

        for child in mirror.children {
            if let string = extractPreferredString(from: child.value, depth: depth + 1) {
                return string
            }
        }

        return nil
    }

    private func decodeTranslatedJSON(from response: String) -> [String: String]? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = Data(base64Encoded: trimmed),
           let jsonString = String(data: data, encoding: .utf8),
           let jsonData = jsonString.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] {
            return obj
        }

        if let json = extractJson(from: response) {
            let sanitized = json.replacingOccurrences(of: "\\_", with: "_")
            if let data = sanitized.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                return obj
            }
        }

        Logger.shared.log("Translation decode failed. Response prefix: \(trimmed.prefix(200))")
        return nil
    }

    private func sanitizeTranslatedText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.hasPrefix("\""), cleaned.hasSuffix("\""), cleaned.count >= 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        return cleaned
    }

    @available(macOS 26.0, *)
    private func translateText(_ text: String, to languageCode: String, key: String, strict: Bool) async throws -> String {
        do {
            let protected = protectPlaceholders(in: text)
            let session = LanguageModelSession()
            let strictClause = strict ? "You MUST translate to idiomatic \(languageCode). Never answer in English unless the text is a product name." : ""
            let prompt = """
            Translate this UI text to \(languageCode). \(strictClause)
            Keep placeholder markers like [[PH_0]] exactly unchanged.
            Preserve line breaks.
            Return ONLY the translated text, no quotes, no markdown.
            Text: \(protected.text)
            """
            let response = try await session.respond(to: prompt)
            let raw = extractResponseText(from: response)
            let sanitized = sanitizeTranslatedText(raw)
            return restorePlaceholders(in: sanitized, placeholders: protected.placeholders)
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("context window"),
               message.localizedCaseInsensitiveContains("exceeded") {
                let parts = splitText(text, maxLength: 120)
                var translatedParts: [String] = []
                translatedParts.reserveCapacity(parts.count)
                for part in parts {
                    let protected = protectPlaceholders(in: part)
                    let session = LanguageModelSession()
                    let strictClause = strict ? "You MUST translate to idiomatic \(languageCode). Never answer in English unless the text is a product name." : ""
                    let prompt = """
                    Translate this UI text to \(languageCode). \(strictClause)
                    Keep placeholder markers like [[PH_0]] exactly unchanged.
                    Preserve line breaks.
                    Return ONLY the translated text, no quotes, no markdown.
                    Text: \(protected.text)
                    """
                    let response = try await session.respond(to: prompt)
                    let raw = extractResponseText(from: response)
                    let sanitized = sanitizeTranslatedText(raw)
                    translatedParts.append(
                        restorePlaceholders(in: sanitized, placeholders: protected.placeholders)
                    )
                }
                return translatedParts.joined()
            }
            throw error
        }
    }

    private func protectPlaceholders(in text: String) -> (text: String, placeholders: [String]) {
        let pattern = "%(?:#@[^@]+@|(?:\\d+\\$)?[-+ #0']*(?:\\d+|\\*)?(?:\\.(?:\\d+|\\*))?(?:hh|h|ll|l|L|z|j|t)?[@diuoxXfFeEgGaAcCsSp%])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, [])
        }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (text, []) }

        var placeholders: [String] = []
        var chunks: [String] = []
        var cursor = 0

        for match in matches {
            guard match.range.location != NSNotFound else { continue }
            if match.range.location > cursor {
                chunks.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            let token = ns.substring(with: match.range)
            if token == "%%" {
                chunks.append(token)
            } else {
                let marker = "[[PH_\(placeholders.count)]]"
                placeholders.append(token)
                chunks.append(marker)
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            chunks.append(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)))
        }

        return (chunks.joined(), placeholders)
    }

    private func restorePlaceholders(in text: String, placeholders: [String]) -> String {
        var restored = text
        for (index, token) in placeholders.enumerated() {
            let pattern = #"(?i)[\[\{\(]{1,2}\s*PH\s*[_-]?\s*\#(index)\s*[\]\}\)]{1,2}"#
            restored = restored.replacingOccurrences(of: pattern, with: token, options: .regularExpression)
        }
        let unmatchedPattern = #"(?i)[\[\{\(]{1,2}\s*PH\s*[_-]?\s*\d+\s*[\]\}\)]{1,2}|\bPH\s*[_-]?\s*\d+\b"#
        restored = restored.replacingOccurrences(
            of: unmatchedPattern,
            with: "",
            options: .regularExpression
        )
        if placeholders.isEmpty {
            restored = restored.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return restored
    }

    private func shouldRetryTranslation(source: String, translated: String) -> Bool {
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let dst = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        if dst.isEmpty { return true }
        if dst.caseInsensitiveCompare(src) == .orderedSame { return true }
        let lower = dst.lowercased()
        if lower.contains("no translation available") { return true }
        if lower.contains("translation unavailable") { return true }
        if dst.range(of: #"(?i)[\[\{\(]{1,2}\s*PH\s*[_-]?\s*\d+\s*[\]\}\)]{1,2}|\bPH\s*[_-]?\s*\d+\b"#, options: .regularExpression) != nil {
            return true
        }
        if dst.lowercased().contains("ui text key") {
            return true
        }
        if dst.range(of: #"[a-z0-9]+(?:_[a-z0-9]+){2,}"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    private func splitText(_ text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }
        var parts: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if current.count >= maxLength {
                parts.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            parts.append(current)
        }
        return parts
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
        // Zbierz diff przed zapisem – logujemy tylko realne zmiany po Save
        var changes: [String] = []
        if storedMaxPasswordAge != maxPasswordAge {
            changes.append("max_password_age: \(storedMaxPasswordAge) → \(maxPasswordAge)")
        }
        if storedWarningThreshold != warningThreshold {
            changes.append("warning_threshold: \(storedWarningThreshold) → \(warningThreshold)")
        }
        if storedNotificationHour != notificationHourString {
            changes.append("notification_hour: \(storedNotificationHour) → \(notificationHourString)")
        }
        if storedQuietHoursStart != quietHoursStartString {
            changes.append("quiet_hours_start: \(storedQuietHoursStart) → \(quietHoursStartString)")
        }
        if storedQuietHoursEnd != quietHoursEndString {
            changes.append("quiet_hours_end: \(storedQuietHoursEnd) → \(quietHoursEndString)")
        }
        if storedMinimalLogging != minimalLogging {
            changes.append("minimal_logging: \(storedMinimalLogging) → \(minimalLogging)")
        }
        if languageSettings.selectedLanguageCode != selectedLanguageCode {
            changes.append("appLanguage: \(languageSettings.selectedLanguageCode) → \(selectedLanguageCode)")
        }
        let savedLaunchAtLogin = (helperStatus == .enabled)
        if launchAtLogin != savedLaunchAtLogin {
            changes.append("launch_at_login: \(savedLaunchAtLogin) → \(launchAtLogin)")
        }

        // Zapis do AppStorage (czyli UserDefaults.standard = plist main app „popo.PasswordMonitor").
        storedMaxPasswordAge = maxPasswordAge
        storedWarningThreshold = warningThreshold
        storedNotificationHour = notificationHourString
        storedQuietHoursStart = quietHoursStartString
        storedQuietHoursEnd = quietHoursEndString
        storedMinimalLogging = minimalLogging

        // Mirror do shared suite — helper czyta z "popo.PasswordMonitor" w syncSharedSettings.
        // Bez tego helper nigdy nie zobaczy zmian (jego UserDefaults.standard to osobny plist).
        if let sharedDefaults = UserDefaults(suiteName: "popo.PasswordMonitor") {
            sharedDefaults.set(maxPasswordAge, forKey: SettingsKeys.maxPasswordAge)
            sharedDefaults.set(warningThreshold, forKey: SettingsKeys.warningThreshold)
            sharedDefaults.set(notificationHourString, forKey: SettingsKeys.notificationHour)
            sharedDefaults.set(quietHoursStartString, forKey: SettingsKeys.quietHoursStart)
            sharedDefaults.set(quietHoursEndString, forKey: SettingsKeys.quietHoursEnd)
            sharedDefaults.set(minimalLogging, forKey: SettingsKeys.minimalLogging)
            sharedDefaults.set(selectedLanguageCode, forKey: "appLanguage")
        }

        // Zastosuj stan helpera tylko jeśli zmieniony
        if launchAtLogin != savedLaunchAtLogin {
            toggleLaunchAtLogin(launchAtLogin, showUserAlert: false)
        }

        // Ustaw język na wybrany po zapisie
        languageSettings.selectedLanguageCode = selectedLanguageCode

        if changes.isEmpty {
            Logger.shared.log("Settings saved with no changes")
        } else {
            Logger.shared.log("Settings saved: \(changes.joined(separator: "; "))")
            DistributedNotificationCenter.default().post(
                name: HelperMessaging.settingsDidChangeNotification,
                object: nil,
                userInfo: nil
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

        storedMaxPasswordAge = 30
        storedWarningThreshold = 7
        storedNotificationHour = "09:00"
        storedQuietHoursStart = "18:01"
        storedQuietHoursEnd = "05:59"
        storedMinimalLogging = true

        languageSettings.selectedLanguageCode = "en"

        // Lustrzane odświeżenie shared suite, żeby helper również wrócił do domyślnych wartości.
        if let sharedDefaults = UserDefaults(suiteName: "popo.PasswordMonitor") {
            sharedDefaults.set(30, forKey: SettingsKeys.maxPasswordAge)
            sharedDefaults.set(7, forKey: SettingsKeys.warningThreshold)
            sharedDefaults.set("09:00", forKey: SettingsKeys.notificationHour)
            sharedDefaults.set("18:01", forKey: SettingsKeys.quietHoursStart)
            sharedDefaults.set("05:59", forKey: SettingsKeys.quietHoursEnd)
            sharedDefaults.set(true, forKey: SettingsKeys.minimalLogging)
            sharedDefaults.set("en", forKey: "appLanguage")
        }
        Logger.shared.log("Settings reset to defaults")
        DistributedNotificationCenter.default().post(
            name: HelperMessaging.settingsDidChangeNotification,
            object: nil,
            userInfo: nil
        )

        loadSettings()
    }

    private func deleteAppAndData() {
        disableLaunchAtLoginIfNeeded()
        terminateRunningHelperProcesses()
        removeStoredDefaultsForUninstall()

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let paths = AppUninstallCleanupPlan.userDataPaths(
            homeDirectory: home,
            desktopAppURL: home.appendingPathComponent("Desktop/PasswordMonitor/PasswordMonitor.app")
        )

        for url in paths {
            do {
                try fm.removeItem(at: url)
                Logger.shared.log("Delete app removed \(url.path)")
            } catch {
                Logger.shared.log("Delete app skipped \(url.path): \(error.localizedDescription)")
            }
        }

        NSApplication.shared.terminate(nil)
    }

    private func terminateRunningHelperProcesses() {
        let helpers = NSRunningApplication.runningApplications(withBundleIdentifier: helperBundleID)
        for helper in helpers {
            Logger.shared.log("Delete app terminating helper process (pid=\(helper.processIdentifier), path=\(helper.bundleURL?.path ?? "unknown"))")
            if !helper.terminate() {
                helper.forceTerminate()
            }
        }
    }

    private func removeStoredDefaultsForUninstall() {
        for domain in AppUninstallCleanupPlan.preferenceDomains {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain)
        }

        UserDefaults.standard.synchronize()
        UserDefaults(suiteName: AppUninstallCleanupPlan.sharedSuiteName)?.synchronize()
        Logger.shared.log("Delete app removed stored defaults")
    }

    private func disableLaunchAtLoginIfNeeded() {
        let service = SMAppService.loginItem(identifier: helperBundleID)
        try? service.unregister()
        helperStatus = service.status
        launchAtLogin = false
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(LanguageSettings())
}
#endif
