//
//  AIRequirementsView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 20/03/2026.
//

import SwiftUI
import AppKit
import Combine
import PasswordMonitorCore

#if canImport(FoundationModels) && compiler(>=6.2)
import FoundationModels
#endif

struct AIRequirementsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AIRequirementsModel()

    var body: some View {
        VStack(spacing: PMLayout.noSpacing) {
            PMWindowContentContainer {
                VStack(alignment: .leading, spacing: PMLayout.sectionSpacing) {
                    RequirementRow(
                        titleKey: "ai_requirements_system_language",
                        value: model.systemLanguageDisplay,
                        status: model.systemStatus,
                        statusWidth: PMLayout.aiRequirementsStatusColumnWidth,
                        optionWidth: PMLayout.aiRequirementsOptionColumnWidth,
                        optionLeadingInset: PMLayout.aiRequirementsOptionLeadingInset,
                        valueWidth: PMLayout.aiRequirementsValueColumnWidth,
                        buttonKey: "ai_requirements_open_language",
                        buttonWidth: PMLayout.aiRequirementsButtonColumnWidth,
                        action: { model.openLanguageSettings() }
                    )
                    RequirementRow(
                        titleKey: "ai_requirements_siri_language",
                        value: model.siriLanguageDisplay,
                        status: model.siriStatus,
                        statusWidth: PMLayout.aiRequirementsStatusColumnWidth,
                        optionWidth: PMLayout.aiRequirementsOptionColumnWidth,
                        optionLeadingInset: PMLayout.aiRequirementsOptionLeadingInset,
                        valueWidth: PMLayout.aiRequirementsValueColumnWidth,
                        buttonKey: "ai_requirements_open_siri",
                        buttonWidth: PMLayout.aiRequirementsButtonColumnWidth,
                        action: { model.openSiriSettings() }
                    )
                    RequirementRow(
                        titleKey: "ai_requirements_ai_enabled",
                        value: model.aiAvailabilityDisplay,
                        status: model.aiStatus,
                        statusWidth: PMLayout.aiRequirementsStatusColumnWidth,
                        optionWidth: PMLayout.aiRequirementsOptionColumnWidth,
                        optionLeadingInset: PMLayout.aiRequirementsOptionLeadingInset,
                        valueWidth: PMLayout.aiRequirementsValueColumnWidth,
                        buttonKey: "ai_requirements_open_ai",
                        buttonWidth: PMLayout.aiRequirementsButtonColumnWidth,
                        action: { model.openAISettings() }
                    )

                    Text(LanguageSettings.localizedString("ai_requirements_notice"))
                        .font(.caption)
                        .foregroundColor(PMTheme.textSecondary)
                        .pmMultilineText()
                }
                .padding(PMLayout.aiRequirementsContentPadding)
            }

            Divider()

            PMWindowContentContainer {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PMLayout.compactSpacing) {
                        Spacer(minLength: PMLayout.zeroMinLength)
                        aiRequirementFooterActions
                    }

                    VStack(alignment: .trailing, spacing: PMLayout.compactSpacing) {
                        aiRequirementFooterActions
                    }
                }
                .padding(.horizontal, PMLayout.aiRequirementsFooterHorizontalPadding)
                .padding(.top, PMLayout.microSpacing)
                .frame(minHeight: PMLayout.aiRequirementsFooterHeight)
            }

            Spacer(minLength: PMLayout.zeroMinLength)

            PMWindowFooterHost()
        }
        .onAppear {
            Task { await model.refresh() }
            refreshWindowTitle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            refreshWindowTitle()
        }
    }

    private var aiRequirementFooterActions: some View {
        PMAdaptiveActionRow(verticalAlignment: .trailing, spacing: PMLayout.compactSpacing) {
            Button(LanguageSettings.localizedString("ai_requirements_refresh")) {
                Task { await model.refresh() }
            }
            .pmButton(role: .primary)

            Button(LanguageSettings.localizedString("common_close")) {
                dismiss()
            }
            .pmButton()
        }
    }

    private func refreshWindowTitle() {
        let title = LanguageSettings.localizedString("ai_requirements_window_title")
        if let keyWindow = NSApp.keyWindow {
            keyWindow.title = title
            return
        }
        if let aiWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == AppWindowID.aiRequirements }) {
            aiWindow.title = title
        }
    }
}

