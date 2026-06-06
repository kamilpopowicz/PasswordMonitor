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
import UserNotifications

enum AppWindowID {
    static let settings = "settings-window"
    static let about = "about-window"
    static let logs = "logs-window"
    static let aiRequirements = "ai-check-window"
    static let passwordChange = "password-change-window"

    static let standard: Set<String> = [
        settings,
        about,
        logs,
        aiRequirements
    ]

    static let managed = standard.union([passwordChange])
}

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
                .updateStatusOverlay()
        } label: {
            Image(nsImage: AppIconImageProvider.image(size: PMLayout.menuBarIconSize))
                .renderingMode(.original)
                .onAppear {
                    appDelegate.configure(
                        appState: appState,
                        languageSettings: languageSettings,
                        themeManager: themeManager,
                        updateRequestCenter: updateRequestCenter
                    )
                }
        }
        .menuBarExtraStyle(.window)

        Window(LanguageSettings.localizedString("settings_window_title", languageCode: languageSettings.selectedLanguageCode), id: AppWindowID.settings) {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(languageSettings)
                .environmentObject(updateRequestCenter)
                .environment(\.locale, languageSettings.locale)
                .pmWindowMinSize()
                .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
                .pmWindowBackground(reduced: themeManager.isApplyingTheme)
                .pmThemeApplying(themeManager.isApplyingTheme)
                .background(AppWindowLifecycleBridge(id: AppWindowID.settings, appState: appState))
                .updateStatusOverlay()
        }
        .windowResizability(.automatic)

        Window(LanguageSettings.localizedString("about_window_title", languageCode: languageSettings.selectedLanguageCode), id: AppWindowID.about) {
            AboutView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(languageSettings)
                .environmentObject(updateRequestCenter)
                .environment(\.locale, languageSettings.locale)
                .pmWindowMinSize()
                .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
                .pmWindowBackground(reduced: themeManager.isApplyingTheme)
                .pmThemeApplying(themeManager.isApplyingTheme)
                .background(AppWindowLifecycleBridge(id: AppWindowID.about, appState: appState))
                .updateStatusOverlay(allowsCriticalInteraction: true)
        }
        .windowResizability(.automatic)

        Window(LanguageSettings.localizedString("logs_window_title", languageCode: languageSettings.selectedLanguageCode), id: AppWindowID.logs) {
            LogsView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(updateRequestCenter)
                .environment(\.locale, languageSettings.locale)
                .pmWindowMinSize()
                .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
                .pmWindowBackground(reduced: themeManager.isApplyingTheme)
                .pmThemeApplying(themeManager.isApplyingTheme)
                .background(AppWindowLifecycleBridge(id: AppWindowID.logs, appState: appState))
                .updateStatusOverlay()
        }
        .windowResizability(.automatic)

        Window(LanguageSettings.localizedString("ai_requirements_window_title", languageCode: languageSettings.selectedLanguageCode), id: AppWindowID.aiRequirements) {
            AIRequirementsView()
                .environmentObject(themeManager)
                .environmentObject(updateRequestCenter)
                .environment(\.locale, languageSettings.locale)
                .pmWindowMinSize()
                .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
                .pmWindowBackground(reduced: themeManager.isApplyingTheme)
                .pmThemeApplying(themeManager.isApplyingTheme)
                .background(AppWindowLifecycleBridge(id: AppWindowID.aiRequirements, appState: appState))
                .updateStatusOverlay()
        }
        .windowResizability(.automatic)
        
        // Skróty i menu
        .commands {
            AppCommands(
                appState: appState,
                updateRequestCenter: updateRequestCenter
            )
        }
    }
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let appState: AppState
    let updateRequestCenter: UpdateRequestCenter
    
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(LanguageSettings.localizedString("settings_menu_title")) {
                presentWindow(id: AppWindowID.settings)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button(LanguageSettings.localizedString("menu_logs")) {
                presentWindow(id: AppWindowID.logs)
            }
            .keyboardShortcut("l", modifiers: .command)
        }

        CommandGroup(replacing: .appInfo) {
            Button(LanguageSettings.localizedString("menu_about")) {
                presentWindow(id: AppWindowID.about)
            }

            Button(LanguageSettings.localizedString("settings_check_for_updates")) {
                updateRequestCenter.requestCheck()
                presentWindow(id: AppWindowID.about)
            }
        }
    }

    private func presentWindow(id: String) {
        openWindow(id: id)
        appState.presentWindow(id: id)
    }
}

private struct AppWindowLifecycleBridge: NSViewRepresentable {
    let id: String
    let appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(id: id, appState: appState)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        attach(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        attach(nsView, coordinator: context.coordinator)
    }

