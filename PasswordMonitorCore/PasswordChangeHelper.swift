//
//  PasswordChangeHelper.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 04/02/2026.
//


import AppKit

/// Pomocnik do otwierania przepływu zmiany hasła z aplikacji lub login itema.
public enum PasswordChangeHelper {
    private static let mainAppBundleIdentifier = "popo.PasswordMonitor"
    private static let helperBundleIdentifier = "popo.PasswordMonitorHelperApp"

    public static func requestPasswordChange() {
        NotificationCenter.default.post(name: HelperMessaging.passwordChangeRequestedNotification, object: nil)
        postPasswordChangeRequest()
        openMainAppFromHelperIfNeeded {
            postPasswordChangeRequest()
        }
    }

    public static func openSystemPasswordSettings() {
        // macOS Ventura / Sonoma+: Touch ID & Password
        if let url = URL(string: "x-apple.systempreferences:com.apple.Touch-ID-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }

        // Legacy: panel Touch ID & Password (działa też wg list prefPane'ów) [web:82][web:92]
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.password"),
           NSWorkspace.shared.open(url) {
            return
        }

        // Starszy prefPane jako ostateczny fallback
        let touchIDPath = "/System/Library/PreferencePanes/TouchID.prefPane"
        if FileManager.default.fileExists(atPath: touchIDPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: touchIDPath))
        } else {
            // Gdyby nawet to nie zadziałało – otwórz ogólne System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preferences") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private static func postPasswordChangeRequest() {
        DistributedNotificationCenter.default().post(
            name: HelperMessaging.passwordChangeRequestedNotification,
            object: Bundle.main.bundleIdentifier
        )
    }

    private static func openMainAppFromHelperIfNeeded(onOpened: @escaping () -> Void) {
        guard Bundle.main.bundleIdentifier == helperBundleIdentifier else { return }

        if NSRunningApplication.runningApplications(withBundleIdentifier: mainAppBundleIdentifier).isEmpty == false {
            return
        }

        let mainAppURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        guard mainAppURL.pathExtension == "app" else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false

        NSWorkspace.shared.openApplication(at: mainAppURL, configuration: configuration) { _, error in
            if let error {
                Logger.shared.log(
                    "Nie udało się otworzyć głównej aplikacji do zmiany hasła: \(error.localizedDescription)",
                    level: .warning
                )
                return
            }

            onOpened()
        }
    }
}
