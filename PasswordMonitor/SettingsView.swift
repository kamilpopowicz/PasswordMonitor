//
//  SettingsView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var launchAtLogin = false
    @State private var domainName = "BP-ITAKA"
    @State private var maxPasswordAge = 30
    @State private var warningThreshold = 7
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        Form {
            Section(header: Text("Startup").font(.headline)) {
                Toggle("Uruchom przy logowaniu", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }
                
                Text("Helper service będzie sprawdzał hasło codziennie o 9:00")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Active Directory").font(.headline)) {
                TextField("Nazwa domeny", text: $domainName)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Text("Maksymalny wiek hasła (dni)")
                    Spacer()
                    TextField("", value: $maxPasswordAge, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("Próg ostrzeżenia (dni)")
                    Spacer()
                    TextField("", value: $warningThreshold, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            Section(header: Text("Informacje").font(.headline)) {
                HStack {
                    Text("Wersja")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Status Helper Service")
                    Spacer()
                    Circle()
                        .fill(helperServiceColor)
                        .frame(width: 10, height: 10)
                    Text(helperServiceStatus)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 500, height: 400)
        .onAppear {
            loadSettings()
        }
        .alert("Helper Service", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    private var helperServiceColor: Color {
        let service = SMAppService.loginItem(identifier: "popo.PasswordMonitorHelperApp")
        return service.status == .enabled ? .green : .red
    }
    
    private var helperServiceStatus: String {
        let service = SMAppService.loginItem(identifier: "popo.PasswordMonitorHelperApp")
        switch service.status {
        case .enabled: return "Aktywny"
        case .notRegistered: return "Nie zarejestrowany"
        case .requiresApproval: return "Wymaga zatwierdzenia"
        case .notFound: return "Nie znaleziono"
        @unknown default: return "Nieznany"
        }
    }
    
    private func loadSettings() {
        let service = SMAppService.mainApp
        launchAtLogin = service.status == .enabled
        
        // TODO: Load z UserDefaults jeśli chcesz persystować ustawienia
        // domainName = UserDefaults.standard.string(forKey: "ad_domain") ?? "BP-ITAKA"
    }
    
    private func toggleLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        
        do {
            if enabled {
                if service.status == .requiresApproval {
                    // Wymaga user approval w System Settings
                    alertMessage = "Otwórz System Settings → Login Items i zatwierdź aplikację"
                    showAlert = true
                    return
                }
                try service.register()
                alertMessage = "Helper service aktywowany"
            } else {
                try service.unregister()
                alertMessage = "Helper service wyłączony"
            }
            showAlert = true
        } catch {
            alertMessage = "Błąd: \(error.localizedDescription)"
            showAlert = true
            launchAtLogin = !enabled  // Revert toggle
        }
    }
}

#Preview {
    SettingsView()
}

