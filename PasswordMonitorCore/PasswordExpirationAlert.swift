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

        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController

        let hostingView = hostingController.view

        let contentSize = hostingView.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: max(380, contentSize.width), height: max(220, contentSize.height)),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.window = panel

        panel.title = "Password Monitor"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false

        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowRect = panel.frame
            let x = screenRect.midX - windowRect.width / 2
            let y = screenRect.midY - windowRect.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 1.0
        panel.makeKeyAndOrderFront(nil)
    }

    /// Zamyka okienko
    func close() {
        window?.close()
        window = nil
        hostingController = nil
    }
}

// MARK: - SwiftUI Content View

/// Zawartość okienka alertu (UI)
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
        _timeRemaining = State(initialValue: expirationDate.timeIntervalSinceNow)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(isUrgent ? .red : .orange)

            Text("Twoje hasło wygasa!")
                .font(.title2)
                .fontWeight(.bold)

            // Opis z zawijaniem tekstu
            Text("Twoje hasło do domeny wygasa \(formattedExpirationDate()). Zmień je, aby uniknąć problemów z logowaniem.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)

            // Live timer – zawsze pokazuje rzeczywisty czas do wygaśnięcia
            VStack(spacing: 8) {
                Text(timeRemaining > 86400 ? "Pozostało:" : "Pozostało czasu:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(formattedTimeRemaining())
                    .font(.system(size: isUrgent ? 36 : 28, weight: .bold, design: .monospaced))
                    .foregroundColor(isUrgent ? .red : .primary)
                    .onAppear { startTimer() }
                    .onDisappear { stopTimer() }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background((isUrgent ? Color.red : Color.blue).opacity(0.1))
            .cornerRadius(8)

            HStack(spacing: 12) {
                // "Odłóż" – niedostępny tylko gdy hasło wygasa za ≤ 24h
                Button(action: onSnooze) {
                    Text("Odłóż")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isUrgent)
                .opacity(isUrgent ? 0.5 : 1.0)
                .help(isUrgent ? "Nie można odłożyć, gdy hasło wygasa za mniej niż 24h" : "Przypomnij za 3 godziny")

                // "Zmień hasło" – na razie tylko log + zamknięcie okna
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
        .padding(24)
        .frame(minWidth: 380, maxWidth: 420)
    }

    // MARK: - Helpers

    private func formattedExpirationDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "pl_PL")
        return formatter.string(from: expirationDate)
    }

    /// Pokazuje Xd Yh Zm Ts jeśli > 24h, inaczej HH:MM:SS
    private func formattedTimeRemaining() -> String {
        let totalSeconds = max(0, Int(timeRemaining))

        if totalSeconds > 86400 {
            let days = totalSeconds / 86400
            let remAfterDays = totalSeconds % 86400
            let hours = remAfterDays / 3600
            let minutes = (remAfterDays % 3600) / 60
            let seconds = remAfterDays % 60
            return "\(days)d \(hours)h \(minutes)m \(seconds)s"
        } else {
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
    }

    private func startTimer() {
        stopTimer()
        // Timer na głównej pętli, bez Task/Actor – prościej i bez ostrzeżeń Swift 6
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            timeRemaining = expirationDate.timeIntervalSinceNow
            if timeRemaining <= 0 {
                stopTimer()
                timeRemaining = 0
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Preview

#Preview {
    AlertContentView(
        expirationDate: Date().addingTimeInterval(3 * 24 * 3600),
        isUrgent: false,
        onSnooze: {},
        onChangePassword: {}
    )
}
