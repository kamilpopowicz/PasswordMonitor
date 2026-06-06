//
//  PasswordChangeManager.swift
//  PasswordMonitorCore
//
//  Created by Codex on 21/05/2026.
//

import Foundation
import OpenDirectory
import Security

public enum PasswordChangeError: Error, Equatable {
    case activeDirectoryRequired
    case currentPasswordInvalid
    case passwordPolicyFailed
    case passwordTooShort
    case passwordTooLong
    case passwordNeedsLetter
    case passwordNeedsDigit
    case passwordChangeTooSoon
    case domainUnavailable
    case accountNotFound
    case accountLocked
    case notAuthorized
    case methodNotSupported
    case operationFailed
    case unknown(code: Int, message: String)
}

public struct PasswordChangeOutcome: Equatable {
    public let username: String
    public let domain: String

    public init(username: String, domain: String) {
        self.username = username
        self.domain = domain
    }
}

public enum KeychainPasswordSyncError: Error, Equatable {
    case defaultKeychainUnavailable
    case currentPasswordInvalid
    case interactionNotAllowed
    case keychainLockedOrUnavailable
    case notAuthorized
    case invalidInputFormat
    case timeout
    case operationFailed
    case unknown(status: Int32, message: String)
}

public struct KeychainPasswordSyncOutcome: Equatable {
    public let keychainLabel: String

    public init(keychainLabel: String) {
        self.keychainLabel = keychainLabel
    }
}

public final class PasswordChangeManager: @unchecked Sendable {
    public typealias DomainResolver = @Sendable () -> String?
    public typealias PasswordChanger = @Sendable (_ username: String, _ currentPassword: String, _ newPassword: String) throws -> Void

    private let currentDomain: DomainResolver
    private let passwordChanger: PasswordChanger
    private let logger: Logger

    public convenience init() {
        self.init(
            currentDomain: SystemADDomainResolver.currentDomain,
            passwordChanger: Self.changePasswordWithOpenDirectory(username:currentPassword:newPassword:),
            logger: .shared
        )
    }

    init(
        currentDomain: @escaping DomainResolver,
        passwordChanger: @escaping PasswordChanger,
        logger: Logger = .shared
    ) {
        self.currentDomain = currentDomain
        self.passwordChanger = passwordChanger
        self.logger = logger
    }

    public func changePassword(
        username: String = NSUserName(),
        currentPassword: String,
        newPassword: String
    ) async throws -> PasswordChangeOutcome {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            throw PasswordChangeError.accountNotFound
        }

        guard let domain = currentDomain()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !domain.isEmpty else {
            throw PasswordChangeError.activeDirectoryRequired
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.passwordChanger(trimmedUsername, currentPassword, newPassword)
                    self.logger.log("event=password_change result=success")
                    continuation.resume(returning: PasswordChangeOutcome(username: trimmedUsername, domain: domain))
                } catch {
                    let mapped = Self.map(error)
                    self.logger.log(
                        "event=password_change result=failure code=\(mapped.diagnosticCode)",
                        level: .error
                    )
                    continuation.resume(throwing: mapped)
                }
            }
        }
    }

    public static func map(_ error: Error) -> PasswordChangeError {
        if let passwordChangeError = error as? PasswordChangeError {
            return passwordChangeError
        }

        let nsError = error as NSError
        switch nsError.code {
        case odCode(kODErrorCredentialsInvalid):
            return .currentPasswordInvalid
        case odCode(kODErrorCredentialsPasswordQualityFailed):
            return .passwordPolicyFailed
        case odCode(kODErrorCredentialsPasswordTooShort):
            return .passwordTooShort
        case odCode(kODErrorCredentialsPasswordTooLong):
            return .passwordTooLong
        case odCode(kODErrorCredentialsPasswordNeedsLetter):
            return .passwordNeedsLetter
        case odCode(kODErrorCredentialsPasswordNeedsDigit):
            return .passwordNeedsDigit
        case odCode(kODErrorCredentialsPasswordChangeTooSoon):
            return .passwordChangeTooSoon
        case odCode(kODErrorCredentialsServerUnreachable),
             odCode(kODErrorCredentialsServerNotFound),
             odCode(kODErrorCredentialsServerTimeout),
             odCode(kODErrorCredentialsServerCommunicationError),
             odCode(kODErrorNodeConnectionFailed):
            return .domainUnavailable
        case odCode(kODErrorCredentialsAccountNotFound):
            return .accountNotFound
        case odCode(kODErrorCredentialsAccountTemporarilyLocked),
             odCode(kODErrorCredentialsAccountLocked):
            return .accountLocked
        case odCode(kODErrorCredentialsNotAuthorized):
            return .notAuthorized
        case odCode(kODErrorCredentialsMethodNotSupported):
            // Some AD mobile-account nodes report this credential-layer error
            // when the current password is rejected during password change.
            // In this flow the actionable user-facing cause is the same:
            // re-enter the current password before trying domain policy fixes.
            return .currentPasswordInvalid
        case odCode(kODErrorPluginOperationNotSupported):
            return .methodNotSupported
        case odCode(kODErrorCredentialsOperationFailed),
             odCode(kODErrorCredentialsServerError),
             odCode(kODErrorPluginError),
             odCode(kODErrorDaemonError):
            return .operationFailed
        default:
            return .unknown(code: nsError.code, message: nsError.localizedDescription)
        }
    }

    private static func odCode(_ error: ODFrameworkErrors) -> Int {
        Int(error.rawValue)
    }

    private static func changePasswordWithOpenDirectory(
        username: String,
        currentPassword: String,
        newPassword: String
    ) throws {
        let node = try ODNode(session: ODSession.default(), type: UInt32(kODNodeTypeAuthentication))
        let record = try node.record(
            withRecordType: kODRecordTypeUsers,
            name: username,
            attributes: nil
        )
        try record.changePassword(currentPassword, toPassword: newPassword)
    }
}

