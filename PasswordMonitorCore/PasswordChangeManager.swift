//
//  PasswordChangeManager.swift
//  PasswordMonitorCore
//
//  Created by Codex on 21/05/2026.
//

import Foundation
import OpenDirectory

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

public final class PasswordChangeManager: @unchecked Sendable {
    public typealias DomainResolver = @Sendable () -> String?
    public typealias PasswordChanger = @Sendable (_ username: String, _ currentPassword: String, _ newPassword: String) throws -> Void

    private let currentDomain: DomainResolver
    private let passwordChanger: PasswordChanger

    public convenience init() {
        self.init(
            currentDomain: SystemADDomainResolver.currentDomain,
            passwordChanger: Self.changePasswordWithOpenDirectory(username:currentPassword:newPassword:)
        )
    }

    init(
        currentDomain: @escaping DomainResolver,
        passwordChanger: @escaping PasswordChanger
    ) {
        self.currentDomain = currentDomain
        self.passwordChanger = passwordChanger
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
                    Logger.shared.log("Password change succeeded via OpenDirectory for user=\(trimmedUsername), domain=\(domain)")
                    continuation.resume(returning: PasswordChangeOutcome(username: trimmedUsername, domain: domain))
                } catch {
                    let mapped = Self.map(error)
                    Logger.shared.log("Password change failed via OpenDirectory for user=\(trimmedUsername), domain=\(domain), error=\(mapped.safeLogDescription)", level: .error)
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
        case odCode(kODErrorCredentialsMethodNotSupported),
             odCode(kODErrorPluginOperationNotSupported):
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

private extension PasswordChangeError {
    var safeLogDescription: String {
        switch self {
        case .activeDirectoryRequired:
            return "activeDirectoryRequired"
        case .currentPasswordInvalid:
            return "currentPasswordInvalid"
        case .passwordPolicyFailed:
            return "passwordPolicyFailed"
        case .passwordTooShort:
            return "passwordTooShort"
        case .passwordTooLong:
            return "passwordTooLong"
        case .passwordNeedsLetter:
            return "passwordNeedsLetter"
        case .passwordNeedsDigit:
            return "passwordNeedsDigit"
        case .passwordChangeTooSoon:
            return "passwordChangeTooSoon"
        case .domainUnavailable:
            return "domainUnavailable"
        case .accountNotFound:
            return "accountNotFound"
        case .accountLocked:
            return "accountLocked"
        case .notAuthorized:
            return "notAuthorized"
        case .methodNotSupported:
            return "methodNotSupported"
        case .operationFailed:
            return "operationFailed"
        case let .unknown(code, _):
            return "unknown(\(code))"
        }
    }
}
