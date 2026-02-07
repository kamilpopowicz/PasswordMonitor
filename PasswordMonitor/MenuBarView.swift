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
    @Environment(\.openWindow) private var openWindow

    @State private var passwordInfo: PasswordInfo?
    @State private var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            if let info = passwordInfo {
                Text("Password expires in:")
                    .font(.headline)

                Text("\(info.daysUntilExpiration) dni")
                    .font(.title2)
                    .foregroundColor(info.daysUntilExpiration <= 7 ? .red : .green)

                Divider()

                Text("Ostatnia zmiana:")
                    .font(.caption)

                Text(info.lastSetDate, style: .date)
                    .font(.caption)
                
                // ostrzeżenie, jeśli dane są z cache (domena niedostępna)
                if info.isFromCache {
                    Text("Brak połączenia z domeną. Połącz się z VPN przed zmianą hasła.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Check password status")
                    .font(.headline)
            }

            Divider()

            // Akcje
            Button("Check now") {
                checkPasswordNow()
            }
            .disabled(isChecking)

            Button("Change password") {
                print("🔐 Użytkownik wybrał 'Zmień hasło' z MenuBar")
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

                Text("Background service")
                    .font(.caption)
            }

            Button("Ustawienia...") {
                openWindow(id: "settings-window")
            }
            .controlSize(.regular)

            Divider()

            // Test powiadomienia (wywołuje NotificationManager z datą testową)
            Button("Test powiadomienia") {
                let testDate = Date().addingTimeInterval(23 * 3600)
                NotificationManager.shared.showTestNotification(expirationDate: testDate)
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

                    // Jeśli wg Twojej logiki trzeba ostrzec – przekaż datę do NotificationManager
                    if manager.shouldShowWarning(passwordInfo: info) {
                        NotificationManager.shared.updateExpirationDate(info.expiryDate)
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
    
    /// Czy przycisk „Zmień hasło” ma być aktywny
    private var canChangePasswordNow: Bool {
        guard let info = passwordInfo else { return false }
        // Zachowujemy dotychczasową logikę: aktywuj od 28 dni przed deadlinem
        return info.daysUntilExpiration <= 28
    }
}

// Trzymasz to już w projekcie – zostawiam bez zmian
class AppState: ObservableObject {
    @Published var launchAtLogin = false
}
