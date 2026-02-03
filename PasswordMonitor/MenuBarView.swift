//
//  MenuBarView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import SwiftUI
import ServiceManagement
import PasswordMonitorCore
import Combine

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var passwordInfo: PasswordInfo?
    @State private var isChecking = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            if let info = passwordInfo {
                Text("Hasło wygasa za:")
                    .font(.headline)
                Text("\(info.daysUntilExpiration) dni")
                    .font(.title2)
                    .foregroundColor(info.daysUntilExpiration <= 7 ? .red : .green)
                
                Divider()
                
                Text("Ostatnia zmiana:")
                    .font(.caption)
                Text(info.lastSetDate, style: .date)
                    .font(.caption)
            } else {
                Text("Sprawdź status hasła")
                    .font(.headline)
            }
            
            Divider()
            
            // Akcje
            Button("Sprawdź teraz") {
                checkPasswordNow()
            }
            .disabled(isChecking)
            
            if let info = passwordInfo, info.daysUntilExpiration <= 7 {
                Button("Zmień hasło") {
//                    NotificationManager().openPasswordSettings()
                }
            }
            
            Divider()
            
            // Helper service status
            HStack {
                Circle()
                    .fill(helperServiceColor)
                    .frame(width: 8, height: 8)
                Text("Background service")
                    .font(.caption)
            }
            
            // Use SettingsLink instead of the old openSettings()
            SettingsLink {Text("Ustawienia...")}
                .controlSize(.regular)
            
            Divider()
            
            Button("Test powiadomienia") {
                // Ustaw datę wygaśnięcia na teraz + 23h (urgent mode)
                let testDate = Date().addingTimeInterval(23 * 3600)
                NotificationManager.shared.updateExpirationDate(testDate)
                NotificationManager.shared.checkAndShowNotificationIfNeeded()
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            
            Divider()
            
            Button("Zamknij") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 250)
        .modifier(MainAppIntegration())
        .onAppear {
            checkPasswordNow()
        }
    }
    
    private var helperServiceColor: Color {
        let service = SMAppService.loginItem(identifier: "popo.PasswordMonitorHelperApp")
        return service.status == .enabled ? .green : .red
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
                    
                    // Pokaż alert jeśli trzeba
                    if manager.shouldShowWarning(passwordInfo: info) {
                        NotificationManager.shared.updateExpirationDate(info.expiryDate)
                        
                        // Sprawdź czy pokazać powiadomienie
                        NotificationManager.shared.checkAndShowNotificationIfNeeded()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isChecking = false
                    print("❌ Error: \(error)")
                }
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var launchAtLogin = false
}