public final class KeychainPasswordSyncManager: @unchecked Sendable {
    // Security contract for keychain sync:
    // Allowed operations: read/status, unlock check, password change (old -> new).
    // Forbidden operations: delete/reset/create/replace keychain, set default keychain,
    // and modifying keychain search lists.
    //
    // Security debt / rationale (P3):
    // - The current implementation relies on legacy SecKeychain APIs plus
    //   /usr/bin/security set-keychain-password for login keychain password sync.
    // - This is intentional for now: we need deterministic old->new sync behavior
    //   without destructive operations on keychain data.
    // - Deprecated SecKeychain APIs are confined to this manager so they can be
    //   replaced in one place.
    // - Target architecture for "best possible" isolation is a short-lived helper
    //   process boundary where secrets do not live in the UI process longer than
    //   a single request lifecycle.
    public typealias DefaultKeychainProvider = @Sendable () -> (keychain: SecKeychain?, status: Int32)
    public typealias KeychainUnlocker = @Sendable (_ keychain: SecKeychain?, _ currentPassword: String) -> Int32
    public typealias PasswordChanger = @Sendable (_ keychain: SecKeychain?, _ currentPassword: String, _ newPassword: String) -> Int32

    private let defaultKeychainProvider: DefaultKeychainProvider
    private let keychainUnlocker: KeychainUnlocker
    private let passwordChanger: PasswordChanger
    private let logger: Logger
    private static let keychainSyncTimeoutStatus: Int32 = -9_900_008
    private static let securityToolTimeout: TimeInterval = 10

    public convenience init() {
        self.init(
            defaultKeychainProvider: Self.copyPreferredDefaultKeychain,
            keychainUnlocker: Self.preflightUnlockKeychain,
            passwordChanger: Self.changeKeychainPassword,
            logger: .shared
        )
    }

    init(
        defaultKeychainProvider: @escaping DefaultKeychainProvider,
        keychainUnlocker: @escaping KeychainUnlocker,
        passwordChanger: @escaping PasswordChanger,
        logger: Logger = .shared
    ) {
        self.defaultKeychainProvider = defaultKeychainProvider
        self.keychainUnlocker = keychainUnlocker
        self.passwordChanger = passwordChanger
        self.logger = logger
    }

    convenience init(
        defaultKeychainProvider: @escaping DefaultKeychainProvider,
        passwordChanger: @escaping PasswordChanger
    ) {
        self.init(
            defaultKeychainProvider: defaultKeychainProvider,
            keychainUnlocker: Self.preflightUnlockKeychain,
            passwordChanger: passwordChanger,
            logger: .shared
        )
    }

