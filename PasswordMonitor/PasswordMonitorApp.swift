//
//  PasswordMonitorApp 2.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import SwiftUI
import ServiceManagement
import PasswordMonitorCore
import Combine

@main
struct PasswordMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var languageSettings = LanguageSettings()
    @StateObject private var themeManager = ThemeManager()

    private var menuBarIconImage: NSImage {
        let targetSize = NSSize(width: 18, height: 18)
        guard let source = NSApp.applicationIconImage else {
            return NSImage(size: targetSize)
        }

        let image = NSImage(size: targetSize)
        image.lockFocus()
        let sourceSize = source.size
        let aspect = min(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
        let drawSize = NSSize(width: sourceSize.width * aspect, height: sourceSize.height * aspect)
        let drawRect = NSRect(
            x: (targetSize.width - drawSize.width) * 0.5,
            y: (targetSize.height - drawSize.height) * 0.5,
            width: drawSize.width,
            height: drawSize.height
        )
        source.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        image.unlockFocus()
        return image
    }

    var body: some Scene {
        // Menu bar extra (macOS 13+)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.locale)
                .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
                .pmWindowBackground(reduced: themeManager.isApplyingTheme)
                .pmThemeApplying(themeManager.isApplyingTheme)
        } label: {
            Image(nsImage: menuBarIconImage)
        }
        .menuBarExtraStyle(.window)

        Window("settings_window_title", id: "settings-window") {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.locale)
                .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
                .pmWindowBackground(reduced: themeManager.isApplyingTheme)
                .pmThemeApplying(themeManager.isApplyingTheme)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .pmWindowPanel()
                .pmWindowMinSize()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: PMLayout.windowMinWidth, height: PMLayout.windowMinHeight)

        Window("logs_window_title", id: "logs-window") {
            LogsView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environment(\.locale, languageSettings.locale)
                .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
                .pmWindowBackground(reduced: themeManager.isApplyingTheme)
                .pmThemeApplying(themeManager.isApplyingTheme)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .pmWindowPanel()
                .pmWindowMinSize()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: PMLayout.windowMinWidth, height: PMLayout.windowMinHeight)
        
        // Skróty i menu
        .commands {
            AppCommands()
        }
    }
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("settings_menu_title") {
                openWindow(id: "settings-window")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("menu_logs") {
                openWindow(id: "logs-window")
            }
            .keyboardShortcut("l", modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var wakeObserver: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.logLocalized("log_app_launched")
        
        // Rejestracja helpera
        registerHelperService()
        
        // Obserwacja NSWorkspace.didWakeNotification, która po wybudzeniu systemu wywoła sprawdzenie
        wakeObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Logger.shared.logLocalized("log_system_wake_check")
            
            Task { @MainActor in
                NotificationManager.shared.checkAndShowNotificationIfNeeded()
            }
        }
        
        // Natychmiastowe sprawdzenie ważności hasła po starcie
        runInitialPasswordCheck()
    }
    
    private func registerHelperService() {
        let helperBundleID = "popo.PasswordMonitorHelperApp"
        let service = SMAppService.loginItem(identifier: helperBundleID)
        
        // Debug info
        let bundleURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/PasswordMonitorHelperApp.app")
        
        Logger.shared.logLocalized("log_helper_expected_bundle_id %@", helperBundleID)
        Logger.shared.logLocalized("log_helper_bundle_path %@", bundleURL.path)
        Logger.shared.logLocalized("log_helper_bundle_exists %@", String(FileManager.default.fileExists(atPath: bundleURL.path)))
        Logger.shared.logLocalized("log_helper_initial_status %@", String(service.status.rawValue))
        
        do {
            switch service.status {
            case .notRegistered:
                try service.register()
                Logger.shared.logLocalized("log_helper_registered_not_registered")
                
            case .enabled:
                Logger.shared.logLocalized("log_helper_already_enabled")
                
            case .requiresApproval:
                Logger.shared.logLocalized("log_helper_requires_approval")
                showApprovalAlert()
                
            case .notFound:
                // 🎯 TO JEST KLUCZOWE: notFound = nigdy nie rejestrowany, więc rejestruj!
                Logger.shared.logLocalized("log_helper_not_found")
                Logger.shared.logLocalized("log_helper_attempting_registration")
                
                try service.register()
                
                // Sprawdź status ponownie po rejestracji
                let newStatus = service.status
                Logger.shared.logLocalized("log_helper_status_after_register %@", String(newStatus.rawValue))
                
                if newStatus == .enabled {
                    Logger.shared.logLocalized("log_helper_registered_successfully")
                } else if newStatus == .requiresApproval {
                    Logger.shared.logLocalized("log_helper_registration_requires_approval")
                    showApprovalAlert()
                } else {
                    Logger.shared.logLocalized("log_helper_unexpected_status_after_register %@", String(newStatus.rawValue))
                }
                
            @unknown default:
                Logger.shared.logLocalized("log_helper_unknown_status %@", String(describing: service.status))
            }
        } catch {
            Logger.shared.logLocalized("log_helper_register_failed %@", error.localizedDescription)
            // Dodaj pełny opis błędu
            let nsError = error as NSError
            Logger.shared.logLocalized("log_helper_register_error_domain %@ %ld", nsError.domain, nsError.code)
        }
    }
    
    
    private func showApprovalAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = LanguageSettings.localizedString("permission_required_title")
            alert.informativeText = LanguageSettings.localizedString("permission_required_message")
            alert.alertStyle = .informational
            alert.addButton(withTitle: LanguageSettings.localizedString("open_settings_button"))
            alert.addButton(withTitle: LanguageSettings.localizedString("later_button"))
            
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
            let response = alert.runModal()
            NSApp.setActivationPolicy(.accessory)
            
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
            }
        }
    }
    
    private func runInitialPasswordCheck() {
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = ActiveDirectoryManager()
            let username = NSUserName()
            
            do {
                let info = try manager.getPasswordInfo(for: username)
                
                DispatchQueue.main.async {
                    // Log informacyjny
                    Logger.shared.logLocalized("log_init_password_expiry %@ %@", String(info.daysUntilExpiration), String(describing: info.expiryDate))
                    
                    // Jeśli wg Twojej logiki trzeba ostrzec – przekaż datę do NotificationManager
                    if manager.shouldShowWarning(passwordInfo: info) {
                        NotificationManager.shared.updateExpirationDate(info.expiryDate)
                        NotificationManager.shared.checkAndShowNotificationIfNeeded()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    Logger.shared.logLocalized("log_init_password_check_error %@", String(describing: error))
                }
            }
        }
    }
    
}
