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

    @State private var passwordInfo: PasswordInfo?
    @State private var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            if let info = passwordInfo {
                Text("menu_password_expires_title")
                    .font(.headline)
                    .foregroundColor(PMTheme.textSecondary)

                Text(LanguageSettings.localizedString("days_remaining %lld", info.daysUntilExpiration))
                    .font(.title2)
                    .foregroundColor(info.daysUntilExpiration <= 7 ? PMTheme.danger : PMTheme.success)

                Divider()

                Text("menu_last_change_title")
                    .font(.caption)
                    .foregroundColor(PMTheme.textSecondary)

                Text(info.lastSetDate, style: .date)
                    .font(.caption)
                    .foregroundColor(PMTheme.textSecondary)
                
                // ostrzeżenie, jeśli dane są z cache (domena niedostępna)
                if info.isFromCache {
                    Text("menu_domain_warning")
                        .font(.caption)
                        .foregroundColor(PMTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("menu_check_status")
                    .font(.headline)
                    .foregroundColor(PMTheme.textSecondary)
            }

            Divider()

            // Akcje
            Button("menu_check_now") {
                checkPasswordNow()
            }
            .disabled(isChecking)

            Button("menu_change_password") {
                Logger.shared.logLocalized("log_menu_change_password_selected")
                PasswordChangeHelper.openSystemPasswordSettings()
            }
            .disabled(!canChangePasswordNow)
            .opacity(canChangePasswordNow ? 1.0 : 0.5)

            Divider()

            // Helper service status
            HStack {
                Circle()
                    .fill(helperServiceColor)
                    .frame(width: 8, height: 8)

                Text("menu_background_service")
                    .font(.caption)
                    .foregroundColor(PMTheme.textSecondary)
            }

            Button("menu_settings") {
                openWindow(id: "settings-window")
            }
            .controlSize(.regular)

            Button("menu_logs") {
                openWindow(id: "logs-window")
            }
            .controlSize(.regular)

            Divider()

            Button("menu_quit") {
                NSApplication.shared.terminate(nil)
            }

            Divider()

            VStack(spacing: 2) {
                Text("Copyright (c) 2026 Kamil Popowicz.")
                Text("All rights reserved.")
            }
            .font(.caption2)
            .foregroundColor(PMTheme.textSecondary)
            .padding(.vertical, 12)
        }
        .pmPanel()
        .frame(width: 260)
        .onAppear {
            checkPasswordNow()
        }
    }

    private var helperServiceColor: Color {
        let service = SMAppService.loginItem(identifier: "popo.PasswordMonitorHelperApp")
        return service.status == .enabled ? PMTheme.success : PMTheme.danger
    }

    private func checkPasswordNow() {
        isChecking = true

        DispatchQueue.global(qos: .userInitiated).async {
            let manager = ActiveDirectoryManager()
            let username = NSUserName()

            do {
                let info = try manager.getPasswordInfo(for: username)

                DispatchQueue.main.async {
                    self.passwordInfo = info
                    self.isChecking = false

                    // Jeśli wg Twojej logiki trzeba ostrzec – przekaż datę do NotificationManager
                    if manager.shouldShowWarning(passwordInfo: info) {
                        NotificationManager.shared.updateExpirationDate(info.expiryDate)
                        NotificationManager.shared.checkAndShowNotificationIfNeeded()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isChecking = false
                    Logger.shared.logLocalized("log_menu_check_error %@", String(describing: error))
                }
            }
        }
    }
    
    /// Czy przycisk „Zmień hasło” ma być aktywny
    private var canChangePasswordNow: Bool {
        guard let info = passwordInfo else { return false }
        // Zachowujemy dotychczasową logikę: aktywuj od 28 dni przed deadlinem
        return info.daysUntilExpiration <= 28
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

    func windowClosed() {
        windowCount = max(0, windowCount - 1)
        updateActivationPolicy()
    }

    private func updateActivationPolicy() {
        let shouldShowDock = (windowCount > 0) || alertVisible
        NSApp.setActivationPolicy(shouldShowDock ? .regular : .accessory)
    }
}
