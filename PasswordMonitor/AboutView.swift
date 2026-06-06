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

    @ObservedObject private var updateMonitor = PMUpdateMonitor.shared

    @State private var updateStatusText: String?
    @State private var updateStatusKind: AboutUpdateStatusKind = .info
    @State private var updateCheckInProgress = false
    @State private var pendingUpdateCandidate: PMUpdateCandidate?
    @State private var lastHandledCheckRequestID: UUID?
    @State private var lastHandledUpdateRequestID: UUID?
    @State private var deferredCheckRequestID: UUID?
    @State private var deferredUpdateRequest: UpdateRequestCenter.Request?

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
            handlePendingCheckRequestIfNeeded()
            handlePendingUpdateRequestIfNeeded()
        }
        .onChange(of: updateRequestCenter.checkRequestID) { _, _ in
            handlePendingCheckRequestIfNeeded()
        }
        .onChange(of: updateRequestCenter.request?.id) { _, _ in
            handlePendingUpdateRequestIfNeeded()
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
                    .pmMultilineText()

                Text(LanguageSettings.localizedString("about_description"))
                    .font(.callout)
                    .foregroundColor(PMTheme.textSecondary)
                    .pmMultilineText()

                PMAdaptiveActionRow(spacing: PMLayout.compactSpacing) {
                    Label {
                        Text(currentAppVersion)
                            .pmMultilineText()
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
                        .pmMultilineText()
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
                .pmMultilineText()
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
                        .pmMultilineText()
                }
                .padding(.top, PMLayout.microSpacing)
            } else {
                Text(LanguageSettings.localizedString("about_updates_idle"))
                    .font(.callout)
                    .foregroundColor(PMTheme.textSecondary)
                    .pmMultilineText()
            }

            if updateMonitor.state.isCriticalBlocking {
                HStack(alignment: .top, spacing: PMLayout.compactSpacing) {
                    Image(systemName: "bell.slash.fill")
                        .foregroundColor(PMTheme.danger)
                        .font(.caption.weight(.semibold))
                        .padding(.top, PMLayout.microSpacing)
                    Text(LanguageSettings.localizedString("update_critical_notifications_paused"))
                        .font(.caption)
                        .foregroundColor(PMTheme.danger)
                        .pmMultilineText()
                }
            }

            if let backgroundUpdateErrorText {
                HStack(alignment: .top, spacing: PMLayout.compactSpacing) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(PMTheme.danger)
                        .font(.caption.weight(.semibold))
                        .padding(.top, PMLayout.microSpacing)
                    Text(backgroundUpdateErrorText)
                        .font(.caption)
                        .foregroundColor(PMTheme.danger)
                        .pmMultilineText()
                }
            }

            if let pendingUpdateCandidate {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PMLayout.controlSpacing) {
                        updateCandidateText(pendingUpdateCandidate)
                        Spacer(minLength: PMLayout.compactSpacing)
                        updateInstallButton
                    }

                    VStack(alignment: .leading, spacing: PMLayout.compactSpacing) {
                        updateCandidateText(pendingUpdateCandidate)
                        updateInstallButton
                    }
                }
                .pmFieldPanel(
                    padding: PMLayout.sectionSpacing,
                    cornerRadius: PMLayout.updateCandidateCornerRadius,
                    fillOpacity: PMTheme.fieldSubtleFillOpacity
                )
            }

            PMAdaptiveActionRow(spacing: PMLayout.controlSpacing) {
                Button {
                    handleCheckForUpdatesTap()
                } label: {
                    HStack(spacing: PMLayout.compactSpacing) {
                        if updateCheckInProgress {
                            ProgressView()
                                .scaleEffect(PMLayout.inlineProgressScale)
                        }
                        Text(LanguageSettings.localizedString("settings_check_for_updates"))
                            .pmMultilineText(alignment: .center)
                    }
                }
                .pmButton(role: .primary)
                .disabled(updateCheckInProgress)

                Button {
                    presentWindow(id: AppWindowID.settings)
                    dismiss()
                } label: {
                    Text(LanguageSettings.localizedString("about_open_settings"))
                        .pmMultilineText(alignment: .center)
                }
                .pmButton()
            }
        }
        .pmContentCard()
    }

    private func presentWindow(id: String) {
        openWindow(id: id)
        appState.presentWindow(id: id)
    }

    private func updateCandidateText(_ candidate: PMUpdateCandidate) -> some View {
        VStack(alignment: .leading, spacing: PMLayout.microSpacing) {
            Text(LanguageSettings.localizedString(
                "settings_update_available %@",
                candidate.version.description
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundColor(PMTheme.textPrimary)
            .pmMultilineText()

            Text(LanguageSettings.localizedString("about_updates_ready"))
                .font(.caption)
                .foregroundColor(PMTheme.textSecondary)
                .pmMultilineText()
        }
    }

    private var updateInstallButton: some View {
        Button {
            handleInstallUpdateTap()
        } label: {
            Text(LanguageSettings.localizedString("settings_update_install"))
                .pmMultilineText(alignment: .center)
        }
        .pmButton(role: .primary)
        .disabled(updateCheckInProgress)
    }

    private var footerActions: some View {
        HStack {
            Spacer()

            Button {
                dismiss()
            } label: {
                Text(LanguageSettings.localizedString("common_close"))
                    .pmMultilineText(alignment: .center)
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
    private func checkForUpdates(autoInstall: Bool = false) async {
        updateCheckInProgress = true
        defer {
            updateCheckInProgress = false
            handleDeferredRequestsIfNeeded()
        }
        updateStatusText = nil
        pendingUpdateCandidate = nil

        do {
            let result = try await updater.checkForUpdate(currentVersion: currentAppVersion)
            switch result {
            case let .upToDate(localVersion, remoteVersion):
                updateMonitor.clearDetectedUpdate()
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
                PMUpdateMonitor.shared.clearDetectedUpdate()
                UpdateNotificationStateStore.shared.recordAvailableUpdate(
                    version: candidate.version.description,
                    releaseTag: candidate.releaseTag,
                    urgency: candidate.urgency
                )
                updateMonitor.reload()
                if autoInstall {
                    await installUpdate(candidate)
                }
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
        guard candidate.isFresh() else {
            await checkForUpdates(autoInstall: true)
            return
        }
        await installUpdate(candidate)
    }

    @MainActor
    private func installUpdate(_ candidate: PMUpdateCandidate) async {
        guard candidate.isFresh() else {
            await checkForUpdates(autoInstall: true)
            return
        }

        let currentAppURL = Bundle.main.bundleURL
        updateCheckInProgress = true
        defer {
            updateCheckInProgress = false
            handleDeferredRequestsIfNeeded()
        }
        updateStatusKind = .info
        updateStatusText = LanguageSettings.localizedString(
            "settings_update_installing %@",
            candidate.version.description
        )

        do {
            try await updater.installUpdate(
                candidate: candidate,
                currentAppURL: currentAppURL,
                restartHandler: {
                    Task { @MainActor in
                        Self.scheduleRelaunchMainApp(at: currentAppURL)
                    }
                }
            )
            updateStatusKind = .success
            updateStatusText = LanguageSettings.localizedString("settings_update_installed_restart")
            pendingUpdateCandidate = nil
            updateMonitor.clearDetectedUpdate()
        } catch {
            updateStatusKind = .error
            updateStatusText = LanguageSettings.localizedString(
                "settings_update_error %@",
                error.localizedDescription
            )
        }
    }

    private static func scheduleRelaunchMainApp(at appURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 0.8; /usr/bin/open \"$1\"",
            "passwordmonitor-relaunch",
            appURL.path
        ]

        do {
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + PMMotion.relaunchDelay) {
                NSApp.terminate(nil)
            }
        } catch {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + PMMotion.relaunchDelay) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func handlePendingCheckRequestIfNeeded() {
        guard let requestID = updateRequestCenter.checkRequestID else { return }
        guard requestID != lastHandledCheckRequestID else { return }
        handleCheckRequest(requestID)
    }

    private func handlePendingUpdateRequestIfNeeded() {
        guard let request = updateRequestCenter.request else { return }
        guard request.id != lastHandledUpdateRequestID else { return }
        handleUpdateRequest(request)
    }

    private func handleCheckRequest(_ requestID: UUID) {
        guard !updateCheckInProgress else {
            deferredCheckRequestID = requestID
            return
        }
        lastHandledCheckRequestID = requestID
        Task { await checkForUpdates() }
    }

    private func handleUpdateRequest(_ request: UpdateRequestCenter.Request) {
        guard !updateCheckInProgress else {
            deferredUpdateRequest = request
            return
        }
        lastHandledUpdateRequestID = request.id

        switch request.kind {
        case .checkOnly:
            Task { await checkForUpdates() }
        case .startDetectedUpdate, .criticalUpdate:
            Task { await checkForUpdates(autoInstall: true) }
        }
    }

    private func handleDeferredRequestsIfNeeded() {
        if let request = deferredUpdateRequest,
           request.id != lastHandledUpdateRequestID {
            deferredUpdateRequest = nil
            handleUpdateRequest(request)
            return
        }

        if let requestID = deferredCheckRequestID,
           requestID != lastHandledCheckRequestID {
            deferredCheckRequestID = nil
            handleCheckRequest(requestID)
        }
    }

    private var updateStatusIcon: String {
        switch updateStatusKind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var backgroundUpdateErrorText: String? {
        let state = updateMonitor.state
        guard let error = state.lastBackgroundError else { return nil }
        if let date = state.lastBackgroundErrorAt {
            let dateText = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
            return LanguageSettings.localizedString("update_last_error_with_date %@ %@", dateText, error)
        }
        return LanguageSettings.localizedString("update_last_error %@", error)
    }
}
