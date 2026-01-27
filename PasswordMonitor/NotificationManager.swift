//
//  NotificationManager.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//


import AppKit

class NotificationManager {
    private let stateFileURL: URL
    
    init() {
        // ~/.password_monitor_state
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        stateFileURL = homeDir.appendingPathComponent(".password_monitor_state")
    }
    
    /// Sprawdza czy dzisiaj już pokazano notyfikację
    func shouldShowTodayNotification() -> Bool {
        guard let lastShown = getLastNotificationDate() else {
            return true  // Nigdy nie pokazano
        }
        
        let calendar = Calendar.current
        return !calendar.isDateInToday(lastShown)
    }
    
    /// Zapisuje timestamp ostatniej notyfikacji
    func markNotificationShown() {
        let timestamp = String(Date().timeIntervalSince1970)
        try? timestamp.write(to: stateFileURL, atomically: true, encoding: .utf8)
    }
    
    private func getLastNotificationDate() -> Date? {
        guard let content = try? String(contentsOf: stateFileURL, encoding: .utf8),
              let timestamp = Double(content) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }
    
    /// Pokazuje dialog ostrzeżenia
    func showPasswordWarning(daysLeft: Int, expiryDate: Date) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Ostrzeżenie o wygaśnięciu hasła"
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "pl_PL")
        
        let expiryString = formatter.string(from: expiryDate)
        
        if daysLeft <= 0 {
            alert.informativeText = """
            Twoje hasło wygasło!
            Data wygaśnięcia: \(expiryString)
            
            Musisz zmienić hasło natychmiast.
            """
        } else {
            alert.informativeText = """
            Twoje hasło wygaśnie za \(daysLeft) dni.
            Data wygaśnięcia: \(expiryString)
            
            Zmień hasło jak najszybciej.
            """
        }
        
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Zmień hasło")
        alert.addButton(withTitle: "Przypomnij później")
        
        // Przywołaj app do foreground
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        let response = alert.runModal()
        
        // Wróć do accessory mode (menu bar only)
        NSApp.setActivationPolicy(.accessory)
        
        return response == .alertFirstButtonReturn  // True jeśli "Zmień hasło"
    }
    
    /// Otwiera System Settings do zmiany hasła
    func openPasswordSettings() {
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersion
        
        if macOSVersion.majorVersion >= 13 {
            // macOS Ventura+ → System Settings
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.password")!)
        } else {
            // Starsze macOS → System Preferences
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalUsers")!)
        }
    }
}
