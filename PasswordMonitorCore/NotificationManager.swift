//
//  NotificationManager.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//


import Foundation
import Combine
import AppKit

/// Zarządza powiadomieniami o wygaśnięciu hasła
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    // MARK: - State
    
    /// Czy w danym dniu już pokazaliśmy powiadomienie (reset o północy)
    @Published private var hasShownNotificationToday = false
    
    /// Czy powiadomienie jest obecnie w trybie snooze (odłożone)
    @Published private var isSnoozed = false
    @Published private var snoozeEndTime: Date?
    
    /// Aktualne okienko powiadomienia (jeśli widoczne)
    private var currentAlert: PasswordExpirationAlert?
    
    /// Timer do resetu o północy
    private var midnightTimer: Timer?
    
    /// Timer do sprawdzania czy nadszedł czas powiadomienia
    private var checkTimer: Timer?
    
    /// Data wygaśnięcia hasła (ustawiana z zewnątrz przez MainApp)
    private var currentExpirationDate: Date?
    
    // MARK: - Initialization
    
    private init() {
        setupMidnightReset()
        startCheckingForNotificationTime()
    }
    
    // MARK: - Public API
    
    /// Aktualizuje datę wygaśnięcia hasła (wywoływane gdy zmieni się status hasła)
    func updateExpirationDate(_ date: Date?) {
        currentExpirationDate = date
        print("📅 NotificationManager: Data wygaśnięcia zaktualizowana na \(date?.formatted() ?? "nil")")
    }
    
    /// Sprawdza czy powinniśmy pokazać powiadomienie (wywoływane cyklicznie)
    func checkAndShowNotificationIfNeeded() {
        guard let expirationDate = currentExpirationDate else {
            print("⏭️ Brak daty wygaśnięcia hasła")
            return
        }
        
        guard !hasShownNotificationToday else {
            print("⏭️ Powiadomienie już dziś pokazane")
            return
        }
        
        guard !isSnoozed || hasSnoozeExpired() else {
            print("⏭️ W trybie snooze do \(snoozeEndTime?.formatted() ?? "unknown")")
            return
        }
        
        let notificationTime = getNotificationTime()
        let now = Date()
        
        // Czy nadszedł czas powiadomienia (lub minął i komputer był uśpiony)?
        if now >= notificationTime {
            print("🔔 Czas powiadomienia! Wygaśnięcie: \(expirationDate)")
            showNotification(passwordExpirationDate: expirationDate)
        } else {
            let diff = notificationTime.timeIntervalSince(now)
            print("⏰ Do powiadomienia pozostało \(Int(diff / 60)) minut")
        }
    }
    
    /// Odłóż powiadomienie o 3 godziny
    func snooze(passwordExpirationDate: Date) {
        let hoursToExpiration = passwordExpirationDate.timeIntervalSinceNow / 3600
        
        // Nie można odłożyć jeśli hasło wygasa za < 24h
        guard hoursToExpiration > 24 else {
            print("🚫 Nie można odłożyć - hasło wygasa za \(Int(hoursToExpiration))h (< 24h)")
            return
        }
        
        isSnoozed = true
        snoozeEndTime = Date().addingTimeInterval(3 * 3600) // +3h
        hasShownNotificationToday = false // Pozwól pokazać ponownie po snooze
        
        // Schowaj aktualne okienko
        currentAlert?.close()
        currentAlert = nil
        
        print("😴 Snooze aktywowany do \(snoozeEndTime!.formatted())")
    }
    
    /// Ręczne zamknięcie powiadomienia (np. po kliknięciu "Zmień hasło")
    func dismissNotification() {
        currentAlert?.close()
        currentAlert = nil
        print("✅ Powiadomienie zamknięte przez użytkownika")
    }
    
    // MARK: - Private Methods
    
    /// Zwraca dzisiejszą datę z godziną z ustawień
    private func getNotificationTime() -> Date {
        let defaults = UserDefaults.standard
        let timeString = defaults.string(forKey: "notification_hour") ?? "09:00"
        
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        
        let timeParts = timeString.split(separator: ":")
        components.hour = Int(timeParts[0]) ?? 9
        components.minute = Int(timeParts[1]) ?? 0
        components.second = 0
        
        return calendar.date(from: components) ?? Date()
    }
    
    /// Sprawdza czy snooze się skończył
    private func hasSnoozeExpired() -> Bool {
        guard let endTime = snoozeEndTime else { return true }
        return Date() >= endTime
    }
    
    /// Pokazuje okienko powiadomienia
    private func showNotification(passwordExpirationDate: Date) {
        guard currentAlert == nil else {
            print("⚠️ Okienko już otwarte")
            return
        }
        
        hasShownNotificationToday = true
        
        let alert = PasswordExpirationAlert(
            expirationDate: passwordExpirationDate,
            onSnooze: { [weak self] in
                guard let self = self else { return }
                self.snooze(passwordExpirationDate: passwordExpirationDate)
            },
            onChangePassword: { [weak self] in
                print("🔐 Użytkownik wybrał 'Zmień hasło'")
                // TODO: Otwórz panel zmiany hasła systemowego
                // NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Accounts.prefPane"))
                self?.dismissNotification()
            }
        )
        
        currentAlert = alert
        alert.show()
    }
    
    /// Ustawia timer resetujący flagę o północy
    private func setupMidnightReset() {
        let calendar = Calendar.current
        let now = Date()
        
        // Następna północ
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.day! += 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        
        guard let midnight = calendar.date(from: components) else { return }
        let interval = midnight.timeIntervalSince(now)
        
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        print("🌙 Następny reset o północy za \(hours)h \(minutes)min")
        
        // Timer jednorazowy do północy
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in
                print("🌙 Północ - reset flagi powiadomienia")
                self.hasShownNotificationToday = false
                self.isSnoozed = false
                self.snoozeEndTime = nil
                self.setupMidnightReset()
            }
        }
    }
    
    /// Rozpoczyna sprawdzanie co minutę czy nadszedł czas powiadomienia
    private func startCheckingForNotificationTime() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                self.checkAndShowNotificationIfNeeded()
            }
        }

        
        // Sprawdź od razu przy starcie (na wypadek gdybyśmy uruchomili się po czasie)
        checkAndShowNotificationIfNeeded()
    }
    
    deinit {
        midnightTimer?.invalidate()
        checkTimer?.invalidate()
    }
}
