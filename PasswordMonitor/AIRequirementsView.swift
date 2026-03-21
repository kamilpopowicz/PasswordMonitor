//
//  AIRequirementsView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 20/03/2026.
//

import SwiftUI
import AppKit

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AIRequirementsView: View {
    @StateObject private var model = AIRequirementsModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("ai_requirements_title")
                    .font(.title2)
                    .foregroundColor(PMTheme.textPrimary)

                RequirementRow(titleKey: "ai_requirements_system_language", value: model.systemLanguageDisplay)
                RequirementRow(titleKey: "ai_requirements_siri_language", value: model.siriLanguageDisplay)
                RequirementRow(titleKey: "ai_requirements_ai_enabled", value: model.aiAvailabilityDisplay)

                Text("ai_requirements_notice")
                    .font(.caption)
                    .foregroundColor(PMTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()

            Divider()

            HStack(spacing: 8) {
                Button("ai_requirements_open_language") {
                    model.openLanguageSettings()
                }
                .pmButton()

                Button("ai_requirements_open_siri") {
                    model.openSiriSettings()
                }
                .pmButton()

                Spacer()

                Button("ai_requirements_refresh") {
                    Task { await model.refresh() }
                }
                .pmButton(role: .primary)
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

    var body: some View {
        HStack {
            Text(titleKey)
                .foregroundColor(PMTheme.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(PMTheme.textPrimary)
        }
    }
}

@MainActor
final class AIRequirementsModel: ObservableObject {
    @Published private(set) var systemLanguageDisplay = "-"
    @Published private(set) var siriLanguageDisplay = "-"
    @Published private(set) var aiAvailabilityDisplay = "-"

    func refresh() async {
        systemLanguageDisplay = systemLanguageName() ?? "-"
        siriLanguageDisplay = siriLanguageName() ?? LanguageSettings.localizedString("ai_requirements_unknown")
        aiAvailabilityDisplay = await aiAvailabilityText()
    }

    func openLanguageSettings() {
        openSystemSettings(urlString: "x-apple.systempreferences:com.apple.Localization-Settings.extension")
    }

    func openSiriSettings() {
        openSystemSettings(urlString: "x-apple.systempreferences:com.apple.Siri")
    }

    private func openSystemSettings(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func systemLanguageName() -> String? {
        guard let code = Locale.current.language.languageCode?.identifier else { return nil }
        let display = Locale.current.localizedString(forLanguageCode: code) ?? code
        return "\(display) (\(code.uppercased()))"
    }

    private func siriLanguageName() -> String? {
        let suite = UserDefaults(suiteName: "com.apple.assistant")
        let candidates: [String?] = [
            suite?.string(forKey: "SessionLanguage"),
            suite?.string(forKey: "SiriLanguage"),
            suite?.string(forKey: "Language")
        ]
        if let match = candidates.compactMap({ $0 }).first {
            let display = Locale.current.localizedString(forLanguageCode: match) ?? match
            return "\(display) (\(match.uppercased()))"
        }
        return nil
    }

    private func aiAvailabilityText() async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession()
                _ = try await session.respond(to: "Reply only with OK")
                return LanguageSettings.localizedString("ai_requirements_available")
            } catch {
                return LanguageSettings.localizedString("ai_requirements_unavailable")
            }
        }
        #endif
        return LanguageSettings.localizedString("ai_requirements_unavailable")
    }
}

#Preview {
    AIRequirementsView()
}
