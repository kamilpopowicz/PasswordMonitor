//
//  PasswordChangeView.swift
//  PasswordMonitor
//
//  Created by Codex on 21/05/2026.
//

import SwiftUI
import Combine
import PasswordMonitorCore

struct PasswordChangeView: View {
    @StateObject private var model = PasswordChangeViewModel()

    let onCancel: () -> Void
    let onSuccess: () -> Void

    var body: some View {
        VStack(spacing: PMLayout.sectionSpacing) {
            PMWindowContentContainer {
                VStack(alignment: .leading, spacing: PMLayout.sectionSpacing) {
                    header

                    VStack(alignment: .leading, spacing: PMLayout.controlSpacing) {
                        PasswordInputRow(
                            title: PasswordChangeCopy.currentPassword,
                            text: $model.currentPassword,
                            isRevealed: model.isPasswordRevealed
                        )

                        PasswordInputRow(
                            title: PasswordChangeCopy.newPassword,
                            text: $model.newPassword,
                            isRevealed: model.isPasswordRevealed
                        )

                        PasswordInputRow(
                            title: PasswordChangeCopy.confirmPassword,
                            text: $model.confirmPassword,
                            isRevealed: model.isPasswordRevealed
                        )
                    }

                    Toggle(PasswordChangeCopy.showPasswords, isOn: $model.isPasswordRevealed)
                        .foregroundColor(PMTheme.textSecondary)

                    strengthPanel

                    if let message = model.validationMessage {
                        MessageBanner(message: message, kind: .warning)
                    }

                    if let message = model.statusMessage {
                        MessageBanner(message: message, kind: model.statusKind)
                    }
                }
                .pmContentCard()
            }

            PMWindowActionBar {
                PMAdaptiveActionRow(verticalAlignment: .center, spacing: PMLayout.compactSpacing) {
                    Button(PasswordChangeCopy.openSystemSettings) {
                        PasswordChangeHelper.openSystemPasswordSettings()
                    }
                    .pmButton()
                    .disabled(model.isSubmitting)

                    Spacer(minLength: PMLayout.zeroMinLength)

                    Button(PasswordChangeCopy.cancel) {
                        onCancel()
                    }
                    .pmButton()
                    .disabled(model.isSubmitting)

                    Button {
                        model.submit(onSuccess: onSuccess)
                    } label: {
                        if model.isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(PasswordChangeCopy.changePassword)
                                .pmMultilineText(alignment: .center)
                        }
                    }
                    .pmButton(role: .primary)
                    .disabled(!model.canSubmit)
                }
            }
        }
        .padding(.vertical, PMLayout.windowContentHorizontalPadding)
        .frame(
            minWidth: PMLayout.passwordChangeWindowMinWidth,
            minHeight: PMLayout.passwordChangeWindowMinHeight
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PMLayout.microSpacing) {
            Text(PasswordChangeCopy.title)
                .font(.title2.weight(.semibold))
                .foregroundColor(PMTheme.textPrimary)
                .pmMultilineText()

            Text(PasswordChangeCopy.subtitle)
                .font(.subheadline)
                .foregroundColor(PMTheme.textSecondary)
                .pmMultilineText()
        }
    }

    private var strengthPanel: some View {
        VStack(alignment: .leading, spacing: PMLayout.compactSpacing) {
            HStack {
                Text(PasswordChangeCopy.strength)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(PMTheme.textSecondary)
                Spacer(minLength: PMLayout.zeroMinLength)
                Text(model.strengthLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(model.strengthColor)
            }

            HStack(spacing: PMLayout.microSpacing) {
                ForEach(PasswordStrengthLevel.allCases, id: \.rawValue) { level in
                    RoundedRectangle(cornerRadius: PMLayout.passwordStrengthMeterHeight, style: .continuous)
                        .fill(level.rawValue <= model.strength.score ? model.strengthColor : PMTheme.fieldStroke)
                        .frame(
                            minWidth: PMLayout.passwordStrengthSegmentMinWidth,
                            maxWidth: .infinity,
                            minHeight: PMLayout.passwordStrengthMeterHeight,
                            maxHeight: PMLayout.passwordStrengthMeterHeight
                        )
                }
            }

            ForEach(model.strength.feedback, id: \.self) { feedback in
                Text(feedback)
                    .font(.caption)
                    .foregroundColor(PMTheme.textSecondary)
                    .pmMultilineText()
            }
        }
        .padding(PMLayout.panelPadding)
        .background(PMTheme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: PMLayout.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PMLayout.panelCornerRadius, style: .continuous)
                .stroke(PMTheme.fieldStroke, lineWidth: PMLayout.hairlineWidth)
        )
    }
}

