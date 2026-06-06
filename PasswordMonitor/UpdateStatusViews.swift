//
//  UpdateStatusViews.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 06/06/2026.
//

import SwiftUI
import PasswordMonitorCore

struct UpdateCommandReceiver: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateRequestCenter: UpdateRequestCenter
    @ObservedObject private var updateMonitor = PMUpdateMonitor.shared

    var body: some View {
        Color.clear
            .frame(width: PMLayout.noSpacing, height: PMLayout.noSpacing)
            .onAppear {
                updateMonitor.reload()
                consumePendingInstallRequestIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: HelperMessaging.updateInstallRequestedNotification)) { _ in
                startUpdateFlow()
            }
            .onReceive(DistributedNotificationCenter.default().publisher(for: HelperMessaging.updateInstallRequestedNotification)) { _ in
                startUpdateFlow()
            }
    }

    private func consumePendingInstallRequestIfNeeded() {
        guard updateMonitor.consumePendingInstallRequest() else { return }
        startUpdateFlow()
    }

    private func startUpdateFlow() {
        openWindow(id: AppWindowID.about)
        appState.presentWindow(id: AppWindowID.about)
        if updateMonitor.state.urgency == .critical {
            updateRequestCenter.requestCriticalUpdate()
        } else {
            updateRequestCenter.requestStartDetectedUpdate()
        }
    }
}

struct UpdateStatusOverlayModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateRequestCenter: UpdateRequestCenter

    let allowsCriticalInteraction: Bool

    func body(content: Content) -> some View {
        UpdateStatusOverlayHost(
            allowsCriticalInteraction: allowsCriticalInteraction,
            startUpdateFlow: startUpdateFlow
        ) {
            content
        } receiver: {
            UpdateCommandReceiver()
        }
    }

    private func startUpdateFlow() {
        openWindow(id: AppWindowID.about)
        appState.presentWindow(id: AppWindowID.about)
        if PMUpdateMonitor.shared.state.urgency == .critical {
            updateRequestCenter.requestCriticalUpdate()
        } else {
            updateRequestCenter.requestStartDetectedUpdate()
        }
    }
}

struct ActionUpdateStatusOverlayModifier: ViewModifier {
    let allowsCriticalInteraction: Bool
    let startUpdateFlow: () -> Void

    func body(content: Content) -> some View {
        UpdateStatusOverlayHost(
            allowsCriticalInteraction: allowsCriticalInteraction,
            startUpdateFlow: startUpdateFlow
        ) {
            content
        } receiver: {
            EmptyView()
        }
    }
}

private struct UpdateStatusOverlayHost<Content: View, Receiver: View>: View {
    @ObservedObject private var updateMonitor = PMUpdateMonitor.shared

