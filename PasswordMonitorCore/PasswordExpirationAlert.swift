//
//  PasswordExpirationAlert.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 02/02/2026.
//

import SwiftUI
import AppKit

public extension Notification.Name {
    static let passwordAlertVisibilityChanged = Notification.Name("PasswordMonitor.PasswordAlertVisibilityChanged")
}

/// Modalne okienko powiadomienia o wygaśnięciu hasła
/// Zawsze na wierzchu, nie da się ukryć, z live licznikiem odliczającym
@MainActor
final class PasswordExpirationAlert {
    enum Mode {
        case live
        case test
    }

    private let expirationDate: Date
    private let mode: Mode
    private let onSnooze: () -> Void
    private let onChangePassword: () -> Void
    private let onEndTest: () -> Void

    private var window: NSPanel?
    private var hostingController: NSHostingController<AlertContentView>?

    /// Tworzy okienko powiadomienia
    /// - Parameters:
    ///   - expirationDate: Data wygaśnięcia hasła
    ///   - onSnooze: Callback po kliknięciu "Odłóż"
    ///   - onChangePassword: Callback po kliknięciu "Zmień hasło"
    init(
        expirationDate: Date,
        mode: Mode = .live,
        onSnooze: @escaping () -> Void,
        onChangePassword: @escaping () -> Void,
        onEndTest: @escaping () -> Void = { }
    ) {
        self.expirationDate = expirationDate
        self.mode = mode
        self.onSnooze = onSnooze
        self.onChangePassword = onChangePassword
        self.onEndTest = onEndTest
    }

    /// Pokazuje okienko na wierzchu wszystkich innych okien
    func show() {
        NotificationCenter.default.post(
            name: .passwordAlertVisibilityChanged,
            object: nil,
            userInfo: ["isVisible": true]
        )

        let hoursRemaining = expirationDate.timeIntervalSinceNow / 3600
        let isUrgent = hoursRemaining <= 24

        let contentView = AlertContentView(
            expirationDate: expirationDate,
            mode: mode,
            isUrgent: isUrgent,
            onSnooze: { [weak self] in
                self?.close()
                self?.onSnooze()
            },
            onChangePassword: { [weak self] in
                self?.close()
                self?.onChangePassword()
            },
            onEndTest: { [weak self] in
                self?.close()
                self?.onEndTest()
            }
        )

        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController

        let hostingView = hostingController.view

        let contentSize = hostingView.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: max(420, contentSize.width), height: max(240, contentSize.height)),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.window = panel

        panel.title = String(localized: "app_name")
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
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    /// Zamyka okienko
    func close() {
        window?.close()
        window = nil
        hostingController = nil
        NotificationCenter.default.post(
            name: .passwordAlertVisibilityChanged,
            object: nil,
            userInfo: ["isVisible": false]
        )
    }
}

// MARK: - SwiftUI Content View

/// Zawartość okienka alertu (UI)
private struct AlertContentView: View {
    let expirationDate: Date
    let mode: PasswordExpirationAlert.Mode
    let isUrgent: Bool
    let onSnooze: () -> Void
    let onChangePassword: () -> Void
    let onEndTest: () -> Void

    @State private var timeRemaining: TimeInterval
    @State private var timer: Timer?
    @State private var themeToken = UUID()

    init(
        expirationDate: Date,
        mode: PasswordExpirationAlert.Mode,
        isUrgent: Bool,
        onSnooze: @escaping () -> Void,
        onChangePassword: @escaping () -> Void,
        onEndTest: @escaping () -> Void
    ) {
        self.expirationDate = expirationDate
        self.mode = mode
        self.isUrgent = isUrgent
        self.onSnooze = onSnooze
        self.onChangePassword = onChangePassword
        self.onEndTest = onEndTest
        _timeRemaining = State(initialValue: expirationDate.timeIntervalSinceNow)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(isUrgent ? PMTheme.danger : PMTheme.warning)

            Text("alert_title_expiring")
                .font(.title2)
                .fontWeight(.bold)

            // Opis z zawijaniem tekstu
            Text(smartAdviceTextKey())
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(PMTheme.textSecondary)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)