@MainActor
final class PasswordChangeViewModel: ObservableObject {
    @Published var currentPassword = ""
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published var isPasswordRevealed = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusKind: MessageBanner.Kind = .info

    private let manager = PasswordChangeManager()

    var strength: PasswordStrength {
        PasswordStrengthAnalyzer.analyze(
            newPassword,
            userInputs: [
                NSUserName(),
                SystemADDomainResolver.currentDomain() ?? "",
                "PasswordMonitor"
            ]
        )
    }

    var validationMessage: String? {
        if currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty {
            return PasswordChangeCopy.fillAllFields
        }

        if newPassword != confirmPassword {
            return PasswordChangeCopy.passwordsDoNotMatch
        }

        if currentPassword == newPassword {
            return PasswordChangeCopy.passwordMustChange
        }

        if newPassword.count < PasswordStrengthAnalyzer.minimumUsefulLength {
            return PasswordChangeCopy.passwordTooShort
        }

        return nil
    }

    var canSubmit: Bool {
        validationMessage == nil && !isSubmitting
    }

    var strengthLabel: String {
        switch strength.level {
        case .veryWeak:
            return PasswordChangeCopy.veryWeak
        case .weak:
            return PasswordChangeCopy.weak
        case .fair:
            return PasswordChangeCopy.fair
        case .strong:
            return PasswordChangeCopy.strong
        case .excellent:
            return PasswordChangeCopy.excellent
        @unknown default:
            return PasswordChangeCopy.weak
        }
    }

    var strengthColor: Color {
        switch strength.level {
        case .veryWeak, .weak:
            return PMTheme.danger
        case .fair:
            return PMTheme.warning
        case .strong, .excellent:
            return PMTheme.success
        @unknown default:
            return PMTheme.danger
        }
    }

    func submit(onSuccess: @escaping () -> Void) {
        guard canSubmit else { return }

        isSubmitting = true
        statusMessage = PasswordChangeCopy.changing
        statusKind = .info

        let current = currentPassword
        let new = newPassword

        Task {
            do {
                _ = try await manager.changePassword(currentPassword: current, newPassword: new)
                clearPasswords()
                statusMessage = PasswordChangeCopy.success
                statusKind = .success
                NotificationManager.shared.refreshPasswordStatusLive(reason: .manual)
                onSuccess()
            } catch {
                statusMessage = PasswordChangeCopy.message(for: PasswordChangeManager.map(error))
                statusKind = .error
            }

            isSubmitting = false
        }
    }

    private func clearPasswords() {
        currentPassword = ""
        newPassword = ""
        confirmPassword = ""
        isPasswordRevealed = false
    }
}