private struct RequirementRow: View {
    let titleKey: String
    let value: String?
    let status: RequirementStatus
    let statusWidth: CGFloat
    let optionWidth: CGFloat
    let optionLeadingInset: CGFloat
    let valueWidth: CGFloat
    let buttonKey: String
    let buttonWidth: CGFloat
    let action: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: PMLayout.compactSpacing) {
                statusDot
                    .frame(width: statusWidth, alignment: .leading)
                Text(LanguageSettings.localizedString(titleKey))
                    .foregroundColor(PMTheme.textSecondary)
                    .pmMultilineText()
                    .frame(width: optionWidth, alignment: .leading)
                    .padding(.leading, optionLeadingInset)
                valueView
                    .frame(width: valueWidth, alignment: .center)
                Button(LanguageSettings.localizedString(buttonKey)) {
                    action()
                }
                .pmButton()
                .frame(width: buttonWidth, alignment: .leading)
                Spacer(minLength: PMLayout.zeroMinLength)
            }

            VStack(alignment: .leading, spacing: PMLayout.compactSpacing) {
                HStack(alignment: .top, spacing: PMLayout.compactSpacing) {
                    statusDot
                    VStack(alignment: .leading, spacing: PMLayout.microSpacing + PMLayout.microSpacing) {
                        Text(LanguageSettings.localizedString(titleKey))
                            .foregroundColor(PMTheme.textSecondary)
                            .pmMultilineText()
                        valueView
                    }
                }

                Button(LanguageSettings.localizedString(buttonKey)) {
                    action()
                }
                .pmButton()
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(status.color)
            .frame(width: PMLayout.requirementStatusDotSize, height: PMLayout.requirementStatusDotSize)
            .padding(.trailing, PMLayout.requirementStatusTrailingPadding)
    }

    @ViewBuilder
    private var valueView: some View {
        if let value {
            Text(value)
                .foregroundColor(PMTheme.textPrimary)
                .pmMultilineText()
        } else {
            ProgressView()
                .controlSize(.small)
                .tint(PMTheme.textSecondary)
        }
    }
}

enum RequirementStatus {
    case ok
    case fail
    case unknown

    var color: Color {
        switch self {
        case .ok: return PMTheme.success
        case .fail: return PMTheme.danger
        case .unknown: return PMTheme.textMuted
        }
    }
}

@MainActor
final class AIRequirementsModel: ObservableObject {
    @Published private(set) var systemLanguageDisplay: String?
    @Published private(set) var siriLanguageDisplay: String?
    @Published private(set) var aiAvailabilityDisplay: String?
    @Published private(set) var systemStatus: RequirementStatus = .unknown
    @Published private(set) var siriStatus: RequirementStatus = .unknown
    @Published private(set) var aiStatus: RequirementStatus = .unknown

    private let supportedLanguages: Set<String> = [
        "en", "fr", "de", "it", "es", "ja", "ko", "zh"
    ]

    func refresh() async {
        systemLanguageDisplay = nil
        siriLanguageDisplay = nil
        aiAvailabilityDisplay = nil
        systemStatus = .unknown
        siriStatus = .unknown
        aiStatus = .unknown

        let systemCode = systemLanguageCode()
        systemLanguageDisplay = systemLanguageName() ?? "-"
        systemStatus = statusForLanguage(code: systemCode)

        let siriCode = siriLanguageCode()
        siriLanguageDisplay = siriLanguageName() ?? LanguageSettings.localizedString("ai_requirements_unknown")
        siriStatus = statusForLanguage(code: siriCode)

        let aiAvailability = await aiAvailabilityText()
        aiAvailabilityDisplay = aiAvailability.text
        aiStatus = aiAvailability.status
    }

    func openLanguageSettings() {
        openSystemSettings(urlString: "x-apple.systempreferences:com.apple.Localization-Settings.extension")
    }

    func openSiriSettings() {
        openSystemSettings(urlString: "x-apple.systempreferences:com.apple.Siri")
    }