    private func attach(_ view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            coordinator.attach(to: window)
        }
    }

    @MainActor
    final class Coordinator {
        private let id: String
        private weak var appState: AppState?
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(id: String, appState: AppState) {
            self.id = id
            self.appState = appState
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            self.window = window

            window.identifier = NSUserInterfaceItemIdentifier(id)
            window.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])

            observe(NSWindow.didDeminiaturizeNotification, for: window) { [weak self, weak window] in
                guard let self, let window else { return }
                self.appState?.windowBecameVisible(window, id: self.id)
            }
            observe(NSWindow.didBecomeKeyNotification, for: window) { [weak self] in
                self?.appState?.windowStateChanged()
            }
            observe(NSWindow.didMiniaturizeNotification, for: window) { [weak self] in
                self?.appState?.windowStateChanged()
            }
            observe(NSWindow.willCloseNotification, for: window) { [weak self] in
                guard let self else { return }
                self.appState?.windowWillClose(window, id: self.id)
            }

            appState?.registerWindow(window, id: id)
        }

        private func observe(
            _ name: Notification.Name,
            for window: NSWindow,
            handler: @escaping @MainActor () -> Void
        ) {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    handler()
                }
            }
            observers.append(observer)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let passwordChangeWindowIdentifier = NSUserInterfaceItemIdentifier(AppWindowID.passwordChange)
    private var passwordChangeWindow: NSWindow?
    private var manualAboutWindow: NSWindow?
    private var passwordChangeLocalObserver: NSObjectProtocol?
    private var passwordChangeDistributedObserver: NSObjectProtocol?
    private var appState: AppState?
    private var languageSettings: LanguageSettings?
    private var themeManager: ThemeManager?
    private var updateRequestCenter: UpdateRequestCenter?

    @MainActor
    func configure(
        appState: AppState,
        languageSettings: LanguageSettings,
        themeManager: ThemeManager,
        updateRequestCenter: UpdateRequestCenter
    ) {
        self.appState = appState
        self.languageSettings = languageSettings
        self.themeManager = themeManager
        self.updateRequestCenter = updateRequestCenter
        consumePendingUpdateInstallRequestIfPossible()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.logLocalized("log_app_launched")
        logLoadedSettingsSnapshot()

        PMUpdateSystemNotifier.shared.configureCategories()
        UNUserNotificationCenter.current().delegate = self

        LocalizationRetryManager.shared.handleAppLaunch()
        registerPasswordChangeRequestObservers()

        // Rejestracja helpera
        registerHelperService()

        DispatchQueue.main.asyncAfter(deadline: .now() + PMMotion.languagePromptDelay) {
            self.promptForSystemLanguageIfNeeded()
        }

        Task { @MainActor in
            await PMUpdateMonitor.shared.checkIfNeeded(
                currentVersion: self.currentAppVersion,
                trigger: .launch
            )
        }
        
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let passwordChangeLocalObserver {
            NotificationCenter.default.removeObserver(passwordChangeLocalObserver)
        }
        if let passwordChangeDistributedObserver {
            DistributedNotificationCenter.default().removeObserver(passwordChangeDistributedObserver)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + PMMotion.windowFocusRetryDelay) {
            self.hideDockWhenNoAppWindowIsOpen()
        }
        Task { @MainActor in
            await PMUpdateMonitor.shared.checkIfNeeded(
                currentVersion: self.currentAppVersion,
                trigger: .activation
            )
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if hasOpenAppWindow {
            return true
        }

        hideDockWhenNoAppWindowIsOpen()
        return false
    }

    private var hasOpenAppWindow: Bool {
        NSApp.windows.contains { window in
            guard let id = window.identifier?.rawValue,
                  AppWindowID.managed.contains(id) else {
                return false
            }
            return window.isVisible || window.isMiniaturized
        }
    }

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func hideDockWhenNoAppWindowIsOpen() {
        guard NSApp.modalWindow == nil else { return }
        guard !hasOpenAppWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    private func registerPasswordChangeRequestObservers() {
        passwordChangeLocalObserver = NotificationCenter.default.addObserver(
            forName: HelperMessaging.passwordChangeRequestedNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.presentPasswordChangeWindow()
            }
        }

        passwordChangeDistributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: HelperMessaging.passwordChangeRequestedNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.presentPasswordChangeWindow()
            }
        }
    }

    @MainActor
    private func presentPasswordChangeWindow() {
        guard !PMUpdateMonitor.shared.state.isCriticalBlocking else {
            presentAboutWindowForUpdate()
            return
        }

        if let passwordChangeWindow {
            focusPasswordChangeWindow(passwordChangeWindow, remainingAttempts: PMLayout.windowFocusRetryCount)
            return
        }

        let content = PasswordChangeView(
            onCancel: { [weak self] in
                self?.closePasswordChangeWindow()
            }
        )
        .updateStatusOverlay(
            startUpdateFlow: { [weak self] in
                self?.presentAboutWindowForUpdate()
            }
        )
        .pmWindowBackground()
        .preferredColorScheme(PMTheme.preferredColorSchemeFromDefaults)
        .frame(
            width: PMLayout.passwordChangeWindowWidth,
            height: PMLayout.passwordChangeWindowHeight
        )

        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: PMLayout.passwordChangeWindowWidth,
                    height: PMLayout.passwordChangeWindowHeight
                )
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = PasswordChangeCopy.windowTitle
        window.identifier = passwordChangeWindowIdentifier
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .floating
        window.contentViewController = hostingController
        window.minSize = NSSize(
            width: PMLayout.passwordChangeWindowMinWidth,
            height: PMLayout.passwordChangeWindowMinHeight
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        passwordChangeWindow = window
        focusPasswordChangeWindow(window, remainingAttempts: PMLayout.windowFocusRetryCount)
    }

    @MainActor
    private func focusPasswordChangeWindow(_ window: NSWindow, remainingAttempts: Int) {
        guard remainingAttempts > 0 else { return }

        NSApp.setActivationPolicy(.regular)
        window.level = .floating
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        guard !NSApp.isActive || !window.isKeyWindow else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + PMMotion.windowFocusRetryDelay) { [weak self, weak window] in
            guard let self, let window else { return }
            Task { @MainActor in
                self.focusPasswordChangeWindow(window, remainingAttempts: remainingAttempts - 1)
            }
        }
    }

    @MainActor
    private func closePasswordChangeWindow() {
        passwordChangeWindow?.close()
        passwordChangeWindow = nil
        hideDockWhenNoAppWindowIsOpen()
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === passwordChangeWindow {
            passwordChangeWindow = nil
        }
        if notification.object as? NSWindow === manualAboutWindow {
            manualAboutWindow = nil
        }
        hideDockWhenNoAppWindowIsOpen()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard notification.object as? NSWindow === passwordChangeWindow else { return }
        passwordChangeWindow?.level = .normal
    }

    @MainActor
    private func consumePendingUpdateInstallRequestIfPossible() {
        guard PMUpdateMonitor.shared.consumePendingInstallRequest() else { return }
        presentAboutWindowForUpdate()
    }

    @MainActor
    private func presentAboutWindowForUpdate() {
        if PMUpdateMonitor.shared.state.urgency == .critical {
            updateRequestCenter?.requestCriticalUpdate()
        } else {
            updateRequestCenter?.requestStartDetectedUpdate()
        }
        presentAboutWindow()
    }

    @MainActor
    private func presentAboutWindow() {
        if let window = existingWindow(id: AppWindowID.about) {
            appState?.presentWindow(id: AppWindowID.about)
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let appState, let languageSettings, let themeManager, let updateRequestCenter else {
            PMUpdateMonitor.shared.setPendingInstallRequest()
            return
        }

        let content = AboutView()
            .environmentObject(appState)
            .environmentObject(themeManager)
            .environmentObject(languageSettings)
            .environmentObject(updateRequestCenter)
            .environment(\.locale, languageSettings.locale)
            .pmWindowMinSize()
            .pmThemeTransitionOverlay(isActive: themeManager.isApplyingTheme)
            .pmWindowBackground(reduced: themeManager.isApplyingTheme)
            .pmThemeApplying(themeManager.isApplyingTheme)
            .updateStatusOverlay(
                allowsCriticalInteraction: true,
                startUpdateFlow: { [weak self] in
                    self?.presentAboutWindowForUpdate()
                }
            )
            .background(AppWindowLifecycleBridge(id: AppWindowID.about, appState: appState))

        let window = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: PMLayout.windowMinWidth, height: PMLayout.windowMinHeight)
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = LanguageSettings.localizedString("about_window_title")
        window.identifier = NSUserInterfaceItemIdentifier(AppWindowID.about)
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentViewController = NSHostingController(rootView: content)
        window.minSize = NSSize(width: PMLayout.windowMinWidth, height: PMLayout.windowMinHeight)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        manualAboutWindow = window
        appState.registerWindow(window, id: AppWindowID.about)
        appState.presentWindow(id: AppWindowID.about)
    }

    private func existingWindow(id: String) -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == id }
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

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.content.categoryIdentifier == PMUpdateSystemNotifier.categoryIdentifier else {
            return
        }
        await MainActor.run {
            PMUpdateMonitor.shared.setPendingInstallRequest()
            NotificationCenter.default.post(name: HelperMessaging.updateInstallRequestedNotification, object: nil)
            self.consumePendingUpdateInstallRequestIfPossible()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.content.categoryIdentifier == PMUpdateSystemNotifier.categoryIdentifier else {
            return []
        }
        return [.banner, .sound, .list]
    }
}