private struct PasswordInputRow: View {
    let title: String
    @Binding var text: String
    let isRevealed: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: PMLayout.controlSpacing) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(PMTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pmMultilineText()
                passwordField
                    .frame(minWidth: PMLayout.passwordChangeFieldMinWidth)
            }

            VStack(alignment: .leading, spacing: PMLayout.microSpacing) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(PMTheme.textPrimary)
                    .pmMultilineText()
                passwordField
            }
        }
    }

    @ViewBuilder
    private var passwordField: some View {
        if isRevealed {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        } else {
            SecureField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct MessageBanner: View {
    enum Kind {
        case info
        case warning
        case error
        case success
    }

    let message: String
    let kind: Kind

    var body: some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundColor(color)
            .pmMultilineText()
            .padding(PMLayout.compactSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(PMControlMetrics.disabledSecondaryFillOpacity))
            .clipShape(RoundedRectangle(cornerRadius: PMLayout.compactSpacing, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PMLayout.compactSpacing, style: .continuous)
                    .stroke(color.opacity(PMControlMetrics.disabledStrokeOpacity), lineWidth: PMLayout.hairlineWidth)
            )
    }

    private var color: Color {
        switch kind {
        case .info:
            return PMTheme.accent
        case .warning:
            return PMTheme.warning
        case .error:
            return PMTheme.danger
        case .success:
            return PMTheme.success
        }
    }
}

enum PasswordChangeCopy {
    static var windowTitle: String { localized(pl: "Zmiana hasła", en: "Change Password") }
    static var title: String { localized(pl: "Zmień hasło domenowe", en: "Change domain password") }
    static var subtitle: String { localized(pl: "Zmiana używa konta AD/mobile skonfigurowanego na tym Macu.", en: "This uses the AD/mobile account configured on this Mac.") }
    static var currentPassword: String { localized(pl: "Stare hasło", en: "Current password") }
    static var newPassword: String { localized(pl: "Nowe hasło", en: "New password") }
    static var confirmPassword: String { localized(pl: "Zweryfikuj", en: "Verify") }
    static var showPasswords: String { localized(pl: "Pokaż hasła", en: "Show passwords") }
    static var strength: String { localized(pl: "Siła hasła", en: "Password strength") }
    static var openSystemSettings: String { localized(pl: "Otwórz Touch ID i hasło", en: "Open Touch ID & Password") }
    static var cancel: String { localized(pl: "Anuluj", en: "Cancel") }
    static var changePassword: String { localized(pl: "Zmień hasło", en: "Change password") }
    static var fillAllFields: String { localized(pl: "Wypełnij wszystkie pola.", en: "Fill in all fields.") }
    static var passwordsDoNotMatch: String { localized(pl: "Nowe hasło i weryfikacja nie są takie same.", en: "New password and verification do not match.") }
    static var passwordMustChange: String { localized(pl: "Nowe hasło musi różnić się od starego.", en: "New password must be different from the current password.") }
    static var passwordTooShort: String { localized(pl: "Użyj co najmniej 8 znaków.", en: "Use at least 8 characters.") }
    static var changing: String { localized(pl: "Zmieniam hasło domenowe...", en: "Changing domain password...") }
    static var success: String { localized(pl: "Hasło zostało zmienione.", en: "Password changed.") }
    static var veryWeak: String { localized(pl: "Bardzo słabe", en: "Very weak") }
    static var weak: String { localized(pl: "Słabe", en: "Weak") }
    static var fair: String { localized(pl: "Średnie", en: "Fair") }
    static var strong: String { localized(pl: "Silne", en: "Strong") }
    static var excellent: String { localized(pl: "Bardzo silne", en: "Excellent") }

    static func message(for error: PasswordChangeError) -> String {
        switch error {
        case .activeDirectoryRequired:
            return localized(pl: "Ten flow wymaga konta AD/mobile.", en: "This flow requires an AD/mobile account.")
        case .currentPasswordInvalid:
            return localized(pl: "Stare hasło jest nieprawidłowe.", en: "Current password is incorrect.")
        case .passwordPolicyFailed, .passwordTooShort, .passwordTooLong, .passwordNeedsLetter, .passwordNeedsDigit:
            return localized(pl: "Nowe hasło nie spełnia polityki domeny.", en: "New password does not meet the domain policy.")
        case .passwordChangeTooSoon:
            return localized(pl: "Polityka domeny nie pozwala jeszcze zmienić hasła.", en: "Domain policy does not allow another password change yet.")
        case .domainUnavailable:
            return localized(pl: "Brak połączenia z domeną. Połącz VPN lub sieć firmową.", en: "Domain is unavailable. Connect VPN or the corporate network.")
        case .accountNotFound:
            return localized(pl: "Nie znaleziono konta AD/mobile dla tego użytkownika.", en: "No AD/mobile account was found for this user.")
        case .accountLocked:
            return localized(pl: "Konto jest zablokowane lub czasowo zablokowane.", en: "The account is locked or temporarily locked.")
        case .notAuthorized:
            return localized(pl: "Brak uprawnień do zmiany hasła dla tego konta.", en: "Not authorized to change this account password.")
        case .methodNotSupported:
            return localized(pl: "Ten węzeł domeny nie wspiera zmiany hasła przez OpenDirectory.", en: "This domain node does not support OpenDirectory password change.")
        case .operationFailed:
            return localized(pl: "Zmiana hasła nie powiodła się.", en: "Password change failed.")
        case let .unknown(_, message):
            return localized(pl: "Zmiana hasła nie powiodła się: \(message)", en: "Password change failed: \(message)")
        @unknown default:
            return localized(pl: "Zmiana hasła nie powiodła się.", en: "Password change failed.")
        }
    }

    private static func localized(pl: String, en: String) -> String {
        LanguageSettings.currentLanguageCode().hasPrefix("pl") ? pl : en
    }
}
