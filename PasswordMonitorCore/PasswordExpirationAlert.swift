//
//  PasswordExpirationAlert.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 02/02/2026.
//

import SwiftUI
import AppKit
import Foundation

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
    private let isDomainAvailable: Bool
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
        isDomainAvailable: Bool = true,
        mode: Mode = .live,
        onSnooze: @escaping () -> Void,
        onChangePassword: @escaping () -> Void,
        onEndTest: @escaping () -> Void = { }
    ) {
        self.expirationDate = expirationDate
        self.isDomainAvailable = isDomainAvailable
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
            isDomainAvailable: isDomainAvailable,
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
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: max(PMLayout.alertWindowMinWidth, contentSize.width),
                height: max(PMLayout.alertWindowMinHeight, contentSize.height)
            ),
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
    let isDomainAvailable: Bool
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
        isDomainAvailable: Bool,
        mode: PasswordExpirationAlert.Mode,
        isUrgent: Bool,
        onSnooze: @escaping () -> Void,
        onChangePassword: @escaping () -> Void,
        onEndTest: @escaping () -> Void
    ) {
        self.expirationDate = expirationDate
        self.isDomainAvailable = isDomainAvailable
        self.mode = mode
        self.isUrgent = isUrgent
        self.onSnooze = onSnooze
        self.onChangePassword = onChangePassword
        self.onEndTest = onEndTest
        _timeRemaining = State(initialValue: expirationDate.timeIntervalSinceNow)
    }

    var body: some View {
        VStack(spacing: PMLayout.cardSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: PMLayout.alertIconSize))
                .foregroundColor(isUrgent ? PMTheme.danger : PMTheme.warning)

            Text(localizedOrFallback("alert_title_expiring", fallback: "Your password is expiring soon!"))
                .font(.title2)
                .fontWeight(.bold)

            // Opis z zawijaniem tekstu
            Text(smartAdviceText())
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(PMTheme.textSecondary)
                .frame(maxWidth: PMLayout.alertAdviceMaxWidth)
                .fixedSize(horizontal: false, vertical: true)

            // Live timer – zawsze pokazuje rzeczywisty czas do wygaśnięcia
            VStack(spacing: PMLayout.compactSpacing) {
                Text(remainingTitleText)
                    .font(.caption)
                    .foregroundColor(PMTheme.textSecondary)

                let lines = formattedTimeRemainingLines()
                VStack(spacing: PMLayout.microSpacing) {
                    Text(lines.line1)
                        .font(.system(size: isUrgent ? PMLayout.alertTimerUrgentFontSize : PMLayout.alertTimerFontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(isUrgent ? PMTheme.danger : PMTheme.textPrimary)
                    Text(lines.line2)
                        .font(.system(size: isUrgent ? PMLayout.alertTimerUrgentFontSize : PMLayout.alertTimerFontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(isUrgent ? PMTheme.danger : PMTheme.textPrimary)
                }
                .onAppear { startTimer() }
                .onDisappear { stopTimer() }
            }
            .padding(.vertical, PMLayout.alertTimerVerticalPadding)
            .padding(.horizontal, PMLayout.alertTimerHorizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: PMLayout.alertTimerCornerRadius, style: .continuous)
                    .fill(PMTheme.fieldBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: PMLayout.alertTimerCornerRadius, style: .continuous)
                            .stroke(isUrgent ? PMTheme.danger.opacity(PMTheme.alertUrgentStrokeOpacity) : PMTheme.fieldStroke, lineWidth: PMLayout.hairlineWidth)
                    )
            )

            let snoozeDisabled = isUrgent && isDomainAvailable
            let changePasswordDisabled = !isDomainAvailable

            HStack(spacing: PMLayout.sectionSpacing) {
                // "Odłóż" – niedostępny tylko gdy hasło wygasa za ≤ 24h
                Button(action: onSnooze) {
                    Text(localizedOrFallback("alert_snooze", fallback: "Snooze"))
                        .frame(minWidth: PMLayout.alertButtonMinWidth)
                }
                .buttonStyle(.bordered)
                .tint(PMTheme.danger)
                .disabled(snoozeDisabled)
                .opacity(snoozeDisabled ? PMControlMetrics.disabledOpacity : PMControlMetrics.enabledOpacity)
                .help(snoozeDisabled
                      ? Text(localizedOrFallback("alert_snooze_help_disabled", fallback: "You can’t snooze when the password expires in less than 24 hours."))
                      : Text(localizedOrFallback("alert_snooze_help_enabled", fallback: "Remind me in 3 hours")))

                // "Zmień hasło" – na razie tylko log + zamknięcie okna
                Button(action: onChangePassword) {
                    Text(localizedOrFallback("alert_change_password", fallback: "Change Password"))
                        .frame(minWidth: PMLayout.alertButtonMinWidth)
                }
                .buttonStyle(.borderedProminent)
                .tint(PMTheme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(changePasswordDisabled)
                .opacity(changePasswordDisabled ? PMControlMetrics.disabledOpacity : PMControlMetrics.enabledOpacity)
            }
            .padding(.top, PMLayout.alertTimerVerticalPadding)

            if !isDomainAvailable {
                Text(localizedOrFallback("alert_domain_unavailable", fallback: "Connect to VPN and change your password."))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(PMTheme.danger)
                    .multilineTextAlignment(.center)
            }

            if mode == .test {
                Divider()
                    .padding(.top, PMLayout.microSpacing + PMLayout.microSpacing)

                Button(action: onEndTest) {
                    Text(localizedOrFallback("alert_end_test", fallback: "End Test"))
                        .frame(minWidth: PMLayout.alertEndTestButtonMinWidth)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            PMWindowFooter()
        }
        .padding(PMLayout.alertContentPadding)
        .pmPanel()
        .padding(PMLayout.alertOuterPadding)
        .id(themeToken)
        .pmWindowBackground()
        .frame(width: PMLayout.alertWidth)
        .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
            themeToken = UUID()
        }
    }

    // MARK: - Helpers
    
    private func smartAdviceText() -> String {
        let days = PasswordExpirationMath.daysRemaining(until: expirationDate)

        switch days {
        case ..<0:
            return localizedOrFallback("alert_advice_expired", fallback: "Your password has already expired. Change it immediately to avoid access issues.")
        case 0...1:
            return localizedOrFallback("alert_advice_today", fallback: "Your password expires today. Change it now to avoid account lockout.")
        case 2...7:
            return localizedOrFallback("alert_advice_week", fallback: "Your password expires within a week. Plan to change it before the deadline.")
        case _ where mode == .test:
            return localizedOrFallback("alert_advice_week", fallback: "Your password expires within a week. Plan to change it before the deadline.")
        default:
            return localizedOrFallback("alert_advice_default", fallback: "Your password is still valid, but company policy requires changing it regularly.")
        }
    }

    private var remainingTitleText: String {
        timeRemaining > 86400
            ? localizedOrFallback("alert_remaining_title_long", fallback: "Time remaining:")
            : localizedOrFallback("alert_remaining_title_short", fallback: "Time remaining:")
    }

    private func formattedExpirationDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "pl_PL")
        return formatter.string(from: expirationDate)
    }

    private func formattedTimeRemainingLines() -> (line1: String, line2: String) {
        let totalSeconds = max(0, Int(timeRemaining))
        let days = totalSeconds / 86400
        let remAfterDays = totalSeconds % 86400
        let hours = remAfterDays / 3600
        let minutes = (remAfterDays % 3600) / 60
        let seconds = remAfterDays % 60

        let dayText = localizedUnit("unit_day %lld", value: days, singular: "day", plural: "days")
        // Keep countdown deterministic; broken translations must not affect this format.
        let timeText = String(format: "%02d:%02d:%02d", hours, minutes, seconds)

        return (dayText, timeText)
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

    private func localizedOrFallback(_ key: String, fallback: String) -> String {
        let value = Logger.localizedString(key)
        return isBrokenLocalization(value, key: key) ? fallback : value
    }

    private func localizedUnit(_ key: String, value: Int, singular: String, plural: String) -> String {
        let localized = Logger.localizedString(key, value)
        if isBrokenLocalization(localized, key: key) {
            let unit = (value == 1) ? singular : plural
            return "\(value) \(unit)"
        }
        return localized
    }

    private func isBrokenLocalization(_ text: String, key: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed == key { return true }
        if trimmed.range(of: #"(?i)PH\s*[_-]?\s*\d+"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"^[a-z0-9]+(?:_[a-z0-9]+)+(?:\s+%[-+ #0'\d\.\@\w]+)?$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }
}
