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

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AIRequirementsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AIRequirementsModel()
    private let optionColumnWidth: CGFloat = 180

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                RequirementRow(
                    titleKey: "ai_requirements_system_language",
                    value: model.systemLanguageDisplay,
                    status: model.systemStatus,
                    optionWidth: optionColumnWidth,
                    buttonKey: "ai_requirements_open_language",
                    action: { model.openLanguageSettings() }
                )
                RequirementRow(
                    titleKey: "ai_requirements_siri_language",
                    value: model.siriLanguageDisplay,
                    status: model.siriStatus,
                    optionWidth: optionColumnWidth,
                    buttonKey: "ai_requirements_open_siri",
                    action: { model.openSiriSettings() }
                )
                RequirementRow(
                    titleKey: "ai_requirements_ai_enabled",
                    value: model.aiAvailabilityDisplay,
                    status: model.aiStatus,
                    optionWidth: optionColumnWidth,
                    buttonKey: "ai_requirements_open_ai",
                    action: { model.openAISettings() }
                )

                Text("ai_requirements_notice")
                    .font(.caption)
                    .foregroundColor(PMTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(minWidth: PMLayout.windowMinWidth, alignment: .leading)

            Divider()

            HStack(spacing: 8) {
                Spacer()

                Button("ai_requirements_refresh") {
                    Task { await model.refresh() }
                }
                .pmButton(role: .primary)

                Button("common_close") {
                    dismiss()
                }
                .pmButton()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            Task { await model.refresh() }
        }
    }
}

private struct RequirementRow: View {
    let titleKey: LocalizedStringKey
    let value: String
    let status: RequirementStatus
    let optionWidth: CGFloat
    let buttonKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
                .padding(.trailing, 6)
            Text(titleKey)
                .foregroundColor(PMTheme.textSecondary)
                .frame(width: optionWidth, alignment: .leading)
            Text(value)
                .foregroundColor(PMTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)
            Button(buttonKey) {
                action()
            }
            .pmButton()
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
    @Published private(set) var systemLanguageDisplay = "-"
    @Published private(set) var siriLanguageDisplay = "-"
    @Published private(set) var aiAvailabilityDisplay = "-"
    @Published private(set) var systemStatus: RequirementStatus = .unknown
    @Published private(set) var siriStatus: RequirementStatus = .unknown
    @Published private(set) var aiStatus: RequirementStatus = .unknown

    private let supportedLanguages: Set<String> = [
        "en", "fr", "de", "it", "es", "ja", "ko", "zh"
    ]

    func refresh() async {
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
        openSystemSettings(urlString: "x-apple.systempreferences:com.apple.AppleIntelligence-Settings.extension")
    }

    private func openSystemSettings(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func systemLanguageCode() -> String? {
        Locale.current.language.languageCode?.identifier
    }

    private func systemLanguageName() -> String? {
        guard let code = systemLanguageCode() else { return nil }
        let display = Locale.current.localizedString(forLanguageCode: code) ?? code
        return "\(display) (\(code.uppercased()))"
    }

    private func siriLanguageCode() -> String? {
        let suite = UserDefaults(suiteName: "com.apple.assistant")
        let candidates: [String?] = [
            suite?.string(forKey: "SessionLanguage"),
            suite?.string(forKey: "SiriLanguage"),
            suite?.string(forKey: "Language")
        ]
        if let match = candidates.compactMap({ $0 }).first {
            return match
        }
        return nil
    }

    private func siriLanguageName() -> String? {
        guard let code = siriLanguageCode() else { return nil }
        let display = Locale.current.localizedString(forLanguageCode: code) ?? code
        return "\(display) (\(code.uppercased()))"
    }

    private func statusForLanguage(code: String?) -> RequirementStatus {
        guard let code else { return .unknown }
        let base = code.lowercased().split(separator: "-").first?.split(separator: "_").first.map(String.init) ?? code.lowercased()
        return supportedLanguages.contains(base) ? .ok : .fail
    }

    private func aiAvailabilityText() async -> (text: String, status: RequirementStatus) {
        #if canImport(FoundationModels)
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

#Preview {
    AIRequirementsView()
}
