//
//  PasswordMonitorApp 2.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//


import SwiftUI
import ServiceManagement

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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set jako accessory app (menu bar only)
        NSApp.setActivationPolicy(.accessory)
        
        // Zarejestruj helper service
        registerHelperService()
    }
    
    private func registerHelperService() {
        let service = SMAppService.agent(plistName: "com.company.PasswordMonitor.Helper.plist")
        
        do {
            if service.status == .notRegistered {
                try service.register()
                print("✅ Helper service registered")
            }
        } catch {
            print("❌ Failed to register helper: \(error)")
        }
    }
}
