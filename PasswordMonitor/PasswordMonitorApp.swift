//
//  PasswordMonitorApp 2.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import SwiftUI
import AppKit
import ServiceManagement
import PasswordMonitorCore
import Combine

enum AppIconImageProvider {
    static func image(size: CGFloat) -> NSImage {
        let candidates = [
            NSImage(named: NSImage.Name("AppIcon")),
            NSImage(named: NSImage.applicationIconName),
            NSApp.applicationIconImage
        ]

        guard let source = candidates.compactMap({ $0 }).first(where: { $0.isValid }) else {
            return NSImage(size: NSSize(width: size, height: size))
        }

        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let sourceSize = source.size
        let aspect = min(size / sourceSize.width, size / sourceSize.height)
        let drawSize = NSSize(width: sourceSize.width * aspect, height: sourceSize.height * aspect)
        let drawRect = NSRect(
            x: (size - drawSize.width) * PMLayout.centeringMultiplier,
            y: (size - drawSize.height) * PMLayout.centeringMultiplier,
            width: drawSize.width,
            height: drawSize.height
        )
        source.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: PMControlMetrics.visibleOpacity
        )
        image.unlockFocus()
        return image
    }
}

@main
struct PasswordMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var languageSettings = LanguageSettings()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var updateRequestCenter = UpdateRequestCenter()

    var body: some Scene {
        // Menu bar extra (macOS 13+)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(languageSettings)
                .environmentObject(updateRequestCenter)
                .environment(\.locale, languageSettings.locale)
                .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
                .pmThemeApplying(themeManager.isApplyingTheme)
        } label: {
            Image(nsImage: AppIconImageProvider.image(size: PMLayout.menuBarIconSize))
                .renderingMode(.original)
        }
        .menuBarExtraStyle(.window)

        Window(LanguageSettings.localizedString("settings_window_title", languageCode: languageSettings.selectedLanguageCode), id: "settings-window") {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(languageSettings)
                .environmentObject(updateRequestCenter)
                .environment(\.locale, languageSettings.locale)
                .pmWindowFixedSize()
                .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
                .pmWindowBackground(reduced: themeManager.isApplyingTheme)
                .pmThemeApplying(themeManager.isApplyingTheme)
        }
        .windowResizability(.contentSize)

        Window(LanguageSettings.localizedString("about_window_title", languageCode: languageSettings.selectedLanguageCode), id: "about-window") {
            AboutView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(languageSettings)
                .environmentObject(updateRequestCenter)
                .environment(\.locale, languageSettings.locale)
                .pmWindowFixedSize()
                .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
                .pmWindowBackground(reduced: themeManager.isApplyingTheme)
                .pmThemeApplying(themeManager.isApplyingTheme)
        }
        .windowResizability(.contentSize)

        Window(LanguageSettings.localizedString("logs_window_title", languageCode: languageSettings.selectedLanguageCode), id: "logs-window") {
            LogsView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(updateRequestCenter)
                .environment(\.locale, languageSettings.locale)
                .pmWindowFixedSize()
                .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
                .pmWindowBackground(reduced: themeManager.isApplyingTheme)
                .pmThemeApplying(themeManager.isApplyingTheme)
        }
        .windowResizability(.contentSize)

        Window(LanguageSettings.localizedString("ai_requirements_window_title", languageCode: languageSettings.selectedLanguageCode), id: "ai-check-window") {
            AIRequirementsView()
                .environmentObject(themeManager)
                .environmentObject(updateRequestCenter)
                .environment(\.locale, languageSettings.locale)
                .pmWindowFixedSize()
                .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
                .pmWindowBackground(reduced: themeManager.isApplyingTheme)
                .pmThemeApplying(themeManager.isApplyingTheme)
        }
        .windowResizability(.contentSize)
        
        // Skróty i menu
        .commands {
            AppCommands()
        }
    }
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var updateRequestCenter: UpdateRequestCenter
    
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(LanguageSettings.localizedString("settings_menu_title")) {
                openWindow(id: "settings-window")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button(LanguageSettings.localizedString("menu_logs")) {
                openWindow(id: "logs-window")
            }
            .keyboardShortcut("l", modifiers: .command)
        }

        CommandGroup(replacing: .appInfo) {
            Button(LanguageSettings.localizedString("menu_about")) {
                openWindow(id: "about-window")
            }

            Button(LanguageSettings.localizedString("settings_check_for_updates")) {
                updateRequestCenter.requestCheck()
                openWindow(id: "about-window")
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.logLocalized("log_app_launched")
        logLoadedSettingsSnapshot()

        LocalizationRetryManager.shared.handleAppLaunch()

        // Rejestracja helpera
        registerHelperService()

        DispatchQueue.main.asyncAfter(deadline: .now() + PMMotion.languagePromptDelay) {
            self.promptForSystemLanguageIfNeeded()
        }
        
    }

    private func promptForSystemLanguageIfNeeded() {
        let systemCode = Locale.current.language.languageCode?.identifier ?? "en"
        let current = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        guard systemCode != current else { return }

        let lastPrompted = UserDefaults.standard.string(forKey: "appLanguagePrompted")
        guard lastPrompted != systemCode else { return }

        let title = LanguageSettings.localizedString("language_prompt_title", languageCode: systemCode)
        let systemName = Locale.current.localizedString(forLanguageCode: systemCode) ?? systemCode
        let message = LanguageSettings.localizedString("language_prompt_message %@", languageCode: systemCode, systemName)
        let yesTitle = LanguageSettings.localizedString("language_prompt_accept", languageCode: systemCode)
        let noTitle = LanguageSettings.localizedString("language_prompt_decline", languageCode: systemCode)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: yesTitle)
        alert.addButton(withTitle: noTitle)

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        UserDefaults.standard.set(systemCode, forKey: "appLanguagePrompted")

        if response == .alertFirstButtonReturn {
            UserDefaults.standard.set(systemCode, forKey: "appLanguage")
            NotificationCenter.default.post(
                name: .appLanguageChanged,
                object: nil,
                userInfo: ["code": systemCode]
            )
        }
    }
    
    private func registerHelperService() {
        let helperBundleID = "popo.PasswordMonitorHelperApp"
        let service = SMAppService.loginItem(identifier: helperBundleID)

        // Debug info
        let bundleURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/PasswordMonitorHelperApp.app")

        defer { ensureHelperRunning(bundleURL: bundleURL, bundleID: helperBundleID) }
        
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
    
    
    private func logLoadedSettingsSnapshot() {
        let defaults = UserDefaults.standard
        let snapshot = [
            "max_password_age=\(defaults.integer(forKey: "max_password_age"))",
            "warning_threshold=\(defaults.integer(forKey: "warning_threshold"))",
            "notification_hour=\(defaults.string(forKey: "notification_hour") ?? "(default)")",
            "quiet_hours_start=\(defaults.string(forKey: "quiet_hours_start") ?? "(default)")",
            "quiet_hours_end=\(defaults.string(forKey: "quiet_hours_end") ?? "(default)")",
            "minimal_logging=\(defaults.object(forKey: "minimal_logging") as? Bool ?? true)",
            "appLanguage=\(defaults.string(forKey: "appLanguage") ?? "(default)")",
            "theme_mode=\(defaults.string(forKey: "theme_mode") ?? "(default)")"
        ]
        Logger.shared.log("Settings loaded at launch: \(snapshot.joined(separator: ", "))")
    }

    private func ensureHelperRunning(bundleURL: URL, bundleID: String) {
        let expectedHelperPath = bundleURL.standardizedFileURL.path
        let runningHelpers = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
        let staleHelpers = HelperProcessCleanup.staleHelpers(
            expectedBundlePath: expectedHelperPath,
            runningHelpers: runningHelpers.map {
                HelperProcessCleanup.RunningHelper(
                    processIdentifier: $0.processIdentifier,
                    bundlePath: $0.bundleURL?.path
                )
            }
        )
        let staleHelperPIDs = Set(staleHelpers.map(\.processIdentifier))

        for helper in runningHelpers {
            let helperPath = helper.bundleURL?.standardizedFileURL.path ?? "unknown"
            guard staleHelperPIDs.contains(helper.processIdentifier) else { continue }

            Logger.shared.log("Terminating stale helper process (pid=\(helper.processIdentifier), path=\(helperPath), expectedPath=\(expectedHelperPath))")
            if !helper.terminate() {
                helper.forceTerminate()
            }
        }

        if runningHelpers.contains(where: { !staleHelperPIDs.contains($0.processIdentifier) }) {
            Logger.shared.log("Helper process already running from current bundle (bundleID=\(bundleID), path=\(expectedHelperPath))")
            return
        }

        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            Logger.shared.log("Helper bundle missing at \(bundleURL.path); skipping launch")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.hides = true
        configuration.promptsUserIfNeeded = false

        Logger.shared.log("Launching helper process at \(bundleURL.path)")
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { app, error in
            if let error = error {
                Logger.shared.log("Helper launch failed: \(error.localizedDescription)", level: .error)
            } else if let app = app {
                Logger.shared.log("Helper launched (pid=\(app.processIdentifier))")
            } else {
                Logger.shared.log("Helper launch returned no app and no error")
            }
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
    
}
