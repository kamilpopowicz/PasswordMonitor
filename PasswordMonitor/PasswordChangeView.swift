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
    @State private var isKeychainHelpPresented = false

    let onCancel: () -> Void

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

                    if let validationMessage = model.validationMessage {
                        MessageBanner(message: validationMessage, kind: .warning)
                    }

                    if let resultPanel = model.resultPanel {
                        PasswordChangeResultPanelView(
                            panel: resultPanel,
                            onClose: {
                                model.dismissResult()
                                onCancel()
                            },
                            onOpenSystemSettings: PasswordChangeHelper.openSystemPasswordSettings,
                            onOpenKeychainHelp: { isKeychainHelpPresented = true },
                            onRetryKeychainSync: { model.retryKeychainSync() }
                        )
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

                    if model.hasSuccessfulResult {
                        Button(PasswordChangeCopy.close) {
                            model.dismissResult()
                            onCancel()
                        }
                        .pmButton(role: .primary)
                        .disabled(model.isSubmitting)
                    } else {
                        Button(PasswordChangeCopy.cancel) {
                            onCancel()
                        }
                        .pmButton()
                        .disabled(model.isSubmitting)

                        Button {
                            model.submit()
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
        }
        .sheet(isPresented: $isKeychainHelpPresented) {
            KeychainSyncHelpSheet(onClose: { isKeychainHelpPresented = false })
                .pmWindowBackground()
        }
        .onChange(of: model.currentPassword) { _ in
            model.resetResultIfNeeded()
        }
        .onChange(of: model.newPassword) { _ in
            model.resetResultIfNeeded()
        }
        .onChange(of: model.confirmPassword) { _ in
            model.resetResultIfNeeded()
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
    @Published private var resultState: PasswordChangeResultState = .idle

    private let manager = PasswordChangeManager()
    private let keychainSyncManager = KeychainPasswordSyncManager()
    private var pendingKeychainRetryCredentials: (currentPassword: String, newPassword: String)?
    private static let recentPasswordChangeWindow: TimeInterval = 24 * 60 * 60

    var hasSuccessfulResult: Bool {
        if case .success = resultState {
            return true
        }
        return false
    }

    fileprivate var resultPanel: PasswordChangeResultPanel? {
        switch resultState {
        case .idle, .submitting:
            return nil
        case let .success(keychainResult, refreshResult):
            let refreshMessage: String
            switch refreshResult {
            case .refreshed:
                refreshMessage = PasswordChangeCopy.successRefreshUpdated
            case .refreshFailed:
                refreshMessage = PasswordChangeCopy.successRefreshUncertain
            }

            return PasswordChangeResultPanel(
                title: PasswordChangeCopy.successTitle,
                message: refreshMessage,
                diagnosticCode: nil,
                kind: .success,
                keychainResult: keychainResult
            )
        case let .failure(presentation):
            return PasswordChangeResultPanel(
                title: PasswordChangeCopy.failureTitle,
                message: presentation.message,
                diagnosticCode: presentation.code,
                kind: .error,
                keychainResult: nil
            )
        }
    }

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

        if currentPasswordContainsUnsupportedLineBreak || newPasswordContainsUnsupportedLineBreak || confirmPasswordContainsUnsupportedLineBreak {
            return PasswordChangeCopy.passwordContainsUnsupportedCharacters
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

    private var currentPasswordContainsUnsupportedLineBreak: Bool {
        currentPassword.contains("\n") || currentPassword.contains("\r")
    }

    private var newPasswordContainsUnsupportedLineBreak: Bool {
        newPassword.contains("\n") || newPassword.contains("\r")
    }

    private var confirmPasswordContainsUnsupportedLineBreak: Bool {
        confirmPassword.contains("\n") || confirmPassword.contains("\r")
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

    func submit() {
        guard canSubmit else { return }

        isSubmitting = true
        resultState = .submitting

        let current = currentPassword
        let new = newPassword

        Task {
            do {
                _ = try await manager.changePassword(currentPassword: current, newPassword: new)
                let keychainResult = await syncKeychainPassword(currentPassword: current, newPassword: new)
                updatePendingKeychainRetryCredentials(
                    for: keychainResult,
                    currentPassword: current,
                    newPassword: new
                )
                clearPasswords()
                let refreshResult = await refreshPasswordStatusAfterChange()
                resultState = .success(keychainResult: keychainResult, refreshResult: refreshResult)
            } catch {
                let mappedError = PasswordChangeManager.map(error)
                clearPendingKeychainRetryCredentials()
                resultState = .failure(
                    presentation: PasswordChangeCopy.presentation(
                        for: mappedError,
                        likelyRecentChangePolicy: likelyRecentChangePolicy()
                    )
                )
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

    private func likelyRecentChangePolicy() -> Bool {
        guard let info = NotificationManager.shared.latestPasswordInfo,
              !info.isFromCache else {
            return false
        }

        let age = Date().timeIntervalSince(info.lastSetDate)
        return age >= 0 && age <= Self.recentPasswordChangeWindow
    }

    private func updatePendingKeychainRetryCredentials(
        for keychainResult: PasswordKeychainSyncResult,
        currentPassword: String,
        newPassword: String
    ) {
        if case .failed = keychainResult {
            pendingKeychainRetryCredentials = (
                currentPassword: currentPassword,
                newPassword: newPassword
            )
        } else {
            clearPendingKeychainRetryCredentials()
        }
    }

    private func clearPendingKeychainRetryCredentials() {
        pendingKeychainRetryCredentials = nil
    }

    func resetResultIfNeeded() {
        switch resultState {
        case .success, .failure:
            resultState = .idle
            clearPendingKeychainRetryCredentials()
        case .idle, .submitting:
            break
        }
    }

    func dismissResult() {
        resetResultIfNeeded()
        clearPendingKeychainRetryCredentials()
    }

    func retryKeychainSync() {
        guard case let .success(currentKeychainResult, refreshResult) = resultState else {
            return
        }
        guard case .failed = currentKeychainResult else {
            return
        }
        guard let credentials = pendingKeychainRetryCredentials else {
            resultState = .success(
                keychainResult: .failed(presentation: PasswordChangeCopy.keychainPresentation(for: .operationFailed, isRetry: true)),
                refreshResult: refreshResult
            )
            return
        }

        isSubmitting = true
        clearPendingKeychainRetryCredentials()
        Task {
            let keychainResult = await syncKeychainPassword(
                currentPassword: credentials.currentPassword,
                newPassword: credentials.newPassword,
                isRetry: true
            )
            resultState = .success(keychainResult: keychainResult, refreshResult: refreshResult)
            clearPendingKeychainRetryCredentials()
            isSubmitting = false
        }
    }

    private func refreshPasswordStatusAfterChange() async -> PasswordChangeRefreshResult {
        await withCheckedContinuation { continuation in
            var didResume = false
            let finish: (PasswordChangeRefreshResult) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: result)
            }

            NotificationManager.shared.refreshPasswordStatusLive(
                reason: .manual,
                timeout: 15,
                shouldCheckNotification: false,
                onResult: { _ in
                    finish(.refreshed)
                },
                onError: { _ in
                    finish(.refreshFailed)
                }
            )
        }
    }

    private func syncKeychainPassword(
        currentPassword: String,
        newPassword: String,
        isRetry: Bool = false
    ) async -> PasswordKeychainSyncResult {
        do {
            _ = try await keychainSyncManager.syncLoginKeychainPassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            return .synced(isRetry: isRetry)
        } catch {
            let mapped: KeychainPasswordSyncError
            if let keychainError = error as? KeychainPasswordSyncError {
                mapped = keychainError
            } else {
                mapped = .operationFailed
            }
            return .failed(
                presentation: PasswordChangeCopy.keychainPresentation(
                    for: mapped,
                    isRetry: isRetry
                )
            )
        }
    }
}

private enum PasswordChangeResultState {
    case idle
    case submitting
    case success(keychainResult: PasswordKeychainSyncResult, refreshResult: PasswordChangeRefreshResult)
    case failure(presentation: PasswordChangeErrorPresentation)
}

private enum PasswordChangeRefreshResult {
    case refreshed
    case refreshFailed
}

fileprivate struct PasswordChangeErrorPresentation {
    let code: String
    let message: String
}

fileprivate struct PasswordChangeResultPanel {
    let title: String
    let message: String
    let diagnosticCode: String?
    let kind: MessageBanner.Kind
    let keychainResult: PasswordKeychainSyncResult?
}

private enum PasswordKeychainSyncResult {
    case synced(isRetry: Bool)
    case failed(presentation: PasswordKeychainPresentation)
}

fileprivate struct PasswordKeychainPresentation {
    let title: String
    let message: String
    let code: String
    let kind: MessageBanner.Kind
    let canRetry: Bool
}

private struct PasswordChangeResultPanelView: View {
    let panel: PasswordChangeResultPanel
    let onClose: () -> Void
    let onOpenSystemSettings: () -> Void
    let onOpenKeychainHelp: () -> Void
    let onRetryKeychainSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PMLayout.compactSpacing) {
            Text(panel.title)
                .font(.headline.weight(.semibold))
                .foregroundColor(PMTheme.textPrimary)
                .pmMultilineText()

            MessageBanner(message: panel.message, kind: panel.kind)

            if let diagnosticCode = panel.diagnosticCode {
                Text(PasswordChangeCopy.diagnosticCode(diagnosticCode))
                    .font(.caption)
                    .foregroundColor(PMTheme.textSecondary)
                    .pmMultilineText()
            }

            if let keychainResult = panel.keychainResult {
                keychainSection(for: keychainResult)
            }

            PMAdaptiveActionRow(verticalAlignment: .center, spacing: PMLayout.compactSpacing) {
                Button(PasswordChangeCopy.close) {
                    onClose()
                }
                .pmButton()

                Button(PasswordChangeCopy.openSystemSettings) {
                    onOpenSystemSettings()
                }
                .pmButton()

                if shouldShowRetryButton {
                    Button(PasswordChangeCopy.retryKeychainSync) {
                        onRetryKeychainSync()
                    }
                    .pmButton()
                }

                if shouldShowKeychainHelpButton {
                    Button(PasswordChangeCopy.keychainInstructions) {
                        onOpenKeychainHelp()
                    }
                    .pmButton(role: .primary)
                }
            }
        }
        .padding(PMLayout.compactSpacing)
        .background(PMTheme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: PMLayout.compactSpacing, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PMLayout.compactSpacing, style: .continuous)
                .stroke(PMTheme.fieldStroke, lineWidth: PMLayout.hairlineWidth)
        )
    }

    private var shouldShowRetryButton: Bool {
        guard let keychainResult = panel.keychainResult else {
            return false
        }
        if case let .failed(presentation) = keychainResult {
            return presentation.canRetry
        }
        return false
    }

    private var shouldShowKeychainHelpButton: Bool {
        panel.keychainResult != nil
    }

    @ViewBuilder
    private func keychainSection(for result: PasswordKeychainSyncResult) -> some View {
        switch result {
        case let .synced(isRetry):
            MessageBanner(
                message: isRetry ? PasswordChangeCopy.keychainSyncRetrySuccess : PasswordChangeCopy.keychainSyncSuccess,
                kind: .success
            )
        case let .failed(presentation):
            MessageBanner(
                message: presentation.message,
                kind: presentation.kind
            )
            Text(PasswordChangeCopy.diagnosticCode(presentation.code))
                .font(.caption)
                .foregroundColor(PMTheme.textSecondary)
                .pmMultilineText()
            MessageBanner(
                message: PasswordChangeCopy.keychainGuidanceBanner,
                kind: .warning
            )
        }
    }
}

private struct KeychainSyncHelpSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PMLayout.sectionSpacing) {
            Text(PasswordChangeCopy.keychainHelpTitle)
                .font(.title3.weight(.semibold))
                .foregroundColor(PMTheme.textPrimary)
                .pmMultilineText()

            Text(PasswordChangeCopy.keychainHelpSummary)
                .font(.subheadline)
                .foregroundColor(PMTheme.textSecondary)
                .pmMultilineText()

            VStack(alignment: .leading, spacing: PMLayout.microSpacing) {
                Text(PasswordChangeCopy.keychainHelpStep1Numbered)
                Text(PasswordChangeCopy.keychainHelpStep2Numbered)
                Text(PasswordChangeCopy.keychainHelpStep3Numbered)
                Text(PasswordChangeCopy.keychainHelpStep4Numbered)
            }
            .font(.subheadline)
            .foregroundColor(PMTheme.textPrimary)
            .pmMultilineText()

            PMWindowActionBar {
                PMAdaptiveActionRow(verticalAlignment: .center, spacing: PMLayout.compactSpacing) {
                    Button(PasswordChangeCopy.openSystemSettings) {
                        PasswordChangeHelper.openSystemPasswordSettings()
                    }
                    .pmButton()

                    Spacer(minLength: PMLayout.zeroMinLength)

                    Button(PasswordChangeCopy.close) {
                        onClose()
                    }
                    .pmButton(role: .primary)
                }
            }
        }
        .padding(PMLayout.windowContentHorizontalPadding)
        .frame(
            minWidth: PMLayout.passwordKeychainHelpMinWidth,
            minHeight: PMLayout.passwordKeychainHelpMinHeight
        )
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
        HStack(alignment: .top, spacing: PMLayout.compactSpacing) {
            Image(systemName: iconName)
                .font(.callout.weight(.semibold))
                .foregroundColor(color)
                .accessibilityHidden(true)

            Text(message)
                .font(.callout.weight(.semibold))
                .foregroundColor(PMTheme.textPrimary)
                .pmMultilineText()
        }
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

    private var iconName: String {
        switch kind {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .success:
            return "checkmark.circle.fill"
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
    static var close: String { localized(pl: "Zamknij", en: "Close") }
    static var changePassword: String { localized(pl: "Zmień hasło", en: "Change password") }
    static var fillAllFields: String { localized(pl: "Wypełnij wszystkie pola.", en: "Fill in all fields.") }
    static var passwordContainsUnsupportedCharacters: String { localized(pl: "Hasło nie może zawierać znaków nowej linii.", en: "Password cannot contain line break characters.") }
    static var passwordsDoNotMatch: String { localized(pl: "Nowe hasło i weryfikacja nie są takie same.", en: "New password and verification do not match.") }
    static var passwordMustChange: String { localized(pl: "Nowe hasło musi różnić się od starego.", en: "New password must be different from the current password.") }
    static var passwordTooShort: String { localized(pl: "Użyj co najmniej 8 znaków.", en: "Use at least 8 characters.") }
    static var changing: String { localized(pl: "Zmieniam hasło domenowe...", en: "Changing domain password...") }
    static var successTitle: String { localized(pl: "Hasło zostało zmienione.", en: "Password changed.") }
    static var successRefreshUpdated: String { localized(pl: "Odświeżono status ważności hasła.", en: "Password expiration status has been refreshed.") }
    static var successRefreshUncertain: String { localized(pl: "Hasło zmieniono, ale nie udało się potwierdzić odświeżenia statusu. Sprawdź ponownie za chwilę.", en: "Password was changed, but status refresh could not be confirmed. Check again in a moment.") }
    static var failureTitle: String { localized(pl: "Nie udało się zmienić hasła.", en: "Password change failed.") }
    static var keychainGuidanceBanner: String { localized(pl: "Jeśli login keychain prosi o stare hasło, zsynchronizuj hasło keychain.", en: "If login keychain still asks for the old password, sync the keychain password.") }
    static var keychainInstructions: String { localized(pl: "Instrukcja keychain", en: "Keychain instructions") }
    static var retryKeychainSync: String { localized(pl: "Spróbuj ponownie", en: "Retry") }
    static var keychainSyncSuccess: String { localized(pl: "Hasło pęku kluczy „logowanie” zostało zsynchronizowane.", en: "The \"login\" keychain password has been synchronized.") }
    static var keychainSyncRetrySuccess: String { localized(pl: "Ponowna synchronizacja keychain zakończona powodzeniem.", en: "Keychain retry synchronization succeeded.") }
    static var keychainHelpTitle: String { localized(pl: "Synchronizacja hasła keychain", en: "Keychain password sync") }
    static var keychainHelpSummary: String { localized(pl: "Po zmianie hasła domenowego keychain może nadal używać starego hasła logowania.", en: "After a domain password change, login keychain might still use your previous login password.") }
    static var keychainHelpStep1: String { localized(pl: "Otwórz aplikację Dostęp do pęku kluczy.", en: "Open Keychain Access.") }
    static var keychainHelpStep2: String { localized(pl: "Wybierz pęk kluczy „logowanie”.", en: "Select the \"login\" keychain.") }
    static var keychainHelpStep3: String { localized(pl: "W menu Edycja wybierz „Zmień hasło pęku kluczy logowanie”.", en: "From the Edit menu, choose \"Change Password for Keychain \\\"login\\\"\".") }
    static var keychainHelpStep4: String { localized(pl: "Podaj stare hasło, a następnie nowe hasło logowania.", en: "Enter the old password first, then the new login password.") }
    static var keychainHelpStep1Numbered: String { localized(pl: "1. Otwórz aplikację Dostęp do pęku kluczy.", en: "1. Open Keychain Access.") }
    static var keychainHelpStep2Numbered: String { localized(pl: "2. Wybierz pęk kluczy „logowanie”.", en: "2. Select the \"login\" keychain.") }
    static var keychainHelpStep3Numbered: String { localized(pl: "3. W menu Edycja wybierz „Zmień hasło pęku kluczy logowanie”.", en: "3. From the Edit menu, choose \"Change Password for Keychain \\\"login\\\"\".") }
    static var keychainHelpStep4Numbered: String { localized(pl: "4. Podaj stare hasło, a następnie nowe hasło logowania.", en: "4. Enter the old password first, then the new login password.") }
    static var veryWeak: String { localized(pl: "Bardzo słabe", en: "Very weak") }
    static var weak: String { localized(pl: "Słabe", en: "Weak") }
    static var fair: String { localized(pl: "Średnie", en: "Fair") }
    static var strong: String { localized(pl: "Silne", en: "Strong") }
    static var excellent: String { localized(pl: "Bardzo silne", en: "Excellent") }

    static func diagnosticCode(_ code: String) -> String {
        localized(pl: "Kod: \(code)", en: "Code: \(code)")
    }

    fileprivate static func keychainPresentation(
        for error: KeychainPasswordSyncError,
        isRetry: Bool
    ) -> PasswordKeychainPresentation {
        let diagnosticCode = error.diagnosticCode
        switch error {
        case .defaultKeychainUnavailable:
            return PasswordKeychainPresentation(
                title: localized(pl: "Brak domyślnego pęku kluczy.", en: "Default keychain is unavailable."),
                message: localized(pl: "Nie znaleziono pęku kluczy „logowanie” lub jest niedostępny.", en: "The \"login\" keychain was not found or is unavailable."),
                code: diagnosticCode,
                kind: .error,
                canRetry: true
            )
        case .currentPasswordInvalid:
            return PasswordKeychainPresentation(
                title: localized(pl: "Nie udało się zsynchronizować keychain.", en: "Keychain synchronization failed."),
                message: localized(pl: "Stare hasło do pęku kluczy jest nieprawidłowe.", en: "The previous keychain password is invalid."),
                code: diagnosticCode,
                kind: .error,
                canRetry: true
            )
        case .interactionNotAllowed:
            return PasswordKeychainPresentation(
                title: localized(pl: "Interakcja z keychain jest zablokowana.", en: "Keychain interaction is blocked."),
                message: localized(pl: "Odblokuj sesję użytkownika i spróbuj ponownie.", en: "Unlock the user session and try again."),
                code: diagnosticCode,
                kind: .warning,
                canRetry: true
            )
        case .keychainLockedOrUnavailable:
            return PasswordKeychainPresentation(
                title: localized(pl: "Keychain jest zablokowany lub niedostępny.", en: "Keychain is locked or unavailable."),
                message: localized(pl: "Odblokuj keychain i ponów synchronizację.", en: "Unlock the keychain and retry synchronization."),
                code: diagnosticCode,
                kind: .warning,
                canRetry: true
            )
        case .notAuthorized:
            return PasswordKeychainPresentation(
                title: localized(pl: "Synchronizacja keychain anulowana.", en: "Keychain synchronization was canceled."),
                message: localized(pl: "Użytkownik anulował operację lub brak uprawnień.", en: "The operation was canceled or not authorized."),
                code: diagnosticCode,
                kind: .warning,
                canRetry: true
            )
        case .invalidInputFormat:
            return PasswordKeychainPresentation(
                title: localized(pl: "Nieprawidłowy format hasła.", en: "Invalid password format."),
                message: localized(pl: "Hasło nie może zawierać znaków nowej linii.", en: "Password cannot contain line break characters."),
                code: diagnosticCode,
                kind: .error,
                canRetry: false
            )
        case .operationFailed:
            return PasswordKeychainPresentation(
                title: localized(pl: "Błąd synchronizacji keychain.", en: "Keychain synchronization error."),
                message: isRetry
                    ? localized(pl: "Ponowna synchronizacja nie powiodła się.", en: "Retry synchronization failed.")
                    : localized(pl: "Automatyczna synchronizacja nie powiodła się.", en: "Automatic synchronization failed."),
                code: diagnosticCode,
                kind: .error,
                canRetry: true
            )
        case .timeout:
            return PasswordKeychainPresentation(
                title: localized(pl: "Synchronizacja keychain przekroczyła limit czasu.", en: "Keychain synchronization timed out."),
                message: localized(pl: "Operacja trwała zbyt długo. Spróbuj ponownie.", en: "The operation took too long. Try again."),
                code: diagnosticCode,
                kind: .warning,
                canRetry: true
            )
        case let .unknown(_, message):
            return PasswordKeychainPresentation(
                title: localized(pl: "Nieznany błąd keychain.", en: "Unknown keychain error."),
                message: localized(pl: "Synchronizacja keychain nie powiodła się: \(message)", en: "Keychain synchronization failed: \(message)"),
                code: diagnosticCode,
                kind: .error,
                canRetry: true
            )
        }
    }

    fileprivate static func presentation(
        for error: PasswordChangeError,
        likelyRecentChangePolicy: Bool = false
    ) -> PasswordChangeErrorPresentation {
        let diagnosticCode = error.diagnosticCode
        switch error {
        case .activeDirectoryRequired:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(pl: "Ten flow wymaga konta AD/mobile.", en: "This flow requires an AD/mobile account.")
            )
        case .currentPasswordInvalid:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(pl: "Stare hasło jest nieprawidłowe.", en: "Current password is incorrect.")
            )
        case .passwordPolicyFailed:
            if likelyRecentChangePolicy {
                return PasswordChangeErrorPresentation(
                    code: diagnosticCode,
                    message: localized(
                        pl: "Domena odrzuciła zmianę hasła. Hasło było zmienione niedawno, więc prawdopodobnie obowiązuje minimalny czas między zmianami.",
                        en: "The domain rejected the password change. The password was changed recently, so a minimum time between password changes is likely enforced."
                    )
                )
            }
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(
                    pl: "Domena odrzuciła nowe hasło, ale nie wskazała dokładnej reguły. Hasło może naruszać historię haseł, wymagania złożoności lub inną zasadę firmową.",
                    en: "The domain rejected the new password without identifying the exact rule. It might violate password history, complexity requirements, or another company policy."
                )
            )
        case .passwordTooShort:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(
                    pl: "Nowe hasło jest zbyt krótkie według polityki domeny.",
                    en: "The new password is too short according to the domain policy."
                )
            )
        case .passwordTooLong:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(
                    pl: "Nowe hasło jest zbyt długie według polityki domeny.",
                    en: "The new password is too long according to the domain policy."
                )
            )
        case .passwordNeedsLetter:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(
                    pl: "Polityka domeny wymaga, aby nowe hasło zawierało co najmniej jedną literę.",
                    en: "The domain policy requires the new password to contain at least one letter."
                )
            )
        case .passwordNeedsDigit:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(
                    pl: "Polityka domeny wymaga, aby nowe hasło zawierało co najmniej jedną cyfrę.",
                    en: "The domain policy requires the new password to contain at least one digit."
                )
            )
        case .passwordChangeTooSoon:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(pl: "Polityka domeny nie pozwala jeszcze zmienić hasła.", en: "Domain policy does not allow another password change yet.")
            )
        case .domainUnavailable:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(pl: "Brak połączenia z domeną. Połącz VPN lub sieć firmową.", en: "Domain is unavailable. Connect VPN or the corporate network.")
            )
        case .accountNotFound:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(pl: "Nie znaleziono konta AD/mobile dla tego użytkownika.", en: "No AD/mobile account was found for this user.")
            )
        case .accountLocked:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(pl: "Konto jest zablokowane lub czasowo zablokowane.", en: "The account is locked or temporarily locked.")
            )
        case .notAuthorized:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(pl: "Brak uprawnień do zmiany hasła dla tego konta.", en: "Not authorized to change this account password.")
            )
        case .methodNotSupported:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(pl: "Ten węzeł domeny nie wspiera zmiany hasła przez OpenDirectory.", en: "This domain node does not support OpenDirectory password change.")
            )
        case .operationFailed:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(pl: "Zmiana hasła nie powiodła się.", en: "Password change failed.")
            )
        case let .unknown(_, message):
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(pl: "Zmiana hasła nie powiodła się: \(message)", en: "Password change failed: \(message)")
            )
        @unknown default:
            return PasswordChangeErrorPresentation(
                code: diagnosticCode,
                message: localized(pl: "Zmiana hasła nie powiodła się.", en: "Password change failed.")
            )
        }
    }

    private static func localized(pl: String, en: String) -> String {
        LanguageSettings.currentLanguageCode().hasPrefix("pl") ? pl : en
    }
}
