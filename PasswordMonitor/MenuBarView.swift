//
//  MenuBarView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import SwiftUI
import AppKit
import ServiceManagement
import PasswordMonitorCore
import Combine

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var notificationManager = NotificationManager.shared

    @State private var isChecking = false
    @State private var lastMenuRefreshAt: Date = .distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: PMLayout.sectionSpacing) {
            statusBlock

            VStack(spacing: PMLayout.compactSpacing) {
                menuButton(LanguageSettings.localizedString("menu_check_now"), role: .primary) {
                    checkPasswordNow()
                }
                .disabled(isChecking)

                menuButton(LanguageSettings.localizedString("menu_change_password")) {
                    Logger.shared.logLocalized("log_menu_change_password_selected")
                    PasswordChangeHelper.openSystemPasswordSettings()
                }
                .disabled(!canChangePasswordNow)
            }

            VStack(spacing: PMLayout.compactSpacing) {
                helperStatusRow

                HStack(spacing: PMLayout.compactSpacing) {
                    menuButton(LanguageSettings.localizedString("menu_settings")) {
                        presentWindow(id: "settings-window")
                    }

                    menuButton(LanguageSettings.localizedString("menu_logs")) {
                        presentWindow(id: "logs-window")
                    }
                }
            }

            Divider()

            VStack(spacing: PMLayout.compactSpacing) {
                menuButton(LanguageSettings.localizedString("menu_about_menubar"), role: .ghost) {
                    presentWindow(id: "about-window")
                }

                menuButton(LanguageSettings.localizedString("menu_quit"), role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            }

            copyrightText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pmMenuBarPanel()
        .onAppear {
            refreshPasswordStatus(reason: .menuOpen, shouldCheckNotification: true)
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: PMLayout.compactSpacing) {
            if let info = notificationManager.latestPasswordInfo {
                let daysRemaining = info.currentDaysUntilExpiration

                Text(LanguageSettings.localizedString("menu_password_expires_title"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(PMTheme.textSecondary)

                Text(LanguageSettings.localizedString("days_remaining %lld", daysRemaining))
                    .font(.system(size: PMLayout.menuStatusNumberSize, weight: .semibold, design: .rounded))
                    .foregroundColor(daysRemaining <= 7 ? PMTheme.danger : PMTheme.success)

                Divider()

                HStack {
                    Text(LanguageSettings.localizedString("menu_last_change_title"))
                    Spacer()
                    Text(info.lastSetDate, style: .date)
                }
                .font(.caption)
                .foregroundColor(PMTheme.textSecondary)

                if notificationManager.hasPerformedRefresh && !notificationManager.isDomainAvailable {
                    Text(LanguageSettings.localizedString("menu_domain_warning"))
                        .font(.caption)
                        .foregroundColor(PMTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: PMLayout.microSpacing) {
                    Text(LanguageSettings.localizedString("menu_check_status"))
                        .font(.headline)
                        .foregroundColor(PMTheme.textSecondary)

                    if notificationManager.hasPerformedRefresh && !notificationManager.isDomainAvailable {
                        Text(LanguageSettings.localizedString("menu_domain_warning"))
                            .font(.caption)
                            .foregroundColor(PMTheme.danger)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            if isChecking {
                HStack(spacing: PMLayout.compactSpacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text(LanguageSettings.localizedString("menu_checking_now"))
                        .font(.caption)
                        .foregroundColor(PMTheme.textSecondary)
                }
            }
        }
        .padding(PMLayout.menuStatusPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pmFieldPanel(
            cornerRadius: PMLayout.fieldCornerRadius,
            fillOpacity: PMTheme.fieldStatusFillOpacity
        )
    }

    private func presentWindow(id: String) {
        openWindow(id: id)
        dismiss()
        appState.presentWindow(id: id)
    }

    private var helperStatusRow: some View {
        HStack(spacing: PMLayout.compactSpacing) {
            Circle()
                .fill(helperServiceColor)
                .frame(width: PMLayout.menuStatusIndicatorSize, height: PMLayout.menuStatusIndicatorSize)

            Text(LanguageSettings.localizedString("menu_background_service"))
                .font(.caption)
                .foregroundColor(PMTheme.textSecondary)

            Spacer(minLength: PMLayout.zeroMinLength)
        }
        .padding(.horizontal, PMLayout.microSpacing)
    }

    private var copyrightText: some View {
        VStack(spacing: PMLayout.microSpacing) {
            Text("Copyright (c) 2026 Kamil Popowicz.")
            Text("All rights reserved.")
        }
        .font(.caption2)
        .foregroundColor(PMTheme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
        .padding(.top, PMLayout.microSpacing)
    }

    private func menuButton(
        _ title: String,
        role: PMButtonRole = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(PMLayout.menuButtonMinimumScale)
                .frame(maxWidth: .infinity)
        }
        .pmButton(role: role, size: .compact)
    }

    private var helperServiceColor: Color {
        let service = SMAppService.loginItem(identifier: "popo.PasswordMonitorHelperApp")
        return service.status == .enabled ? PMTheme.success : PMTheme.danger
    }

    private func checkPasswordNow() {
        refreshPasswordStatus(reason: .checkNow, shouldCheckNotification: true)
    }

    private func refreshPasswordStatus(reason: NotificationManager.CheckReason, shouldCheckNotification: Bool) {
        let now = Date()
        if isChecking || now.timeIntervalSince(lastMenuRefreshAt) < 1.0 {
            return
        }
        lastMenuRefreshAt = now
        isChecking = true
        Logger.shared.logLocalized("log_menu_refresh_started")
        notificationManager.refreshPasswordStatusLive(
            reason: reason,
            shouldCheckNotification: shouldCheckNotification,
            onResult: { info in
                self.isChecking = false
                Logger.shared.logLocalized("log_menu_refresh_finished")
            },
            onError: { error in
                self.isChecking = false
                Logger.shared.logLocalized("log_menu_refresh_finished")
                Logger.shared.logLocalized("log_menu_check_error %@", String(describing: error))
            }
        )
    }
    
    /// Czy przycisk „Zmień hasło” ma być aktywny
    private var canChangePasswordNow: Bool {
        guard let info = notificationManager.latestPasswordInfo else { return false }
        // Zachowujemy dotychczasową logikę: aktywuj od 28 dni przed deadlinem
        let withinThreshold = info.currentDaysUntilExpiration <= 28
        let domainAvailable = notificationManager.isDomainAvailable
        return withinThreshold && domainAvailable
    }
}

class AppState: ObservableObject {
    @Published var launchAtLogin = false
    private var windowCount = 0
    private var alertVisible = false
    private var alertObserver: Any?

    init() {
        NSApp.setActivationPolicy(.accessory)
        alertObserver = NotificationCenter.default.addObserver(
            forName: .passwordAlertVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let isVisible = (notification.userInfo?["isVisible"] as? Bool) ?? false
            self.alertVisible = isVisible
            self.updateActivationPolicy()
        }
    }

    deinit {
        if let alertObserver {
            NotificationCenter.default.removeObserver(alertObserver)
        }
    }

    func windowOpened() {
        windowCount += 1
        updateActivationPolicy()
    }

    func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func presentWindow(id: String) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        focusWindow(id: id, remainingAttempts: PMLayout.windowFocusRetryCount)
    }

    func windowClosed() {
        windowCount = max(0, windowCount - 1)
        updateActivationPolicy()
    }

    private func updateActivationPolicy() {
        let shouldShowDock = (windowCount > 0) || alertVisible
        NSApp.setActivationPolicy(shouldShowDock ? .regular : .accessory)
    }

    private func focusWindow(id: String, remainingAttempts: Int) {
        guard remainingAttempts > 0 else { return }

        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == id }) {
            moveToActiveScreenIfNeeded(window)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + PMMotion.windowFocusRetryDelay) {
            self.focusWindow(id: id, remainingAttempts: remainingAttempts - 1)
        }
    }

    private func moveToActiveScreenIfNeeded(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        guard let activeScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        guard window.screen != activeScreen else { return }

        let visibleFrame = activeScreen.visibleFrame
        let frame = window.frame
        let origin = NSPoint(
            x: visibleFrame.midX - (frame.width * PMLayout.centeringMultiplier),
            y: visibleFrame.midY - (frame.height * PMLayout.centeringMultiplier)
        )
        window.setFrameOrigin(origin)
    }
}
