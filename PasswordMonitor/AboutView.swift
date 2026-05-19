//
//  AboutView.swift
//  PasswordMonitor
//
//  Created by Codex on 14/05/2026.
//

import SwiftUI
import AppKit
import PasswordMonitorCore

private enum AboutUpdateStatusKind {
    case info
    case success
    case error
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateRequestCenter: UpdateRequestCenter

    @State private var updateStatusText: String?
    @State private var updateStatusKind: AboutUpdateStatusKind = .info
    @State private var updateCheckInProgress = false
    @State private var pendingUpdateCandidate: PMUpdateCandidate?
    @State private var lastHandledCheckRequestID: UUID?

    private let updater = PMUpdateService(configuration: .passwordMonitor)

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var updateStatusColor: Color {
        switch updateStatusKind {
        case .info: return PMTheme.textSecondary
        case .success: return PMTheme.success
        case .error: return PMTheme.danger
        }
    }

    var body: some View {
        VStack(spacing: PMLayout.noSpacing) {
            PMWindowContentContainer {
                VStack(alignment: .leading, spacing: PMLayout.cardSpacing) {
                    heroCard
                    securityCard
                    updateCard
                    PMWindowActionBar {
                        footerActions
                    }
                }
            }
            .padding(.top, PMLayout.contentPadding)

            Spacer(minLength: PMLayout.zeroMinLength)

            PMWindowFooterHost()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            appState.windowOpened()
            handlePendingCheckRequestIfNeeded()
            DispatchQueue.main.async {
                appState.activateApp()
            }
        }
        .onChange(of: updateRequestCenter.checkRequestID) { _, _ in
            handlePendingCheckRequestIfNeeded()
        }
        .onDisappear {
            appState.windowClosed()
        }
    }

    private var heroCard: some View {
        HStack(alignment: .top, spacing: PMLayout.cardSpacing) {
            appIconTile

            VStack(alignment: .leading, spacing: PMLayout.controlSpacing) {
                Text(LanguageSettings.localizedString("about_title"))
                    .font(.system(size: PMLayout.aboutHeroTitleSize, weight: .semibold, design: .rounded))
                    .foregroundColor(PMTheme.textPrimary)

                Text(LanguageSettings.localizedString("about_subtitle"))
                    .font(.headline)
                    .foregroundColor(PMTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LanguageSettings.localizedString("about_description"))
                    .font(.callout)
                    .foregroundColor(PMTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: PMLayout.compactSpacing) {
                    Label {
                        Text(currentAppVersion)
                    } icon: {
                        Image(systemName: "number.circle.fill")
                    }
                    .font(.caption)
                    .foregroundColor(PMTheme.textSecondary)

                    Circle()
                        .fill(PMTheme.textMuted)
                        .frame(width: PMLayout.metadataDotSize, height: PMLayout.metadataDotSize)

                    Text(LanguageSettings.localizedString("about_single_source"))
                        .font(.caption)
                        .foregroundColor(PMTheme.textSecondary)
                }
            }

            Spacer(minLength: PMLayout.zeroMinLength)
        }
        .pmContentCard(padding: PMLayout.contentCardHeroPadding)
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: PMLayout.controlSpacing) {
            HStack(spacing: PMLayout.controlSpacing) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(PMTheme.success)
                Text(LanguageSettings.localizedString("about_release_security"))
                    .font(.headline)
                    .foregroundColor(PMTheme.textPrimary)
            }

            Text(LanguageSettings.localizedString("about_security_detail"))
                .font(.subheadline)
                .foregroundColor(PMTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pmContentCard()
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: PMLayout.sectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: PMLayout.microSpacing + PMLayout.microSpacing) {
                    Text(LanguageSettings.localizedString("about_updates_title"))
                        .font(.headline)
                        .foregroundColor(PMTheme.textPrimary)

                    Text(LanguageSettings.localizedString("about_updates_hint"))
                        .font(.caption)
                        .foregroundColor(PMTheme.textSecondary)
                }

                Spacer()

