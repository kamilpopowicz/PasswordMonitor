//
//  PasswordChangeHelper.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 04/02/2026.
//


import AppKit

/// Pomocnik do otwierania miejsca, gdzie użytkownik zmienia hasło.
/// Nie dotykamy samych haseł – tylko wywołujemy systemowy UI.
public enum PasswordChangeHelper {
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
}
