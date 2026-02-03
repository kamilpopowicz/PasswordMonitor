//
//  PasswordExpirationAlert.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 02/02/2026.
//


import SwiftUI
import AppKit

/// Modalne okienko powiadomienia o wygaśnięciu hasła
/// Zawsze na wierzchu, nie da się ukryć, z live licznikiem odliczającym
@MainActor
final class PasswordExpirationAlert {
    private let expirationDate: Date
    private let onSnooze: () -> Void
    private let onChangePassword: () -> Void
    
    private var window: NSPanel?
    private var countdownTimer: Timer?
    private var hostingController: NSHostingController<AlertContentView>?
    
    /// Tworzy okienko powiadomienia
    /// - Parameters:
    ///   - expirationDate: Data wygaśnięcia hasła
    ///   - onSnooze: Callback po kliknięciu "Odłóż"
    ///   - onChangePassword: Callback po kliknięciu "Zmień hasło"
    init(
        expirationDate: Date,
        onSnooze: @escaping () -> Void,
        onChangePassword: @escaping () -> Void
    ) {
        self.expirationDate = expirationDate
        self.onSnooze = onSnooze
        self.onChangePassword = onChangePassword
    }
    
    /// Pokazuje okienko na wierzchu wszystkich innych okien
    func show() {
        let hoursRemaining = expirationDate.timeIntervalSinceNow / 3600
        let isUrgent = hoursRemaining <= 24
        
        // Tworzymy View SwiftUI zawierające UI okienka
        let contentView = AlertContentView(
            expirationDate: expirationDate,
            isUrgent: isUrgent,
            onSnooze: { [weak self] in
                self?.close()
                self?.onSnooze()
            },
            onChangePassword: { [weak self] in
                self?.close()
                self?.onChangePassword()
            }
        )
        
        hostingController = NSHostingController(rootView: contentView)
        guard let hostingView = hostingController?.view else { return }
        
        // Oblicz rozmiar na podstawie zawartości
        hostingView.layoutSubtreeIfNeeded()
        let contentSize = hostingView.fittingSize
        
        // Tworzymy panel (utility window) zawsze na wierzchu
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window?.title = "Password Monitor"
        window?.titleVisibility = .hidden
        window?.titlebarAppearsTransparent = true
        window?.isMovable = false // Nie można przesuwać - zawsze na środku ekranu
        window?.level = .floating // Zawsze na wierzchu
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window?.contentView = hostingView
        window?.isReleasedWhenClosed = false
        
        // Wyśrodkuj na ekranie
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowRect = window?.frame ?? .zero
            let x = screenRect.midX - windowRect.width / 2
            let y = screenRect.midY - windowRect.height / 2
            window?.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window?.makeKeyAndOrderFront(nil)
        
        // Animacja pojawienia się
        window?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window?.animator().alphaValue = 1
        }
    }
    
    /// Zamyka okienko
    func close() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        
        Task { @MainActor in
            guard let window = self.window else {
                self.hostingController = nil
                return
            }
            
            // Używamy continuation zamiast completionHandler
            await withCheckedContinuation { continuation in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    window.animator().alphaValue = 0
                } completionHandler: {
                    window.close()
                    continuation.resume()
                }
            }
            
            self.window = nil
            self.hostingController = nil
        }
    }

}

// MARK: - SwiftUI Content View

/// Zawartość okienka alertu
private struct AlertContentView: View {
    let expirationDate: Date
    let isUrgent: Bool
    let onSnooze: () -> Void
    let onChangePassword: () -> Void
    
    @State private var timeRemaining: TimeInterval
    @State private var timer: Timer?
    
    init(
        expirationDate: Date,
        isUrgent: Bool,
        onSnooze: @escaping () -> Void,
        onChangePassword: @escaping () -> Void
    ) {
        self.expirationDate = expirationDate
        self.isUrgent = isUrgent
        self.onSnooze = onSnooze
        self.onChangePassword = onChangePassword
        self._timeRemaining = State(initialValue: expirationDate.timeIntervalSinceNow)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Ikona ostrzeżenia
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(isUrgent ? .red : .orange)
            
            // Tytuł
            Text("Twoje hasło wygasa!")
                .font(.title2)
                .fontWeight(.bold)
            
            // Opis
            Text("Twoje hasło do domeny wygasa \(formattedExpirationDate()). Zmień je aby uniknąć problemów z logowaniem.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 350)
            
            // 🔴 Live timer (widoczny tylko gdy < 24h)
            if isUrgent {
                VStack(spacing: 8) {
                    Text("Pozostało czasu:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formattedTimeRemaining())
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                        .onAppear {
                            startTimer()
                        }
                        .onDisappear {
                            timer?.invalidate()
                        }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Przyciski
            HStack(spacing: 12) {
                // 🔴 Odłóż (czerwony, wyłączony gdy < 24h)
                Button(action: onSnooze) {
                    Text("Odłóż")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isUrgent) // Nieaktywny gdy < 24h
                .help(isUrgent ? "Nie można odłożyć gdy hasło wygasa za mniej niż 24h" : "Przypomnij za 3 godziny")
                
                // 🔵 Zmień hasło (niebieski)
                Button(action: onChangePassword) {
                    Text("Zmień hasło")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 10)
        }
        .padding(30)
        .frame(minWidth: 400)
    }
    
    // MARK: - Helpers
    
    private func formattedExpirationDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "pl_PL")
        return formatter.string(from: expirationDate)
    }
    
    private func formattedTimeRemaining() -> String {
        let totalSeconds = max(0, timeRemaining)
        let hours = Int(totalSeconds) / 3600
        let minutes = Int(totalSeconds) % 3600 / 60
        let seconds = Int(totalSeconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                timeRemaining = expirationDate.timeIntervalSinceNow
                if timeRemaining <= 0 {
                    timer?.invalidate()
                    timeRemaining = 0
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AlertContentView(
        expirationDate: Date().addingTimeInterval(23 * 3600), // 23h do końca (urgent)
        isUrgent: true,
        onSnooze: {},
        onChangePassword: {}
    )
}