            // Live timer – zawsze pokazuje rzeczywisty czas do wygaśnięcia
            VStack(spacing: 8) {
                Text(remainingTitleKey)
                    .font(.caption)
                    .foregroundColor(PMTheme.textSecondary)

                if let lines = formattedTimeRemainingLines() {
                    VStack(spacing: 2) {
                        Text(lines.line1)
                            .font(.system(size: isUrgent ? 32 : 26, weight: .bold, design: .monospaced))
                            .foregroundColor(isUrgent ? PMTheme.danger : PMTheme.textPrimary)
                        Text(lines.line2)
                            .font(.system(size: isUrgent ? 32 : 26, weight: .bold, design: .monospaced))
                            .foregroundColor(isUrgent ? PMTheme.danger : PMTheme.textPrimary)
                    }
                    .onAppear { startTimer() }
                    .onDisappear { stopTimer() }
                } else {
                    Text(formattedTimeRemaining())
                        .font(.system(size: isUrgent ? 34 : 28, weight: .bold, design: .monospaced))
                        .foregroundColor(isUrgent ? PMTheme.danger : PMTheme.textPrimary)
                        .onAppear { startTimer() }
                        .onDisappear { stopTimer() }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PMTheme.fieldBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isUrgent ? PMTheme.danger.opacity(0.6) : PMTheme.fieldStroke, lineWidth: 1)
                    )
            )

            HStack(spacing: 12) {
                // "Odłóż" – niedostępny tylko gdy hasło wygasa za ≤ 24h
                Button(action: onSnooze) {
                    Text("alert_snooze")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .tint(PMTheme.danger)
                .disabled(isUrgent)
                .opacity(isUrgent ? 0.5 : 1.0)
                .help(isUrgent
                      ? Text("alert_snooze_help_disabled")
                      : Text("alert_snooze_help_enabled"))

                // "Zmień hasło" – na razie tylko log + zamknięcie okna
                Button(action: onChangePassword) {
                    Text("alert_change_password")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .tint(PMTheme.accent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 10)

            if mode == .test {
                Divider()
                    .padding(.top, 4)

                Button(action: onEndTest) {
                    Text("alert_end_test")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            Text("Copyright (c) 2026 Kamil Popowicz. All rights reserved.")
                .font(.caption2)
                .foregroundColor(PMTheme.textSecondary)
                .padding(.vertical, 12)
        }
        .padding(24)
        .pmPanel()
        .padding()
        .id(themeToken)
        .pmWindowBackground()
        .frame(width: 420)
        .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
            themeToken = UUID()
        }
    }

    // MARK: - Helpers
    
    private func smartAdviceTextKey() -> LocalizedStringKey {
        let days = PasswordExpirationMath.daysRemaining(until: expirationDate)

        switch days {
        case ..<0:
            return LocalizedStringKey("alert_advice_expired")
        case 0...1:
            return LocalizedStringKey("alert_advice_today")
        case 2...7:
            return LocalizedStringKey("alert_advice_week")
        case _ where mode == .test:
            return LocalizedStringKey("alert_advice_week")
        default:
            return LocalizedStringKey("alert_advice_default")
        }
    }

    private var remainingTitleKey: LocalizedStringKey {
        timeRemaining > 86400
            ? LocalizedStringKey("alert_remaining_title_long")
            : LocalizedStringKey("alert_remaining_title_short")
    }

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
            let dayText = Logger.localizedString("unit_day %lld", days)
            let hourText = Logger.localizedString("unit_hour %lld", hours)
            let minuteText = Logger.localizedString("unit_minute %lld", minutes)
            let secondText = Logger.localizedString("unit_second %lld", seconds)
            return "\(dayText) \(hourText) \(minuteText) \(secondText)"
        } else {
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            return Logger.localizedString(
                "alert_remaining_short_format",
                hours,
                minutes,
                seconds
            )
        }
    }

    private func formattedTimeRemainingLines() -> (line1: String, line2: String)? {
        let totalSeconds = max(0, Int(timeRemaining))
        guard totalSeconds > 86400 else { return nil }

        let days = totalSeconds / 86400
        let remAfterDays = totalSeconds % 86400
        let hours = remAfterDays / 3600
        let minutes = (remAfterDays % 3600) / 60
        let seconds = remAfterDays % 60

        let dayText = Logger.localizedString("unit_day %lld", days)
        let hourText = Logger.localizedString("unit_hour %lld", hours)
        let minuteText = Logger.localizedString("unit_minute %lld", minutes)
        let secondText = Logger.localizedString("unit_second %lld", seconds)

        return ("\(dayText) \(hourText)", "\(minuteText) \(secondText)")
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
    Group {
        AlertContentView(
            expirationDate: Date().addingTimeInterval(3 * 24 * 3600),
            mode: .live,
            isUrgent: false,
            onSnooze: {},
            onChangePassword: {},
            onEndTest: {}
        )
        AlertContentView(
            expirationDate: Date().addingTimeInterval(999 * 24 * 3600),
            mode: .test,
            isUrgent: false,
            onSnooze: {},
            onChangePassword: {},
            onEndTest: {}
        )
    }
}
