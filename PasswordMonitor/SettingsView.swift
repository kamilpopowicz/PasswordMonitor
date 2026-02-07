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
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageSettings.self) private var languageSettings

    // EDYTOWANE wartości (UI)
    @State private var launchAtLogin = false
    @State private var domainName = ""
    @State private var maxPasswordAge = 30
    @State private var warningThreshold = 7

    // Godzina w UI
    @State private var notificationHourString = "09:00"
    @State private var notificationDate = Date()

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var helperStatus: SMAppService.Status = .notFound

    private let helperBundleID = "popo.PasswordMonitorHelperApp"

    // ZAPISANE wartości (AppStorage)
    @AppStorage(SettingsKeys.domainName) private var storedDomainName = "BP-ITAKA"
    @AppStorage(SettingsKeys.maxPasswordAge) private var storedMaxPasswordAge = 30
    @AppStorage(SettingsKeys.warningThreshold) private var storedWarningThreshold = 7
    @AppStorage(SettingsKeys.notificationHour) private var storedNotificationHour = "09:00"

    var body: some View {
        VStack(spacing: 0) {
            // Główna zawartość ustawień
            ScrollView {
                Form {
                    // MARK: Powiadomienia
                    Section(header: Text("Powiadomienia").font(.headline)) {
                        DatePicker(
                            "Godzina powiadomienia",
                            selection: $notificationDate,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: notificationDate) { _, newValue in
                            // Konwersja Date -> String "HH:mm" dla EDYTOWANEJ wartości
                            notificationHourString = dateToTimeString(newValue) ?? "09:00"
                            print("🕘 Godzina powiadomienia zmieniona na: \(notificationHourString)")
                        }

                        Text("Powiadomienie wyświetli się codziennie o ustalonej godzinie")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // MARK: Startup
                    Section(header: Text("Startup").font(.headline)) {
                        Toggle("Uruchom przy logowaniu", isOn: $launchAtLogin)

                        Text("Password Monitor (Helper service) będzie sprawdzał hasło codziennie o \(notificationHourString)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // MARK: Active Directory
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

                    // MARK: Język / Language
                    Section(header: Text("language_settings_title").font(.headline)) {
                        // Create local Bindable for @Observable binding
                        @Bindable var settings = languageSettings

                        Picker("Language", selection: $settings.selectedLanguage) {
                            ForEach(LanguageSettings.AppLanguage.allCases) { language in
                                Text(language.displayName)
                                    .tag(language)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("language_change_footnote")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // MARK: Informacje
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
            }

            // Dolny pasek przycisków
            HStack {
                Spacer()
                Button("Anuluj") {
                    cancelChanges()
                }
                Button("Zapisz") {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isDirty)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear {
            loadSettings()
        }
        .alert("Helper Service", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    /// Czy wartości edytowane różnią się od zapisanych
    private var isDirty: Bool {
        let savedLaunchAtLogin = (helperStatus == .enabled)
        return domainName != storedDomainName
            || maxPasswordAge != storedMaxPasswordAge
            || warningThreshold != storedWarningThreshold
            || notificationHourString != storedNotificationHour
            || launchAtLogin != savedLaunchAtLogin
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
        // AppStorage -> edytowane wartości
        domainName = storedDomainName
        maxPasswordAge = storedMaxPasswordAge
        warningThreshold = storedWarningThreshold
        notificationHourString = storedNotificationHour
        notificationDate = timeStringToDate(notificationHourString) ?? Date()

        // Helper service status
        let service = SMAppService.loginItem(identifier: helperBundleID)
        helperStatus = service.status
        launchAtLogin = (service.status == .enabled)

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

    /// Zapisuje wprowadzone zmiany do AppStorage i helpera
    private func saveChanges() {
        // Zapisz do AppStorage
        storedDomainName = domainName
        storedMaxPasswordAge = maxPasswordAge
        storedWarningThreshold = warningThreshold
        storedNotificationHour = notificationHourString

        // Zastosuj stan helpera
        toggleLaunchAtLogin(launchAtLogin)

        // Ponownie wczytaj, żeby zsynchronizować helperStatus i wyzerować "dirty"
        loadSettings()
    }

    /// Odrzuca zmiany i przywraca stan zapisany
    private func cancelChanges() {
        loadSettings()
        dismiss()
    }
}

#Preview {
    SettingsView()
}
