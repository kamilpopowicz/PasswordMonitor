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
    @ObservedObject private var updateMonitor = PMUpdateMonitor.shared

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
                    dismiss()
                    PasswordChangeHelper.requestPasswordChange()
                }
                .disabled(!canChangePasswordNow)
            }

            VStack(spacing: PMLayout.compactSpacing) {
                helperStatusRow

                HStack(spacing: PMLayout.compactSpacing) {
                    menuButton(LanguageSettings.localizedString("menu_settings")) {
                        presentWindow(id: AppWindowID.settings)
                    }

                    menuButton(LanguageSettings.localizedString("menu_logs")) {
                        presentWindow(id: AppWindowID.logs)
                    }
                }
            }

            Divider()

            VStack(spacing: PMLayout.compactSpacing) {
                menuButton(LanguageSettings.localizedString("menu_about_menubar"), role: .ghost) {
                    presentWindow(id: AppWindowID.about)
                }

                menuButton(LanguageSettings.localizedString("menu_quit"), role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            }

            copyrightText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pmMenuBarPanel()
        .background(PMMenuBarWindowConfigurator())
        .onAppear {
            refreshPasswordStatus(reason: .menuOpen, shouldCheckNotification: true)
            Task {
                await updateMonitor.checkIfNeeded(currentVersion: currentAppVersion, trigger: .menuOpen)
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: PMLayout.compactSpacing) {
            if let info = notificationManager.latestPasswordInfo {
                let daysRemaining = info.currentDaysUntilExpiration

                Text(LanguageSettings.localizedString("menu_password_expires_title"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(PMTheme.textSecondary)
                    .pmMultilineText()

                Text(LanguageSettings.localizedString("days_remaining %lld", daysRemaining))
                    .font(.system(size: PMLayout.menuStatusNumberSize, weight: .semibold, design: .rounded))
                    .foregroundColor(daysRemaining <= 7 ? PMTheme.danger : PMTheme.success)
                    .pmMultilineText()

                Divider()

                HStack {
                    Text(LanguageSettings.localizedString("menu_last_change_title"))
                        .pmMultilineText()
                    Spacer()
                    Text(info.lastSetDate, style: .date)
                }
                .font(.caption)
                .foregroundColor(PMTheme.textSecondary)

                if notificationManager.hasPerformedRefresh && !notificationManager.isDomainAvailable {
                    Text(LanguageSettings.localizedString("menu_domain_warning"))
                        .font(.caption)
                        .foregroundColor(PMTheme.danger)
                        .pmMultilineText()
                }
            } else {
                VStack(alignment: .leading, spacing: PMLayout.microSpacing) {
                    Text(LanguageSettings.localizedString("menu_check_status"))
                        .font(.headline)
                        .foregroundColor(PMTheme.textSecondary)
                        .pmMultilineText()

                    if notificationManager.hasPerformedRefresh && !notificationManager.isDomainAvailable {
                        Text(LanguageSettings.localizedString("menu_domain_warning"))
                            .font(.caption)
                            .foregroundColor(PMTheme.danger)
                            .pmMultilineText()
                    }
                }
            }

            if isChecking {
                HStack(spacing: PMLayout.compactSpacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text(LanguageSettings.localizedString("menu_checking_now"))
                        .font(.caption)
                        .foregroundColor(PMTheme.textSecondary)
                        .pmMultilineText()
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
                .pmMultilineText()

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
                .pmMultilineText(alignment: .center)
                .minimumScaleFactor(PMLayout.menuButtonMinimumScale)
                .frame(maxWidth: .infinity)
        }
        .pmButton(role: role, size: .compact)
    }

    private var helperServiceColor: Color {
        let service = SMAppService.loginItem(identifier: "popo.PasswordMonitorHelperApp")
        return service.status == .enabled ? PMTheme.success : PMTheme.danger
    }

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
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
        !updateMonitor.state.isCriticalBlocking
            && notificationManager.hasPerformedRefresh
            && notificationManager.isDomainAvailable
    }
}

class AppState: ObservableObject {
    @Published var launchAtLogin = false
    private var alertVisible = false
    private var alertObserver: Any?
    private var registeredWindows: [String: ObjectIdentifier] = [:]

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

    func registerWindow(_ window: NSWindow, id: String) {
        window.identifier = NSUserInterfaceItemIdentifier(id)
        let identifier = ObjectIdentifier(window)
        let isNewWindow = registeredWindows[id] != identifier
        registeredWindows[id] = identifier
        updateActivationPolicy()

        if isNewWindow {
            presentWindow(id: id)
        }
    }

    func presentWindow(id: String) {
        NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        focusWindow(id: id, remainingAttempts: PMLayout.windowFocusRetryCount)
    }

    func windowBecameVisible(_ window: NSWindow, id: String) {
        window.identifier = NSUserInterfaceItemIdentifier(id)
        presentWindow(id: id)
    }

    func windowStateChanged() {
        updateActivationPolicy()
    }

    func windowWillClose(_ window: NSWindow, id: String) {
        if registeredWindows[id] == ObjectIdentifier(window) {
            registeredWindows.removeValue(forKey: id)
        }
        DispatchQueue.main.async { [weak self] in
            self?.updateActivationPolicy()
        }
    }

    private func updateActivationPolicy() {
        let hasOpenStandardWindow = NSApp.windows.contains { window in
            guard let id = window.identifier?.rawValue,
                  AppWindowID.standard.contains(id),
                  registeredWindows[id] == ObjectIdentifier(window) else {
                return false
            }
            return window.isVisible || window.isMiniaturized
        }
        let hasOpenPasswordChangeWindow = NSApp.windows.contains { window in
            window.identifier?.rawValue == AppWindowID.passwordChange
                && (window.isVisible || window.isMiniaturized)
        }
        let shouldShowDock = hasOpenStandardWindow || hasOpenPasswordChangeWindow || alertVisible
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