    public func syncLoginKeychainPassword(
        currentPassword: String,
        newPassword: String
    ) async throws -> KeychainPasswordSyncOutcome {
        if Self.containsUnsupportedLineBreak(currentPassword) || Self.containsUnsupportedLineBreak(newPassword) {
            throw KeychainPasswordSyncError.invalidInputFormat
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                switch self.defaultKeychainProvider() {
                case let (_, status) where status != errSecSuccess:
                    let mapped = Self.map(status: status)
                    self.logger.log(
                        "event=keychain_sync phase=resolve result=failure code=\(mapped.diagnosticCode)",
                        level: .error
                    )
                    continuation.resume(throwing: mapped)
                case let (keychain, _):
                    let unlockStatus = self.keychainUnlocker(keychain, currentPassword)
                    guard unlockStatus == errSecSuccess else {
                        let mapped = Self.map(status: unlockStatus)
                        self.logger.log(
                            "event=keychain_sync phase=preflight result=failure code=\(mapped.diagnosticCode)",
                            level: .error
                        )
                        continuation.resume(throwing: mapped)
                        return
                    }

                    let status = self.passwordChanger(keychain, currentPassword, newPassword)
                    guard status == errSecSuccess else {
                        let mapped = Self.map(status: status)
                        self.logger.log(
                            "event=keychain_sync phase=change result=failure code=\(mapped.diagnosticCode)",
                            level: .error
                        )
                        continuation.resume(throwing: mapped)
                        return
                    }

                    self.logger.log("event=keychain_sync result=success")
                    continuation.resume(returning: KeychainPasswordSyncOutcome(keychainLabel: "login"))
                }
            }
        }
    }

    public static func map(status: Int32) -> KeychainPasswordSyncError {
        switch status {
        case keychainSyncTimeoutStatus:
            return .timeout
        case errSecNoDefaultKeychain, errSecInvalidKeychain, errSecNoSuchKeychain:
            return .defaultKeychainUnavailable
        case errSecAuthFailed:
            return .currentPasswordInvalid
        case errSecInteractionNotAllowed:
            return .interactionNotAllowed
        case errSecNotAvailable, errSecReadOnly:
            return .keychainLockedOrUnavailable
        case errSecUserCanceled:
            return .notAuthorized
        case errSecIO, errSecOpWr, errSecParam, errSecWrPerm, errSecAllocate, errSecInternalComponent, errSecInternalError:
            return .operationFailed
        default:
            let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "Unknown Security framework error"
            return .unknown(status: status, message: message)
        }
    }

    static func isAllowedSecurityToolArguments(_ arguments: [String]) -> Bool {
        arguments.count == 2 && arguments[0] == "set-keychain-password"
    }

    private static func copyPreferredDefaultKeychain() -> (keychain: SecKeychain?, status: Int32) {
        var userKeychain: SecKeychain?
        let userStatus = SecKeychainCopyDomainDefault(.user, &userKeychain)
        if userStatus == errSecSuccess, let userKeychain {
            return (keychain: userKeychain, status: errSecSuccess)
        }

        var defaultKeychain: SecKeychain?
        let defaultStatus = SecKeychainCopyDefault(&defaultKeychain)
        if defaultStatus == errSecSuccess, let defaultKeychain {
            return (keychain: defaultKeychain, status: errSecSuccess)
        }

        if userStatus != errSecSuccess {
            return (keychain: nil, status: userStatus)
        }
        return (keychain: nil, status: defaultStatus)
    }

    private static func preflightUnlockKeychain(
        keychain: SecKeychain?,
        currentPassword: String
    ) -> Int32 {
        guard let data = currentPassword.data(using: .utf8) else {
            return errSecParam
        }
        return data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            return SecKeychainUnlock(
                keychain,
                UInt32(data.count),
                bytes,
                true
            )
        }
    }

    private static func changeKeychainPassword(
        keychain: SecKeychain?,
        currentPassword: String,
        newPassword: String
    ) -> Int32 {
        guard let keychainPath = resolveDefaultKeychainPath(keychain) else {
            return errSecNoDefaultKeychain
        }
        return runSecuritySetKeychainPassword(
            keychainPath: keychainPath,
            currentPassword: currentPassword,
            newPassword: newPassword
        )
    }

    private static func resolveDefaultKeychainPath(_ keychain: SecKeychain?) -> String? {
        guard let keychain else { return nil }

        var pathLength: UInt32 = 4096
        var pathBuffer = [CChar](repeating: 0, count: Int(pathLength))
        let status = SecKeychainGetPath(keychain, &pathLength, &pathBuffer)
        guard status == errSecSuccess else {
            return nil
        }
        return String(cString: pathBuffer)
    }

    private static func runSecuritySetKeychainPassword(
        keychainPath: String,
        currentPassword: String,
        newPassword: String
    ) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        let arguments = ["set-keychain-password", keychainPath]
        guard isAllowedSecurityToolArguments(arguments) else {
            return errSecParam
        }
        process.arguments = arguments

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let completionSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            completionSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return errSecNotAvailable
        }

        let interactiveInput = "\(currentPassword)\n\(newPassword)\n\(newPassword)\n"
        if let inputData = interactiveInput.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(inputData)
        }
        inputPipe.fileHandleForWriting.closeFile()

        let waitResult = completionSemaphore.wait(timeout: .now() + securityToolTimeout)
        if waitResult == .timedOut {
            process.terminate()
            _ = completionSemaphore.wait(timeout: .now() + 1)
            if process.isRunning {
                process.interrupt()
            }
            return keychainSyncTimeoutStatus
        }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            return mapSecurityToolFailure(
                output: output,
                terminationStatus: process.terminationStatus
            )
        }

        return errSecSuccess
    }

    private static func mapSecurityToolFailure(
        output: String,
        terminationStatus: Int32
    ) -> Int32 {
        if terminationStatus == 130 || terminationStatus == 143 {
            return errSecUserCanceled
        }

        let normalized = output.lowercased()

        if normalized.contains("authfailed") || normalized.contains("authentication failed") {
            return errSecAuthFailed
        }
        if normalized.contains("interaction not allowed") || normalized.contains("user interaction is not allowed") {
            return errSecInteractionNotAllowed
        }
        if normalized.contains("no default keychain") || normalized.contains("no such keychain") {
            return errSecNoDefaultKeychain
        }
        if normalized.contains("cancel") {
            return errSecUserCanceled
        }
        if normalized.contains("read only") {
            return errSecReadOnly
        }

        return errSecInternalComponent
    }

    private static func containsUnsupportedLineBreak(_ value: String) -> Bool {
        value.contains("\n") || value.contains("\r")
    }
}