    func openAISettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.AppleIntelligence-Settings.extension",
            "x-apple.systempreferences:com.apple.Intelligence-Settings.extension",
            "x-apple.systempreferences:com.apple.AppleIntelligence",
            "x-apple.systempreferences:com.apple.Siri"
        ]
        for url in urls {
            if openSystemSettings(urlString: url) {
                return
            }
        }
    }

    @discardableResult
    private func openSystemSettings(urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return NSWorkspace.shared.open(url)
    }

    private func systemLanguageCode() -> String? {
        Locale.current.language.languageCode?.identifier
    }

    private func systemLanguageName() -> String? {
        guard let code = systemLanguageCode() else { return nil }
        let appLocale = Locale(identifier: LanguageSettings.currentLanguageCode())
        let display = appLocale.localizedString(forLanguageCode: code) ?? code
        return "\(display) (\(code.uppercased()))"
    }

    private func siriLanguageCode() -> String? {
        let suites = [
            "com.apple.assistant",
            "com.apple.assistant.backedup",
            "com.apple.Siri",
            "com.apple.siri",
            "com.apple.siri.assistantd",
            "com.apple.speech.recognition",
            "com.apple.SpeechRecognitionCore",
            "com.apple.SpeechRecognitionCoreSM"
        ]
        let keys = [
            "SessionLanguage",
            "Session Language",
            "SiriLanguage",
            "SiriLanguageIdentifier",
            "SiriLocaleIdentifier",
            "AssistantLanguage",
            "Language",
            "DefaultLanguage",
            "LastUsedLanguage",
            "SessionLanguageCode",
            "SiriLanguageCode",
            "VoiceTriggerLanguage",
            "SpokenLanguage",
            "TTSLanguage",
            "VoiceLanguage",
            "SpeechLanguage",
            "SpokenLanguageIdentifier"
        ]

        for suiteName in suites {
            guard let suite = UserDefaults(suiteName: suiteName) else { continue }
            for key in keys {
                if let value = suite.string(forKey: key), !value.isEmpty {
                    Logger.shared.log("Siri language detected from \(suiteName).\(key): \(value)")
                    return value
                }
            }
        }

        let domains = suites
        for domain in domains {
            if let prefs = UserDefaults.standard.persistentDomain(forName: domain) {
                for key in keys {
                    if let value = prefs[key] as? String, !value.isEmpty {
                        Logger.shared.log("Siri language detected from persistentDomain \(domain).\(key): \(value)")
                        return value
                    }
                }
            }
        }

        for domain in suites {
            for key in keys {
                if let value = cfPreferencesValue(key: key, domain: domain) {
                    Logger.shared.log("Siri language detected from CFPreferences \(domain).\(key): \(value)")
                    return value
                }
            }
        }

        logSiriDomainsSnapshot(domains: suites)
        logSiriDomainsKeysList(domains: suites)
        Logger.shared.log("Siri language not found in known defaults suites")
        return nil
    }

    private func logSiriDomainsSnapshot(domains: [String]) {
        for domain in domains {
            if let prefs = UserDefaults.standard.persistentDomain(forName: domain) {
                let keys = prefs.keys.sorted()
                let interesting = keys.filter { key in
                    let lower = key.lowercased()
                    return lower.contains("siri") || lower.contains("language") || lower.contains("locale") || lower.contains("speech")
                }
                if !interesting.isEmpty {
                    Logger.shared.log("Siri prefs keys in \(domain): \(interesting.joined(separator: ", "))")
                }
            }
        }
    }

    private func logSiriDomainsKeysList(domains: [String]) {
        for domain in domains {
            if let keys = CFPreferencesCopyKeyList(
                domain as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? [String] {
                let interesting = keys.filter { key in
                    let lower = key.lowercased()
                    return lower.contains("siri") || lower.contains("language") || lower.contains("locale") || lower.contains("speech")
                }.sorted()
                if !interesting.isEmpty {
                    Logger.shared.log("Siri CFPreferences keys in \(domain): \(interesting.joined(separator: ", "))")
                }
            }
        }
    }

    private func cfPreferencesValue(key: String, domain: String) -> String? {
        let domainRef = domain as CFString
        let keyRef = key as CFString
        if let value = CFPreferencesCopyAppValue(keyRef, domainRef) as? String, !value.isEmpty {
            return value
        }
        if let value = CFPreferencesCopyValue(
            keyRef,
            domainRef,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? String, !value.isEmpty {
            return value
        }
        return nil
    }

    private func siriLanguageName() -> String? {
        guard let code = siriLanguageCode() else { return nil }
        let appLocale = Locale(identifier: LanguageSettings.currentLanguageCode())
        let display = appLocale.localizedString(forLanguageCode: code) ?? code
        return "\(display) (\(code.uppercased()))"
    }

    private func statusForLanguage(code: String?) -> RequirementStatus {
        guard let code else { return .unknown }
        let base = code.lowercased().split(separator: "-").first?.split(separator: "_").first.map(String.init) ?? code.lowercased()
        return supportedLanguages.contains(base) ? .ok : .fail
    }

    private func aiAvailabilityText() async -> (text: String, status: RequirementStatus) {
        #if canImport(FoundationModels) && compiler(>=6.2)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession()
                _ = try await session.respond(to: "Reply only with OK")
                return (LanguageSettings.localizedString("ai_requirements_available"), .ok)
            } catch {
                return (LanguageSettings.localizedString("ai_requirements_unavailable"), .fail)
            }
        }
        #endif
        return (LanguageSettings.localizedString("ai_requirements_unavailable"), .fail)
    }
}
