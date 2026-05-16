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
        VStack(alignment: .leading, spacing: 16) {
            heroCard
            securityCard
            updateCard
            footerActions
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            handlePendingCheckRequestIfNeeded()
        }
        .onChange(of: updateRequestCenter.checkRequestID) { _, _ in
            handlePendingCheckRequestIfNeeded()
        }
    }

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 16) {
            appIconTile

            VStack(alignment: .leading, spacing: 10) {
                Text(LanguageSettings.localizedString("about_title"))
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .foregroundColor(PMTheme.textPrimary)

                Text(LanguageSettings.localizedString("about_subtitle"))
                    .font(.headline)
                    .foregroundColor(PMTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LanguageSettings.localizedString("about_description"))
                    .font(.callout)
                    .foregroundColor(PMTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label {
                        Text(currentAppVersion)
                    } icon: {
                        Image(systemName: "number.circle.fill")
                    }
                    .font(.caption)
                    .foregroundColor(PMTheme.textSecondary)

                    Text("•")
                        .foregroundColor(PMTheme.textMuted)
                        .font(.caption)

                    Text(LanguageSettings.localizedString("about_single_source"))
                        .font(.caption)
                        .foregroundColor(PMTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .pmPanel()
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
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
        .padding(16)
        .pmPanel()
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
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
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: updateStatusIcon)
                        .foregroundColor(updateStatusColor)
                        .font(.caption.weight(.semibold))
                        .padding(.top, 2)
                    Text(updateStatusText)
                        .font(.callout)
                        .foregroundColor(updateStatusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            } else {
                Text(LanguageSettings.localizedString("about_updates_idle"))
                    .font(.callout)
                    .foregroundColor(PMTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let pendingUpdateCandidate {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
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
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PMTheme.fieldBackground.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(PMTheme.fieldStroke, lineWidth: 1)
                        )
                )
            }

            HStack(spacing: 10) {
                Button {
                    handleCheckForUpdatesTap()
                } label: {
                    HStack(spacing: 8) {
                        if updateCheckInProgress {
                            ProgressView()
                                .scaleEffect(0.8)
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
        .padding(16)
        .pmPanel()
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
    }

    private var appIconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PMTheme.accent.opacity(0.35),
                            PMTheme.panelStroke.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(PMTheme.panelStroke, lineWidth: 1)
                )

            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 72, height: 72)))
                    .resizable()
                    .scaledToFit()
                    .padding(12)

                Text(currentAppVersion)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(PMTheme.textSecondary)

                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.caption2.weight(.semibold))
                    Text(LanguageSettings.localizedString("about_author"))
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(PMTheme.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(PMTheme.fieldBackground.opacity(0.75))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(PMTheme.fieldStroke.opacity(0.8), lineWidth: 1)
                        )
                )
            }
        }
        .frame(width: 118, height: 118)
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
                restartHandler: relaunchMainApp
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

    private func relaunchMainApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
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
