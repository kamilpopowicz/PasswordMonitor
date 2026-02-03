//
//  MainAppIntegration.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 02/02/2026.
//


import SwiftUI
import Combine

/// Rozszerzenie głównego widoku aplikacji o obsługę powiadomień
/// Dodaj ten kod do Twojego głównego pliku (np. PasswordMonitorApp.swift lub ContentView.swift)
struct MainAppIntegration: ViewModifier {
    @StateObject private var passwordChecker = PasswordChecker()
    @State private var lastExpirationDate: Date?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Początkowe sprawdzenie przy starcie aplikacji
                checkPasswordAndUpdateNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // Sprawdź gdy aplikacja staje się aktywna (użytkownik kliknął w Dock)
                checkPasswordAndUpdateNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                // 🔥 KLUCZOWE: Sprawdź po wybudzeniu komputera ze snu
                // Jeśli komputer spał przez czas powiadomienia, pokaż je natychmiast
                print("💻 Komputer wybudzony - sprawdzam status hasła")
                checkPasswordAndUpdateNotification()
                
                // Wymuś dodatkowe sprawdzenie powiadomienia (na wypadek gdybyśmy przegapili godzinę)
                NotificationManager.shared.checkAndShowNotificationIfNeeded()
            }
            .onReceive(passwordChecker.$expirationDate) { newDate in
                // Gdy zmieni się data wygaśnięcia, aktualizuj NotificationManager
                if let date = newDate, date != lastExpirationDate {
                    lastExpirationDate = date
                    NotificationManager.shared.updateExpirationDate(date)
                    
                    // Sprawdź od razu czy nie powinniśmy pokazać powiadomienia
                    // (np. gdy hasło już wygasa lub wygasło podczas gdy aplikacja nie działała)
                    NotificationManager.shared.checkAndShowNotificationIfNeeded()
                }
            }
    }
    
    private func checkPasswordAndUpdateNotification() {
        // Wywołaj sprawdzenie hasła (asynchroniczne)
        Task {
            await passwordChecker.checkPasswordExpiration()
        }
    }
}

// MARK: - PasswordChecker (Twoja istniejąca logika)

/// Klasa zarządzająca sprawdzaniem daty wygaśnięcia hasła
/// To już masz w swoim kodzie - upewnij się że publikuje expirationDate
@MainActor
class PasswordChecker: ObservableObject {
    @Published var expirationDate: Date?
    @Published var isLoading = false
    @Published var error: Error?
    
    func checkPasswordExpiration() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let date = try await fetchPasswordExpirationFromSystem()
            self.expirationDate = date
            print("🔐 Data wygaśnięcia hasła: \(date?.formatted() ?? "brak")")
        } catch {
            self.error = error
            print("❌ Błąd sprawdzania hasła: \(error)")
        }
    }
    
    private func fetchPasswordExpirationFromSystem() async throws -> Date? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-read", "/Users/\(NSUserName())", "SMBPasswordLastSet"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                // ✅ POPRAWKA: Parsowanie na MainActor (bo klasa jest @MainActor)
                Task { @MainActor in
                    if let date = self.parseSMBPasswordDate(from: output) {
                        continuation.resume(returning: date)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// ✅ POPRAWKA: nonisolated bo to czysta funkcja (nie modyfikuje stanu klasy)
    nonisolated private func parseSMBPasswordDate(from output: String) -> Date? {
        // Szukaj linii: SMBPasswordLastSet: 134127638173381659
        guard let range = output.range(of: "SMBPasswordLastSet: ") else {
            return nil
        }
        
        let valueStart = range.upperBound
        let substring = output[valueStart...]
        
        // Pobierz liczbę (timestamp Windows)
        guard let timestampString = substring.split(separator: "\n").first,
              let timestamp = Double(timestampString) else {
            return nil
        }
        
        // Konwersja timestamp Windows (100-nanosekundy od 1601-01-01) na Date
        let windowsEpoch = Date(timeIntervalSince1970: -11644473600) // 1601-01-01 00:00:00 UTC
        let seconds = timestamp / 10_000_000 // Konwersja z 100ns na sekundy
        
        return windowsEpoch.addingTimeInterval(seconds)
    }
}
