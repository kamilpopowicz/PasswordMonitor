//
//  SettingsView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import SwiftUI
import ServiceManagement

private enum SettingsKeys {
    static let domainName = "ad_domain"
    static let maxPasswordAge = "max_password_age"
    static let warningThreshold = "warning_threshold"
    static let notificationHour = "notification_hour" // Format: "09:00"
}

struct SettingsView: View {
    @State private var launchAtLogin = false
    
    // ✅ Istniejące ustawienia AD
    @AppStorage(SettingsKeys.domainName) private var domainName = "BP-ITAKA"
    @AppStorage(SettingsKeys.maxPasswordAge) private var maxPasswordAge = 30
    @AppStorage(SettingsKeys.warningThreshold) private var warningThreshold = 7
    
    // ✅ NOWE: Godzina powiadomienia (9:00 domyślnie)
    @AppStorage(SettingsKeys.notificationHour) private var notificationHourString = "09:00"
    @State private var notificationDate = Date() // Tymczasowy picker state
    
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var helperStatus: SMAppService.Status = .notFound
    
    private let helperBundleID = "popo.PasswordMonitorHelperApp"
    
    var body: some View {
        Form {
            Section(header: Text("Powiadomienia").font(.headline)) {
                // ✅ Picker godziny
                DatePicker(
                    "Godzina powiadomienia",
                    selection: $notificationDate,
                    displayedComponents: .hourAndMinute
                )
                .onAppear {
                    // Konwersja String "HH:mm" -> Date dla pickera
                    notificationDate = timeStringToDate(notificationHourString) ?? Date()
                }
                .onChange(of: notificationDate) { _, newValue in
                    // Konwersja Date -> String "HH:mm" dla @AppStorage
                    notificationHourString = dateToTimeString(newValue) ?? "09:00"
                    print("🕘 Godzina powiadomienia zmieniona na: \(notificationHourString)")
                }
                
                Text("Powiadomienie wyświetli się codziennie o ustalonej godzinie")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Startup").font(.headline)) {
                Toggle("Uruchom przy logowaniu", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }
                
                Text("Password Monitor (Helper service) będzie sprawdzał hasło codziennie o \(notificationHourString)")
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
                        .onChange(of: maxPasswordAge) { _, newValue in
                            if newValue < 1 { maxPasswordAge = 1 }
                            if newValue > 365 { maxPasswordAge = 365 }
                        }
                }
                
                HStack {
                    Text("Próg ostrzeżenia (dni)")
                    Spacer()
                    TextField("", value: $warningThreshold, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: warningThreshold) { _, newValue in
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
        .frame(width: 500, height: 450) // Zwiększona wysokość na nową sekcję
        .onAppear {
            loadSettings()
        }
        .alert("Helper Service", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Helpers
    
    private func timeStringToDate(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: timeString)
    }
    
    private func dateToTimeString(_ date: Date) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private var helperStatusColor: Color {
        switch helperStatus {
        case .enabled: return .green
        case .requiresApproval: return .orange
        case .notRegistered, .notFound: return .red
        @unknown default: return .gray
        }
    }
    
    private var helperStatusDescription: String {
        switch helperStatus {
        case .enabled: return "Aktywny"
        case .notRegistered: return "Nie zarejestrowany"
        case .requiresApproval: return "Wymaga zatwierdzenia"
        case .notFound: return "Nie znaleziono"
        @unknown default: return "Nieznany"
        }
    }
    
    private func loadSettings() {
        let service = SMAppService.loginItem(identifier: helperBundleID)
        helperStatus = service.status
        launchAtLogin = (service.status == .enabled)
        
        // Synchronizuj picker z zapisanym czasem
        notificationDate = timeStringToDate(notificationHourString) ?? Date()
        
        print("📊 Settings loaded - Notification time: \(notificationHourString)")
    }
    
    private func toggleLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.loginItem(identifier: helperBundleID)
        
        do {
            if enabled {
                try service.register()
                print("✅ Helper registered")
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
            launchAtLogin = !enabled
            helperStatus = service.status
        }
    }
}

#Preview {
    SettingsView()
}
