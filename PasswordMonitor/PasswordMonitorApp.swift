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
    
    var body: some Scene {
        // Menu bar extra (macOS 13+)
        MenuBarExtra("Password Monitor", systemImage: "lock.shield") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
        
        // Settings window
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()
    private let passwordChecker = PasswordChecker()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 Aplikacja uruchomiona")
        
        // Początkowe sprawdzenie hasła
        Task {
            await passwordChecker.checkPasswordExpiration()
        }
        
        // Obserwuj zmiany daty wygaśnięcia
        passwordChecker.$expirationDate
            .receive(on: DispatchQueue.main)
            .sink { date in
                guard let date = date else { return }
                print("📅 Zaktualizowano datę wygaśnięcia: \(date)")
                
                // Aktualizuj NotificationManager
                NotificationManager.shared.updateExpirationDate(date)
                
                // Sprawdź czy pokazać powiadomienie
                NotificationManager.shared.checkAndShowNotificationIfNeeded()
            }
            .store(in: &cancellables)
        
        // Obserwuj wybudzenie komputera (KLUCZOWE)
        NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                print("💻 Wybudzenie systemu - sprawdzam powiadomienie")
                
                // Sprawdź ponownie hasło (na wypadek zmian w tle)
                Task { await self?.passwordChecker.checkPasswordExpiration() }
                
                // Wymuś sprawdzenie powiadomienia
                NotificationManager.shared.checkAndShowNotificationIfNeeded()
            }
            .store(in: &cancellables)
    }
    
    private func registerHelperService() {
        let helperBundleID = "popo.PasswordMonitorHelperApp"
        let service = SMAppService.loginItem(identifier: helperBundleID)
        
        // Debug info
        let bundleURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/PasswordMonitorHelperApp.app")
        
        print("Expected Bundle ID: \(helperBundleID)")
        print("Helper bundle path: \(bundleURL.path)")
        print("Exists: \(FileManager.default.fileExists(atPath: bundleURL.path))")
        print("Initial Service status: \(service.status.rawValue)")
        
        do {
            switch service.status {
            case .notRegistered:
                try service.register()
                print("✅ Helper service registered (was not registered)")
                
            case .enabled:
                print("✅ Helper service already enabled")
                
            case .requiresApproval:
                print("⚠️ Helper requires user approval in System Settings")
                showApprovalAlert()
                
            case .notFound:
                // 🎯 TO JEST KLUCZOWE: notFound = nigdy nie rejestrowany, więc rejestruj!
                print("ℹ️ Service not found in system database (never registered before)")
                print("Attempting registration...")
                
                try service.register()
                
                // Sprawdź status ponownie po rejestracji
                let newStatus = service.status
                print("Status after register: \(newStatus.rawValue)")
                
                if newStatus == .enabled {
                    print("✅ Helper service registered successfully")
                } else if newStatus == .requiresApproval {
                    print("⚠️ Registration requires user approval")
                    showApprovalAlert()
                } else {
                    print("⚠️ Unexpected status after registration: \(newStatus.rawValue)")
                }
                
            @unknown default:
                print("⚠️ Unknown status: \(service.status)")
            }
        } catch {
            print("❌ Failed to register helper: \(error.localizedDescription)")
            // Dodaj pełny opis błędu
            let nsError = error as NSError
            print("Error domain: \(nsError.domain), code: \(nsError.code)")
        }
    }
    
    
    private func showApprovalAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Wymagane pozwolenie"
            alert.informativeText = """
            Aby włączyć automatyczne sprawdzanie hasła, zatwierdź aplikację w:
            
            System Settings → General → Login Items → Allow in Background
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Otwórz Settings")
            alert.addButton(withTitle: "Później")
            
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
