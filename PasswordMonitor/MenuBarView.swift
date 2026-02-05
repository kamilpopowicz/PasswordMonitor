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
                
                // ostrzeżenie, jeśli dane są z cache (domena niedostępna)
                if info.isFromCache {
                    Text("Brak połączenia z domeną. Połącz się z VPN przed zmianą hasła.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

            if let info = passwordInfo, info.daysUntilExpiration <= 28 {
                Button("Zmień hasło") {
                    print("🔐 Użytkownik wybrał 'Zmień hasło'")
                    PasswordChangeHelper.openSystemPasswordSettings()
//                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/TouchID.prefPane"))
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

            // Link do ustawień
            SettingsLink {
                Text("Ustawienia...")
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
}

// Trzymasz to już w projekcie – zostawiam bez zmian
class AppState: ObservableObject {
    @Published var launchAtLogin = false
}