                if updateCheckInProgress {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let updateStatusText {
                HStack(alignment: .top, spacing: PMLayout.compactSpacing) {
                    Image(systemName: updateStatusIcon)
                        .foregroundColor(updateStatusColor)
                        .font(.caption.weight(.semibold))
                        .padding(.top, PMLayout.microSpacing)
                    Text(updateStatusText)
                        .font(.callout)
                        .foregroundColor(updateStatusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, PMLayout.microSpacing)
            } else {
                Text(LanguageSettings.localizedString("about_updates_idle"))
                    .font(.callout)
                    .foregroundColor(PMTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let pendingUpdateCandidate {
                HStack(spacing: PMLayout.controlSpacing) {
                    VStack(alignment: .leading, spacing: PMLayout.microSpacing) {
                        Text(LanguageSettings.localizedString(
                            "settings_update_available %@",
                            pendingUpdateCandidate.version.description
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(PMTheme.textPrimary)

                        Text(LanguageSettings.localizedString("about_updates_ready"))
                            .font(.caption)
                            .foregroundColor(PMTheme.textSecondary)
                    }

                    Spacer()

                    Button {
                        handleInstallUpdateTap()
                    } label: {
                        Text(LanguageSettings.localizedString("settings_update_install"))
                    }
                    .pmButton(role: .primary)
                    .disabled(updateCheckInProgress)
                }
                .pmFieldPanel(
                    padding: PMLayout.sectionSpacing,
                    cornerRadius: PMLayout.updateCandidateCornerRadius,
                    fillOpacity: PMTheme.fieldSubtleFillOpacity
                )
            }

            HStack(spacing: PMLayout.controlSpacing) {
                Button {
                    handleCheckForUpdatesTap()
                } label: {
                    HStack(spacing: PMLayout.compactSpacing) {
                        if updateCheckInProgress {
                            ProgressView()
                                .scaleEffect(PMLayout.inlineProgressScale)
                        }
                        Text(LanguageSettings.localizedString("settings_check_for_updates"))
                    }
                }
                .pmButton(role: .primary)
                .disabled(updateCheckInProgress)

                Button {
                    openWindow(id: "settings-window")
                    dismiss()
                } label: {
                    Text(LanguageSettings.localizedString("about_open_settings"))
                }
                .pmButton()

                Spacer()
            }
        }
        .pmContentCard()
    }

    private var footerActions: some View {
        HStack {
            Spacer()

            Button {
                dismiss()
            } label: {
                Text(LanguageSettings.localizedString("common_close"))
            }
            .pmButton()
        }
        .frame(maxWidth: .infinity)
    }

    private var appIconTile: some View {
        Image(nsImage: AppIconImageProvider.image(size: PMLayout.aboutIconImageSize))
            .resizable()
            .scaledToFit()
            .frame(width: PMLayout.aboutIconImageSize, height: PMLayout.aboutIconImageSize)
    }

    private func handleCheckForUpdatesTap() {
        updateRequestCenter.requestCheck()
    }

    private func handleInstallUpdateTap() {
        Task { await installPendingUpdate() }
    }

    @MainActor
    private func checkForUpdates() async {
        updateCheckInProgress = true
        defer { updateCheckInProgress = false }
        updateStatusText = nil
        pendingUpdateCandidate = nil

        do {
            let result = try await updater.checkForUpdate(currentVersion: currentAppVersion)
            switch result {
            case let .upToDate(localVersion, remoteVersion):
                let remoteText = remoteVersion?.description ?? "?"
                updateStatusKind = .info
                updateStatusText = LanguageSettings.localizedString(
                    "settings_update_up_to_date %@ %@",
                    localVersion.description,
                    remoteText
                )
            case let .updateAvailable(candidate):
                pendingUpdateCandidate = candidate
                updateStatusKind = .success
                updateStatusText = LanguageSettings.localizedString(
                    "settings_update_available %@",
                    candidate.version.description
                )
            @unknown default:
                updateStatusKind = .error
                updateStatusText = LanguageSettings.localizedString("settings_update_error %@", "Unknown update result")
            }
        } catch {
            updateStatusKind = .error
            updateStatusText = LanguageSettings.localizedString(
                "settings_update_error %@",
                error.localizedDescription
            )
        }
    }

    @MainActor
    private func installPendingUpdate() async {
        guard let candidate = pendingUpdateCandidate else { return }
        updateCheckInProgress = true
        defer { updateCheckInProgress = false }
        updateStatusKind = .info
        updateStatusText = LanguageSettings.localizedString(
            "settings_update_installing %@",
            candidate.version.description
        )

        do {
            try await updater.installUpdate(
                candidate: candidate,
                currentAppURL: Bundle.main.bundleURL,
                restartHandler: {
                    Task { @MainActor in
                        Self.relaunchMainApp()
                    }
                }
            )
            updateStatusKind = .success
            updateStatusText = LanguageSettings.localizedString("settings_update_installed_restart")
            pendingUpdateCandidate = nil
        } catch {
            updateStatusKind = .error
            updateStatusText = LanguageSettings.localizedString(
                "settings_update_error %@",
                error.localizedDescription
            )
        }
    }

    private static func relaunchMainApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + PMMotion.relaunchDelay) {
                NSApp.terminate(nil)
            }
        }
    }

    private func handlePendingCheckRequestIfNeeded() {
        guard let requestID = updateRequestCenter.checkRequestID else { return }
        guard requestID != lastHandledCheckRequestID else { return }
        guard !updateCheckInProgress else { return }
        lastHandledCheckRequestID = requestID
        Task { await checkForUpdates() }
    }

    private var updateStatusIcon: String {
        switch updateStatusKind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