public extension PasswordChangeError {
    var diagnosticCode: String {
        switch self {
        case .activeDirectoryRequired:
            return "PM-PWD-010"
        case .currentPasswordInvalid:
            return "PM-PWD-001"
        case .passwordPolicyFailed:
            return "PM-PWD-002"
        case .passwordTooShort:
            return "PM-PWD-012"
        case .passwordTooLong:
            return "PM-PWD-013"
        case .passwordNeedsLetter:
            return "PM-PWD-014"
        case .passwordNeedsDigit:
            return "PM-PWD-015"
        case .passwordChangeTooSoon:
            return "PM-PWD-004"
        case .domainUnavailable:
            return "PM-PWD-003"
        case .accountNotFound:
            return "PM-PWD-005"
        case .accountLocked:
            return "PM-PWD-006"
        case .notAuthorized:
            return "PM-PWD-007"
        case .methodNotSupported:
            return "PM-PWD-008"
        case .operationFailed:
            return "PM-PWD-009"
        case .unknown:
            return "PM-PWD-011"
        }
    }
}

public extension KeychainPasswordSyncError {
    var diagnosticCode: String {
        switch self {
        case .defaultKeychainUnavailable:
            return "PM-KCH-001"
        case .currentPasswordInvalid:
            return "PM-KCH-002"
        case .interactionNotAllowed:
            return "PM-KCH-003"
        case .keychainLockedOrUnavailable:
            return "PM-KCH-004"
        case .notAuthorized:
            return "PM-KCH-005"
        case .invalidInputFormat, .operationFailed:
            return "PM-KCH-006"
        case .timeout:
            return "PM-KCH-008"
        case .unknown:
            return "PM-KCH-007"
        }
    }
}
