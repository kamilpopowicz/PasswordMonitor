//
//  SettingsView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import SwiftUI
import ServiceManagement

/// Klucze do UserDefaults — zdefiniowane jako stałe aby uniknąć literówek
private enum SettingsKeys {
    static let domainName = "ad_domain"
    static let maxPasswordAge = "max_password_age"
    static let warningThreshold = "warning_threshold"
}

struct SettingsView: View {
    /// ⚠️ launchAtLogin jest zarządzane przez SYSTEM (SMAppService), NIE UserDefaults!
    /// Pobieramy aktualny status z SMAppService przy każdym uruchomieniu
    @State private var launchAtLogin = false
    
    /// ✅ Te wartości są automatycznie zapisywane/wczytywane z UserDefaults przez @AppStorage
    @AppStorage(SettingsKeys.domainName) private var domainName = "BP-ITAKA"
    @AppStorage(SettingsKeys.maxPasswordAge) private var maxPasswordAge = 30
    @AppStorage(SettingsKeys.warningThreshold) private var warningThreshold = 7
    
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    /// Cache'ujemy status Helpera aby uniknąć wielokrotnych zapytań do systemu
    @State private var helperStatus: SMAppService.Status = .notFound
    
    /// Identyfikator Bundle Helpera
    private let helperBundleID = "popo.PasswordMonitorHelperApp"
    
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
                        // Ograniczamy wartość do sensownego zakresu
                        .onChange(of: maxPasswordAge) { oldValue, newValue in
                            if newValue < 1 { maxPasswordAge = 1 }
                            if newValue > 30 { maxPasswordAge = 30 }
                        }
                }
                
                HStack {
                    Text("Próg ostrzeżenia (dni)")
                    Spacer()
                    TextField("", value: $warningThreshold, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                        // Ostrzeżenie nie może być większe niż max wiek hasła
                        .onChange(of: warningThreshold) { oldValue, newValue in
                            if newValue < 1 { warningThreshold = 1 }
                            if newValue > maxPasswordAge {
                                warningThreshold = maxPasswordAge
                            }
                        }
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
                        .fill(helperStatusColor)
                        .frame(width: 10, height: 10)
                    Text(helperStatusDescription)
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
    
    /// Kolor wskaźnika statusu Helpera
    private var helperStatusColor: Color {
        switch helperStatus {
        case .enabled: return .green
        case .requiresApproval: return .orange
        case .notRegistered, .notFound: return .red
        @unknown default: return .gray
        }
    }
    
    /// Opis statusu Helpera po polsku
    private var helperStatusDescription: String {
        switch helperStatus {
        case .enabled: return "Aktywny"
        case .notRegistered: return "Nie zarejestrowany"
        case .requiresApproval: return "Wymaga zatwierdzenia"
        case .notFound: return "Nie znaleziono"
        @unknown default: return "Nieznany"
        }
    }
    
    /// Ładuje ustawienia przy otwarciu widoku
    /// launchAtLogin pobieramy z SMAppService (źródło prawdy), NIE z UserDefaults
    private func loadSettings() {
        let service = SMAppService.loginItem(identifier: helperBundleID)
        helperStatus = service.status
        launchAtLogin = (service.status == .enabled)
        
        print("📊 Settings loaded:")
        print("   - Domain: \(domainName)")
        print("   - Max Age: \(maxPasswordAge) days")
        print("   - Warning: \(warningThreshold) days")
        print("   - Launch at login: \(launchAtLogin)")
    }
    
    /// Włącza lub wyłącza uruchamianie Helpera przy logowaniu
    private func toggleLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.loginItem(identifier: helperBundleID)
        
        do {
            if enabled {
                try service.register()
                print("✅ Helper registered")
                
                // Aktualizuj status po rejestracji
                helperStatus = service.status
                
                if helperStatus == .requiresApproval {
                    alertMessage = "Otwórz System Settings → Ogólne → Elementy logowania i zatwierdź PasswordMonitorHelperApp"
                } else {
                    alertMessage = "Helper service aktywowany. Zostanie uruchomiony przy następnym logowaniu."
                }
            } else {
                try service.unregister()
                helperStatus = .notRegistered
                print("✅ Helper unregistered")
                alertMessage = "Helper service wyłączony"
            }
            showAlert = true
            
        } catch {
            print("❌ Błąd toggle: \(error.localizedDescription)")
            alertMessage = "Błąd: \(error.localizedDescription)"
            showAlert = true
            launchAtLogin = !enabled // Revert
            helperStatus = service.status
        }
    }
}

#Preview {
    SettingsView()
}