    let allowsCriticalInteraction: Bool
    let startUpdateFlow: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let receiver: () -> Receiver

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: PMLayout.noSpacing) {
                if shouldShowReservedBanner {
                    updateBanner
                        .padding(.top, PMLayout.compactSpacing)
                        .padding(.horizontal, PMLayout.contentPadding)
                        .padding(.bottom, PMLayout.compactSpacing)
                }

                content()
                    .disabled(updateMonitor.state.isCriticalBlocking && !allowsCriticalInteraction)
            }

            if updateMonitor.state.isCriticalBlocking && !allowsCriticalInteraction {
                criticalBlocker
            }

            receiver()
        }
        .onAppear {
            updateMonitor.reload()
        }
    }

    private var shouldShowReservedBanner: Bool {
        shouldShowStatusBanner && (!updateMonitor.state.isCriticalBlocking || allowsCriticalInteraction)
    }

    private var shouldShowStatusBanner: Bool {
        guard updateMonitor.state.isUpdateAvailable else { return false }
        if updateMonitor.state.urgency == .critical { return true }
        if let remindLaterUntil = updateMonitor.state.remindLaterUntil,
           remindLaterUntil > Date() {
            return false
        }
        return true
    }

    private var updateBanner: some View {
        HStack(spacing: PMLayout.compactSpacing) {
            Button {
                startUpdateFlow()
            } label: {
                HStack(spacing: PMLayout.compactSpacing) {
                    Image(systemName: updateMonitor.state.urgency == .critical ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill")
                        .foregroundColor(updateMonitor.state.urgency == .critical ? PMTheme.danger : PMTheme.accent)
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(PMTheme.textPrimary)
                        .pmMultilineText()
                    Spacer(minLength: PMLayout.compactSpacing)
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(PMTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(statusText)

            if updateMonitor.state.urgency != .critical {
                Button {
                    updateMonitor.remindLater()
                } label: {
                    Label(LanguageSettings.localizedString("update_remind_later"), systemImage: "clock")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundColor(PMTheme.textSecondary)
                .help(LanguageSettings.localizedString("update_remind_later"))
            }
        }
        .padding(.horizontal, PMLayout.sectionSpacing)
        .padding(.vertical, PMLayout.compactSpacing)
        .pmFieldPanel(
            cornerRadius: PMLayout.smallFieldCornerRadius,
            fillOpacity: PMTheme.fieldSubtleFillOpacity,
            strokeOpacity: PMTheme.fieldSoftStrokeOpacity
        )
    }

    private var criticalBlocker: some View {
        ZStack {
            PMTheme.overlayScrim
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: PMLayout.sectionSpacing) {
                HStack(spacing: PMLayout.controlSpacing) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(PMTheme.danger)
                    Text(LanguageSettings.localizedString("update_critical_title"))
                        .font(.headline)
                        .foregroundColor(PMTheme.textPrimary)
                }

                Text(LanguageSettings.localizedString("update_critical_body"))
                    .font(.callout)
                    .foregroundColor(PMTheme.textSecondary)
                    .pmMultilineText()

                Text(LanguageSettings.localizedString("update_critical_notifications_paused"))
                    .font(.caption)
                    .foregroundColor(PMTheme.danger)
                    .pmMultilineText()

                if let version = updateMonitor.state.availableVersion {
                    Text(LanguageSettings.localizedString("settings_update_available %@", version))
                        .font(.caption)
                        .foregroundColor(PMTheme.textSecondary)
                        .pmMultilineText()
                }

                if let error = updateMonitor.state.lastBackgroundError {
                    Text(LanguageSettings.localizedString("update_last_error %@", error))
                        .font(.caption)
                        .foregroundColor(PMTheme.danger)
                        .pmMultilineText()
                }

                PMAdaptiveActionRow(spacing: PMLayout.compactSpacing) {
                    Button {
                        startUpdateFlow()
                    } label: {
                        Text(LanguageSettings.localizedString(updateMonitor.state.lastBackgroundError == nil ? "update_install_now" : "update_retry_update"))
                            .pmMultilineText(alignment: .center)
                    }
                    .pmButton(role: .primary)
                }
            }
            .frame(maxWidth: PMLayout.passwordKeychainHelpMinWidth, alignment: .leading)
            .pmContentCard()
            .padding(PMLayout.contentPadding)
        }
    }

    private var statusText: String {
        guard let version = updateMonitor.state.availableVersion else {
            return LanguageSettings.localizedString("update_available_short")
        }
        if updateMonitor.state.urgency == .critical {
            return LanguageSettings.localizedString("update_critical_short %@", version)
        }
        return LanguageSettings.localizedString("update_available_short %@", version)
    }

}

extension View {
    func updateStatusOverlay(allowsCriticalInteraction: Bool = false) -> some View {
        modifier(UpdateStatusOverlayModifier(allowsCriticalInteraction: allowsCriticalInteraction))
    }

    func updateStatusOverlay(
        allowsCriticalInteraction: Bool = false,
        startUpdateFlow: @escaping () -> Void
    ) -> some View {
        modifier(ActionUpdateStatusOverlayModifier(
            allowsCriticalInteraction: allowsCriticalInteraction,
            startUpdateFlow: startUpdateFlow
        ))
    }
}
