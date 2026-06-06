//
//  PasswordMonitorCoreTests.swift
//  PasswordMonitorCoreTests
//
//  Created by Kamil Popowicz on 19/02/2026.
//

import XCTest
import CryptoKit
import OpenDirectory
import Security
@testable import PasswordMonitorCore

final class PasswordMonitorCoreTests: XCTestCase {
    private let cacheKey = "cached_password_info"
    private let sharedDefaults = UserDefaults(suiteName: "popo.PasswordMonitor")

    override func setUp() {
        super.setUp()
        clearNotificationClaims()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        sharedDefaults?.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: "cached_password_info_last_fetch_cache")
        sharedDefaults?.removeObject(forKey: "cached_password_info_last_fetch_cache")
        UserDefaults.standard.removeObject(forKey: "warning_threshold")
        UserDefaults.standard.removeObject(forKey: "quiet_hours_start")
        UserDefaults.standard.removeObject(forKey: "quiet_hours_end")
        clearNotificationClaims()
        super.tearDown()
    }

    private func clearNotificationClaims() {
        let store = NotificationStateStore.shared
        store.clearNotificationDeliveryClaim()
        store.clearScheduledNotificationEventClaim()
        store.clearHelperTriggerClaim()
    }

    private func smbPasswordLastSetOutput(for date: Date) -> String {
        let windowsFileTime = Int64(date.timeIntervalSince1970 * 10_000_000) + 116_444_736_000_000_000
        return "SMBPasswordLastSet: \(windowsFileTime)\n"
    }

    private func localPasswordLastSetOutput(for date: Date) -> String {
        return "passwordLastSetTime: \(date.timeIntervalSince1970)\n"
    }

    private func posixPermissions(at url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }

    func testPasswordCacheSaveLoadMarksFromCache() {
        let expiryDate = Date().addingTimeInterval(10 * 24 * 3600 + 3600)
        let info = PasswordInfo(
            lastSetDate: Date(timeIntervalSince1970: 0),
            daysUntilExpiration: 7,
            expiryDate: expiryDate,
            isFromCache: false
        )

        PasswordCache.shared.save(info)
        PasswordCache.shared.markLastFetchWasCache(true)

        let loaded = PasswordCache.shared.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.daysUntilExpiration, 10)
        XCTAssertEqual(loaded?.expiryDate.timeIntervalSince1970 ?? 0, expiryDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(loaded?.lastSetDate, Date(timeIntervalSince1970: 0))
        XCTAssertTrue(loaded?.isFromCache ?? false)
        XCTAssertNotNil(sharedDefaults?.data(forKey: cacheKey))
    }

    func testPasswordExpirationMathUsesSameDayCountAsAlertLogic() {
        let now = Date(timeIntervalSince1970: 0)
        let expirationDate = now.addingTimeInterval(6 * 24 * 3600 + 23 * 3600)

        let daysRemaining = PasswordExpirationMath.daysRemaining(until: expirationDate, from: now)
        XCTAssertEqual(daysRemaining, 6)
    }

    func testPasswordCacheLoadInvalidDataReturnsNil() {
        UserDefaults.standard.set(Data([0x00, 0x01, 0x02]), forKey: cacheKey)
        let loaded = PasswordCache.shared.load()
        XCTAssertNil(loaded)
    }

    func testPasswordStrengthAnalyzerRejectsCommonPassword() {
        let result = PasswordStrengthAnalyzer.analyze("password123")

        XCTAssertEqual(result.level, .veryWeak)
        XCTAssertTrue(result.feedback.contains("Avoid common passwords."))
    }

    func testPasswordStrengthAnalyzerRewardsLongPassphrase() {
        let result = PasswordStrengthAnalyzer.analyze("correct river battery sunrise")

        XCTAssertGreaterThanOrEqual(result.score, PasswordStrengthLevel.strong.rawValue)
    }

    func testPasswordStrengthAnalyzerPenalizesUserContext() {
        let result = PasswordStrengthAnalyzer.analyze(
            "KamilPassword2026!",
            userInputs: ["kamil"]
        )

        XCTAssertTrue(result.feedback.contains("Avoid using your name, domain, or app name."))
    }

    func testPasswordChangeErrorMappingHandlesInvalidCredentials() {
        let error = NSError(domain: ODFrameworkErrorDomain, code: Int(kODErrorCredentialsInvalid.rawValue))

        XCTAssertEqual(PasswordChangeManager.map(error), .currentPasswordInvalid)
    }

    func testPasswordChangeErrorMappingTreatsCredentialMethodNotSupportedAsCurrentPasswordRejected() {
        let error = NSError(domain: ODFrameworkErrorDomain, code: Int(kODErrorCredentialsMethodNotSupported.rawValue))

        XCTAssertEqual(PasswordChangeManager.map(error), .currentPasswordInvalid)
    }

    func testPasswordChangeErrorMappingKeepsPluginOperationNotSupportedSeparate() {
        let error = NSError(domain: ODFrameworkErrorDomain, code: Int(kODErrorPluginOperationNotSupported.rawValue))

        XCTAssertEqual(PasswordChangeManager.map(error), .methodNotSupported)
    }

    func testPasswordChangeErrorMappingHandlesDomainConnectivity() {
        let error = NSError(domain: ODFrameworkErrorDomain, code: Int(kODErrorCredentialsServerUnreachable.rawValue))

        XCTAssertEqual(PasswordChangeManager.map(error), .domainUnavailable)
    }

    func testPasswordChangeErrorMappingDistinguishesDomainPolicyFailures() {
        let mappings: [(ODFrameworkErrors, PasswordChangeError)] = [
            (kODErrorCredentialsPasswordQualityFailed, .passwordPolicyFailed),
            (kODErrorCredentialsPasswordTooShort, .passwordTooShort),
            (kODErrorCredentialsPasswordTooLong, .passwordTooLong),
            (kODErrorCredentialsPasswordNeedsLetter, .passwordNeedsLetter),
            (kODErrorCredentialsPasswordNeedsDigit, .passwordNeedsDigit),
            (kODErrorCredentialsPasswordChangeTooSoon, .passwordChangeTooSoon)
        ]

        for (odError, expected) in mappings {
            let error = NSError(domain: ODFrameworkErrorDomain, code: Int(odError.rawValue))
            XCTAssertEqual(PasswordChangeManager.map(error), expected)
        }
    }

    func testPasswordChangeErrorsProvideStableDiagnosticCodes() {
        XCTAssertEqual(PasswordChangeError.currentPasswordInvalid.diagnosticCode, "PM-PWD-001")
        XCTAssertEqual(PasswordChangeError.passwordPolicyFailed.diagnosticCode, "PM-PWD-002")
        XCTAssertEqual(PasswordChangeError.passwordTooShort.diagnosticCode, "PM-PWD-012")
        XCTAssertEqual(PasswordChangeError.passwordTooLong.diagnosticCode, "PM-PWD-013")
        XCTAssertEqual(PasswordChangeError.passwordNeedsLetter.diagnosticCode, "PM-PWD-014")
        XCTAssertEqual(PasswordChangeError.passwordNeedsDigit.diagnosticCode, "PM-PWD-015")
        XCTAssertEqual(PasswordChangeError.domainUnavailable.diagnosticCode, "PM-PWD-003")
        XCTAssertEqual(PasswordChangeError.methodNotSupported.diagnosticCode, "PM-PWD-008")
        XCTAssertEqual(PasswordChangeError.unknown(code: 42, message: "details").diagnosticCode, "PM-PWD-011")
    }

    func testKeychainPasswordSyncErrorMappingHandlesInvalidCredentials() {
        XCTAssertEqual(
            KeychainPasswordSyncManager.map(status: errSecAuthFailed),
            .currentPasswordInvalid
        )
    }

    func testKeychainPasswordSyncErrorMappingHandlesMissingDefaultKeychain() {
        XCTAssertEqual(
            KeychainPasswordSyncManager.map(status: errSecNoDefaultKeychain),
            .defaultKeychainUnavailable
        )
    }

    func testKeychainPasswordSyncErrorMappingHandlesTimeout() {
        XCTAssertEqual(
            KeychainPasswordSyncManager.map(status: -9_900_008),
            .timeout
        )
    }

    func testKeychainPasswordSyncErrorsProvideStableDiagnosticCodes() {
        XCTAssertEqual(KeychainPasswordSyncError.defaultKeychainUnavailable.diagnosticCode, "PM-KCH-001")
        XCTAssertEqual(KeychainPasswordSyncError.currentPasswordInvalid.diagnosticCode, "PM-KCH-002")
        XCTAssertEqual(KeychainPasswordSyncError.timeout.diagnosticCode, "PM-KCH-008")
        XCTAssertEqual(KeychainPasswordSyncError.unknown(status: -1, message: "details").diagnosticCode, "PM-KCH-007")
    }

    func testLoggerCreatesAndRepairsPrivateLogPermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasswordMonitorLoggerPermissions-\(UUID().uuidString)", isDirectory: true)
        let logURL = root.appendingPathComponent("test.log")
        let rotatedURL = root.appendingPathComponent("test.log.1")
        let lockURL = root.appendingPathComponent("test.log.lock")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: logURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: logURL.path)

        let logger = Logger(fileURL: logURL, maxBytes: 80)
        logger.log(String(repeating: "x", count: 100))

        XCTAssertEqual(posixPermissions(at: logURL), 0o600)
        XCTAssertEqual(posixPermissions(at: rotatedURL), 0o600)
        XCTAssertEqual(posixPermissions(at: lockURL), 0o600)
    }

    func testLoggerConcurrentWritersProduceCompleteUTF8WithoutNULBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasswordMonitorLoggerConcurrent-\(UUID().uuidString)", isDirectory: true)
        let logURL = root.appendingPathComponent("test.log")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let firstLogger = Logger(fileURL: logURL, maxBytes: 1_000_000)
        let secondLogger = Logger(fileURL: logURL, maxBytes: 1_000_000)

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let logger = index.isMultiple(of: 2) ? firstLogger : secondLogger
            logger.log("concurrent-entry-\(index)")
        }

        let data = try Data(contentsOf: logURL)
        let content = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(data.contains(0))
        XCTAssertEqual(content.split(separator: "\n").count, 100)
        for index in 0..<100 {
            XCTAssertTrue(content.contains("concurrent-entry-\(index)"))
        }
    }

    func testLoggerSanitizesControlCharactersAndPreventsLineInjection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasswordMonitorLoggerControlCharacters-\(UUID().uuidString)", isDirectory: true)
        let logURL = root.appendingPathComponent("test.log")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let logger = Logger(fileURL: logURL, maxBytes: 1_000_000)

        logger.log("before\u{0}middle\nafter\rfinal")

        let data = try Data(contentsOf: logURL)
        let content = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(data.contains(0))
        XCTAssertEqual(content.split(separator: "\n").count, 1)
        XCTAssertTrue(content.contains("before\\u{0}middle\\nafter\\rfinal"))
    }

    func testLoggerClearUsesSharedSafeWriter() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasswordMonitorLoggerClear-\(UUID().uuidString)", isDirectory: true)
        let logURL = root.appendingPathComponent("test.log")
        let rotatedURL = root.appendingPathComponent("test.log.1")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let logger = Logger(fileURL: logURL, maxBytes: 1_000_000)
        logger.log("before-clear")
        try Data("old-rotated-data".utf8).write(to: rotatedURL)

        XCTAssertTrue(logger.clear())
        XCTAssertEqual(logger.readContents(), "")
        XCTAssertEqual(posixPermissions(at: logURL), 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rotatedURL.path))
    }

    func testLoggerFailsClosedWhenInterprocessLockCannotBeCreated() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasswordMonitorLoggerMissingParent-\(UUID().uuidString)", isDirectory: true)
        let logURL = root.appendingPathComponent("missing/test.log")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let logger = Logger(fileURL: logURL, maxBytes: 1_000_000)

        logger.log("must-not-be-written-without-lock")

        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
        XCTAssertEqual(logger.readContents(), "")
        XCTAssertFalse(logger.clear())
    }

    func testPasswordAndKeychainFlowsNeverLogProvidedSecrets() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasswordMonitorLoggerSecrets-\(UUID().uuidString)", isDirectory: true)
        let logURL = root.appendingPathComponent("test.log")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let logger = Logger(fileURL: logURL, maxBytes: 1_000_000)
        let currentSecret = "UniqueCurrentSecret!2026"
        let newSecret = "UniqueNewSecret!2026"

        let passwordManager = PasswordChangeManager(
            currentDomain: { "example.test" },
            passwordChanger: { _, _, _ in },
            logger: logger
        )
        _ = try await passwordManager.changePassword(
            username: "tester",
            currentPassword: currentSecret,
            newPassword: newSecret
        )

        let keychainManager = KeychainPasswordSyncManager(
            defaultKeychainProvider: { (keychain: nil, status: errSecSuccess) },
            keychainUnlocker: { _, _ in errSecSuccess },
            passwordChanger: { _, _, _ in errSecSuccess },
            logger: logger
        )
        _ = try await keychainManager.syncLoginKeychainPassword(
            currentPassword: currentSecret,
            newPassword: newSecret
        )

        let content = logger.readContents()
        XCTAssertFalse(content.contains(currentSecret))
        XCTAssertFalse(content.contains(newSecret))
        XCTAssertTrue(content.contains("event=password_change result=success"))
        XCTAssertTrue(content.contains("event=keychain_sync result=success"))
    }

    func testKeychainPasswordSyncRejectsLineBreakInputBeforeAnySideEffects() async {
        var didCallProvider = false
        var didCallPasswordChanger = false

        let manager = KeychainPasswordSyncManager(
            defaultKeychainProvider: {
                didCallProvider = true
                return (keychain: nil, status: errSecSuccess)
            },
            keychainUnlocker: { _, _ in
                errSecSuccess
            },
            passwordChanger: { _, _, _ in
                didCallPasswordChanger = true
                return errSecSuccess
            }
        )

        do {
            _ = try await manager.syncLoginKeychainPassword(
                currentPassword: "old\npass",
                newPassword: "new-pass"
            )
            XCTFail("Expected invalidInputFormat error")
        } catch let error as KeychainPasswordSyncError {
            XCTAssertEqual(error, .invalidInputFormat)
            XCTAssertFalse(didCallProvider)
            XCTAssertFalse(didCallPasswordChanger)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testKeychainPasswordSyncAllowsOnlySetPasswordSecurityArguments() {
        XCTAssertTrue(
            KeychainPasswordSyncManager.isAllowedSecurityToolArguments(
                ["set-keychain-password", "/Users/test/Library/Keychains/login.keychain-db"]
            )
        )
        XCTAssertFalse(
            KeychainPasswordSyncManager.isAllowedSecurityToolArguments(
                ["delete-keychain", "/Users/test/Library/Keychains/login.keychain-db"]
            )
        )
    }

    func testKeychainPasswordSyncManagerReturnsSuccessForMockedAdapter() async throws {
        let manager = KeychainPasswordSyncManager(
            defaultKeychainProvider: {
                (keychain: nil, status: errSecSuccess)
            },
            keychainUnlocker: { _, _ in
                errSecSuccess
            },
            passwordChanger: { _, _, _ in
                errSecSuccess
            }
        )

        let outcome = try await manager.syncLoginKeychainPassword(
            currentPassword: "old-pass",
            newPassword: "new-pass"
        )

        XCTAssertEqual(outcome.keychainLabel, "login")
    }

    func testKeychainPasswordSyncManagerMapsChangerFailure() async {
        let manager = KeychainPasswordSyncManager(
            defaultKeychainProvider: {
                (keychain: nil, status: errSecSuccess)
            },
            keychainUnlocker: { _, _ in
                errSecSuccess
            },
            passwordChanger: { _, _, _ in
                errSecInteractionNotAllowed
            }
        )

        do {
            _ = try await manager.syncLoginKeychainPassword(
                currentPassword: "old-pass",
                newPassword: "new-pass"
            )
            XCTFail("Expected interactionNotAllowed error")
        } catch let error as KeychainPasswordSyncError {
            XCTAssertEqual(error, .interactionNotAllowed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testKeychainPasswordSyncManagerMapsPreflightUnlockFailureAndSkipsChange() async {
        var didRunPasswordChange = false
        let manager = KeychainPasswordSyncManager(
            defaultKeychainProvider: {
                (keychain: nil, status: errSecSuccess)
            },
            keychainUnlocker: { _, _ in
                errSecAuthFailed
            },
            passwordChanger: { _, _, _ in
                didRunPasswordChange = true
                return errSecSuccess
            }
        )

        do {
            _ = try await manager.syncLoginKeychainPassword(
                currentPassword: "old-pass",
                newPassword: "new-pass"
            )
            XCTFail("Expected currentPasswordInvalid error")
        } catch let error as KeychainPasswordSyncError {
            XCTAssertEqual(error, .currentPasswordInvalid)
            XCTAssertFalse(didRunPasswordChange)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testParseSMBPasswordLastSetEpoch() throws {
        let output = "SMBPasswordLastSet: 116444736000000000\n"
        let date = try ActiveDirectoryManager.parseSMBPasswordLastSet(from: output)
        XCTAssertEqual(date, Date(timeIntervalSince1970: 0))
    }

    func testParseSMBPasswordLastSetInvalid() {
        XCTAssertThrowsError(try ActiveDirectoryManager.parseSMBPasswordLastSet(from: "nope"))
    }

    func testParseSMBPasswordLastSetSelectsLatestWhenMultipleLines() throws {
        let output = """
        SMBPasswordLastSet: 116444736000000000
        SMBPasswordLastSet: 116444736100000000
        """
        let date = try ActiveDirectoryManager.parseSMBPasswordLastSet(from: output)
        XCTAssertEqual(date, Date(timeIntervalSince1970: 10))
    }

    func testSystemADDomainResolverParsesDomainFromOutput() {
        let output = """
        Active Directory Domain = corp.example.com
        Active Directory Forest = CORP.EXAMPLE.COM
        """

        XCTAssertEqual(SystemADDomainResolver.parseDomain(from: output), "corp.example.com")
    }

    func testSystemADDomainResolverReturnsNilForMissingDomain() {
        let output = "Some unrelated configuration"
        XCTAssertNil(SystemADDomainResolver.parseDomain(from: output))
    }

    func testSystemADDomainResolverMatchesShortNodeNameFromFQDN() {
        let nodes = ["EXAMPLE", "OTHER"]
        XCTAssertEqual(
            SystemADDomainResolver.matchingNode(for: "example.local", nodes: nodes),
            "EXAMPLE"
        )
    }

    func testSystemADDomainResolverReturnsNilWhenNodeListDoesNotContainDomain() {
        let nodes = ["EXAMPLE"]
        XCTAssertNil(
            SystemADDomainResolver.matchingNode(for: "unknown.domain", nodes: nodes)
        )
    }

    func testActiveDirectoryUsesLegacyFallbackPathsWhenNodeCannotBeResolved() throws {
        let cachedInfo = PasswordInfo(
            lastSetDate: Date().addingTimeInterval(-4 * 24 * 3600),
            daysUntilExpiration: 26,
            expiryDate: Date().addingTimeInterval(26 * 24 * 3600),
            isFromCache: false
        )
        PasswordCache.shared.save(cachedInfo)

        var attemptedPaths: [String] = []
        let manager = ActiveDirectoryManager(
            currentDomain: { "corp.example.com" },
            adNodeName: { _ in nil },
            adOutputReader: { _, path in
                attemptedPaths.append(path)
                throw ADError.commandFailed("offline")
            },
            localOutputReader: { _ in
                XCTFail("Local passwordLastSetTime should not be used when an AD domain is configured")
                throw ADError.userNotFound
            }
        )

        let info = try manager.getPasswordInfo(for: "tester")

        XCTAssertEqual(
            attemptedPaths,
            [
                "/Active Directory/All Domains",
                "/Search",
                "/Active Directory/corp.example.com/All Domains"
            ]
        )
        XCTAssertTrue(info.isFromCache)
    }

    func testActiveDirectoryFallbackPathCanRecoverWhenNodeCannotBeResolved() throws {
        let lastSetDate = Date().addingTimeInterval(-5 * 24 * 3600)
        var attemptedPaths: [String] = []
        let manager = ActiveDirectoryManager(
            currentDomain: { "corp.example.com" },
            adNodeName: { _ in nil },
            adOutputReader: { _, path in
                attemptedPaths.append(path)
                guard path == "/Active Directory/All Domains" else {
                    throw ADError.commandFailed("unexpected fallback")
                }
                return self.smbPasswordLastSetOutput(for: lastSetDate)
            },
            localOutputReader: { _ in
                XCTFail("Local passwordLastSetTime should not be used after a successful AD fallback read")
                throw ADError.userNotFound
            }
        )

        let info = try manager.getPasswordInfo(for: "tester")

        XCTAssertEqual(attemptedPaths, ["/Active Directory/All Domains"])
        XCTAssertFalse(info.isFromCache)
        XCTAssertEqual(info.lastSetDate.timeIntervalSince1970, lastSetDate.timeIntervalSince1970, accuracy: 1)
    }

    func testActiveDirectoryUsesLocalPasswordInfoOnlyWithoutConfiguredDomain() throws {
        var attemptedADPaths: [String] = []
        let lastSetDate = Date().addingTimeInterval(-5 * 24 * 3600)
        let manager = ActiveDirectoryManager(
            currentDomain: { nil },
            adNodeName: { _ in nil },
            adOutputReader: { _, path in
                attemptedADPaths.append(path)
                throw ADError.commandFailed("unexpected AD read")
            },
            localOutputReader: { _ in
                self.localPasswordLastSetOutput(for: lastSetDate)
            }
        )

        let info = try manager.getPasswordInfo(for: "tester")

        XCTAssertTrue(attemptedADPaths.isEmpty)
        XCTAssertFalse(info.isFromCache)
        XCTAssertEqual(info.lastSetDate.timeIntervalSince1970, lastSetDate.timeIntervalSince1970, accuracy: 1)
    }

    func testActiveDirectoryPrefersResolvedNodeBeforeConfiguredDomainFallback() throws {
        let lastSetDate = Date().addingTimeInterval(-6 * 24 * 3600)
        var attemptedPaths: [String] = []
        let manager = ActiveDirectoryManager(
            currentDomain: { "corp.example.com" },
            adNodeName: { _ in "CORP" },
            adOutputReader: { _, path in
                attemptedPaths.append(path)
                return self.smbPasswordLastSetOutput(for: lastSetDate)
            },
            localOutputReader: { _ in
                XCTFail("Local passwordLastSetTime should not be used after a successful AD read")
                throw ADError.userNotFound
            }
        )

        let info = try manager.getPasswordInfo(for: "tester")

        XCTAssertEqual(attemptedPaths, ["/Active Directory/CORP/All Domains"])
        XCTAssertFalse(info.isFromCache)
        XCTAssertEqual(info.lastSetDate.timeIntervalSince1970, lastSetDate.timeIntervalSince1970, accuracy: 1)
    }

    func testHelperScheduleNextOccurrenceReturnsSameDayFutureTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 3600) // 01:00

        let next = HelperSchedule.nextOccurrence(for: "09:00", after: now, calendar: calendar)
        XCTAssertEqual(next, Date(timeIntervalSince1970: 9 * 3600))
    }

    func testHelperScheduleNextOccurrenceRollsToNextDayWhenTimePassed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 10 * 3600) // 10:00

        let next = HelperSchedule.nextOccurrence(for: "09:00", after: now, calendar: calendar)
        XCTAssertEqual(next, Date(timeIntervalSince1970: 33 * 3600))
    }

    func testHelperScheduleQuietHoursOvernightRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let evening = Date(timeIntervalSince1970: (19 * 3600))
        let earlyMorning = Date(timeIntervalSince1970: (5 * 3600))
        let midday = Date(timeIntervalSince1970: (12 * 3600))

        XCTAssertTrue(
            HelperSchedule.isWithinQuietHours(
                date: evening,
                startTime: "18:01",
                endTime: "05:59",
                calendar: calendar
            )
        )
        XCTAssertTrue(
            HelperSchedule.isWithinQuietHours(
                date: earlyMorning,
                startTime: "18:01",
                endTime: "05:59",
                calendar: calendar
            )
        )
        XCTAssertFalse(
            HelperSchedule.isWithinQuietHours(
                date: midday,
                startTime: "18:01",
                endTime: "05:59",
                calendar: calendar
            )
        )
    }

    func testHelperScheduleQuietHoursDisabledWhenStartEqualsEnd() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sample = Date(timeIntervalSince1970: (22 * 3600))

        XCTAssertFalse(
            HelperSchedule.isWithinQuietHours(
                date: sample,
                startTime: "00:00",
                endTime: "00:00",
                calendar: calendar
            )
        )
    }

    func testDashboardSpecMapsSeverityThresholdsDeterministically() {
        XCTAssertEqual(PMDashboardSpec.severity(for: 40), .healthy)
        XCTAssertEqual(PMDashboardSpec.severity(for: 29), .warning)
        XCTAssertEqual(PMDashboardSpec.severity(for: 14), .warning)
        XCTAssertEqual(PMDashboardSpec.severity(for: 13), .urgent)
        XCTAssertEqual(PMDashboardSpec.severity(for: 2), .urgent)
        XCTAssertEqual(PMDashboardSpec.severity(for: 1), .critical)
        XCTAssertEqual(PMDashboardSpec.severity(for: 0), .critical)
    }

    func testDashboardSpecProvidesAllDashboardTileLayouts() {
        XCTAssertEqual(PMDashboardSpec.dashboardLayout.count, 4)
        XCTAssertNotNil(PMDashboardSpec.dashboardLayout[.password])
        XCTAssertNotNil(PMDashboardSpec.dashboardLayout[.hrPortal])
        XCTAssertNotNil(PMDashboardSpec.dashboardLayout[.networkDrives])
        XCTAssertNotNil(PMDashboardSpec.dashboardLayout[.help])

        for (_, spec) in PMDashboardSpec.dashboardLayout {
            XCTAssertGreaterThan(spec.maxRadius, spec.minRadius)
            XCTAssertGreaterThanOrEqual(spec.baseRadius, spec.minRadius)
            XCTAssertLessThanOrEqual(spec.baseRadius, spec.maxRadius)
            XCTAssertGreaterThanOrEqual(spec.anchor.x, 0)
            XCTAssertLessThanOrEqual(spec.anchor.x, 1)
            XCTAssertGreaterThanOrEqual(spec.anchor.y, 0)
            XCTAssertLessThanOrEqual(spec.anchor.y, 1)
        }
    }

    func testDashboardSpecEnablesReduceMotionCompatibilityByDefault() {
        XCTAssertTrue(PMDashboardSpec.defaultMotionSpec.disabledByReduceMotion)
        XCTAssertEqual(PMDashboardSpec.defaultMotionSpec.maxOffsetX, 12, accuracy: 0.0001)
        XCTAssertEqual(PMDashboardSpec.defaultMotionSpec.maxOffsetY, 10, accuracy: 0.0001)
        XCTAssertEqual(PMDashboardSpec.defaultMotionSpec.cursorInfluence, 0.22, accuracy: 0.0001)
        XCTAssertEqual(PMDashboardSpec.defaultMotionSpec.returnSpring.response, 0.36, accuracy: 0.0001)
        XCTAssertEqual(PMDashboardSpec.defaultMotionSpec.returnSpring.dampingFraction, 0.82, accuracy: 0.0001)
        XCTAssertEqual(PMDashboardSpec.defaultMotionSpec.returnSpring.blendDuration, 0.05, accuracy: 0.0001)
        XCTAssertEqual(PMDashboardSpec.ctaSafeGap, 14, accuracy: 0.0001)
    }

    func testDashboardSpecRadiusScaleMatchesContractValues() {
        XCTAssertEqual(PMDashboardSpec.radiusScale(for: .healthy), 0.72, accuracy: 0.0001)
        XCTAssertEqual(PMDashboardSpec.radiusScale(for: .warning), 1.00, accuracy: 0.0001)
        XCTAssertEqual(PMDashboardSpec.radiusScale(for: .urgent), 1.22, accuracy: 0.0001)
        XCTAssertEqual(PMDashboardSpec.radiusScale(for: .critical), 1.54, accuracy: 0.0001)
    }

    func testDashboardSpecSeparatesNavigationDestinationsFromDashboardTiles() {
        XCTAssertTrue(AppDestinationID.allCases.contains(.home))
        XCTAssertTrue(AppDestinationID.allCases.contains(.settings))
        XCTAssertFalse(DashboardTileID.allCases.map(\.rawValue).contains(AppDestinationID.home.rawValue))
        XCTAssertFalse(DashboardTileID.allCases.map(\.rawValue).contains(AppDestinationID.settings.rawValue))
    }

    func testDashboardSpecKeepsDestinationAndDashboardTileColorMapsExplicit() {
        XCTAssertEqual(PMDashboardSpec.destinationColorHex.count, AppDestinationID.allCases.count)
        XCTAssertEqual(PMDashboardSpec.destinationColorHex[.home], "#72D8E1")
        XCTAssertEqual(PMDashboardSpec.destinationColorHex[.password], "#86E58C")
        XCTAssertEqual(PMDashboardSpec.destinationColorHex[.settings], "#5F8CFF")
        XCTAssertEqual(PMDashboardSpec.destinationColorHex[.help], "#F7C95D")

        XCTAssertEqual(PMDashboardSpec.dashboardTileColorHex.count, DashboardTileID.allCases.count)
        XCTAssertEqual(PMDashboardSpec.dashboardTileColorHex[.password], "#86E58C")
        XCTAssertEqual(PMDashboardSpec.dashboardTileColorHex[.hrPortal], "#A682FF")
        XCTAssertEqual(PMDashboardSpec.dashboardTileColorHex[.networkDrives], "#5F8CFF")
        XCTAssertEqual(PMDashboardSpec.dashboardTileColorHex[.help], "#F7C95D")
    }

    func testDashboardSpecMapsDashboardTilesToServiceModules() {
        XCTAssertEqual(PMDashboardSpec.tileServiceModule[.password] ?? nil, .password)
        XCTAssertEqual(PMDashboardSpec.tileServiceModule[.hrPortal] ?? nil, .hrPortal)
        XCTAssertEqual(PMDashboardSpec.tileServiceModule[.networkDrives] ?? nil, .networkDrives)
        XCTAssertNil(PMDashboardSpec.tileServiceModule[.help] ?? nil)
    }

    func testDashboardSpecMapsServiceModuleRuntimeStateToTileSeverity() {
        XCTAssertEqual(PMDashboardSpec.tileSeverity(for: .healthy), .healthy)
        XCTAssertEqual(PMDashboardSpec.tileSeverity(for: .warning), .warning)
        XCTAssertEqual(PMDashboardSpec.tileSeverity(for: .loading), .healthy)
        XCTAssertEqual(PMDashboardSpec.tileSeverity(for: .error), .urgent)
        XCTAssertEqual(PMDashboardSpec.tileSeverity(for: .unavailable), .critical)
    }

    func testDashboardSpecProvidesServiceModuleDestinationMapping() {
        XCTAssertEqual(PMDashboardSpec.moduleDestination.count, ServiceModuleID.allCases.count)
        XCTAssertEqual(PMDashboardSpec.moduleDestination[.password], .password)
        XCTAssertEqual(PMDashboardSpec.moduleDestination[.hrPortal], .home)
        XCTAssertEqual(PMDashboardSpec.moduleDestination[.networkDrives], .home)
    }

    func testDashboardSpecDefinesPresentationContractForFutureServiceModules() {
        XCTAssertEqual(PMDashboardSpec.serviceModulePresentation.count, ServiceModuleID.allCases.count)

        let hr = PMDashboardSpec.serviceModulePresentation[.hrPortal]
        XCTAssertEqual(hr?.launchMode, .inAppWebView)
        XCTAssertEqual(hr?.requiresNetwork, true)
        XCTAssertEqual(hr?.requiresAuthenticatedSession, true)
        XCTAssertEqual(hr?.allowedActions, [.open, .refresh, .retry, .openExternal])

        let drives = PMDashboardSpec.serviceModulePresentation[.networkDrives]
        XCTAssertEqual(drives?.launchMode, .nativePanel)
        XCTAssertEqual(drives?.requiresNetwork, true)
        XCTAssertEqual(drives?.requiresAuthenticatedSession, true)
        XCTAssertEqual(drives?.allowedActions, [.open, .refresh, .retry])
    }

    func testDashboardSpecDefinesInitialSnapshotsForServiceModules() {
        XCTAssertEqual(PMDashboardSpec.initialServiceModuleSnapshot.count, ServiceModuleID.allCases.count)

        let password = PMDashboardSpec.initialServiceModuleSnapshot[.password]
        XCTAssertEqual(password?.runtimeState, .healthy)
        XCTAssertEqual(password?.connectivity, .online)
        XCTAssertEqual(password?.authState, .authenticated)
        XCTAssertEqual(password?.primaryAction, .open)
        XCTAssertEqual(password?.secondaryActions, [.refresh])

        let hr = PMDashboardSpec.initialServiceModuleSnapshot[.hrPortal]
        XCTAssertEqual(hr?.runtimeState, .loading)
        XCTAssertEqual(hr?.connectivity, .degraded)
        XCTAssertEqual(hr?.authState, .authenticationRequired)
        XCTAssertEqual(hr?.statusKey, .awaitingPortalConfiguration)
        XCTAssertEqual(hr?.primaryAction, .open)
        XCTAssertEqual(hr?.secondaryActions, [.refresh, .openExternal])

        let drives = PMDashboardSpec.initialServiceModuleSnapshot[.networkDrives]
        XCTAssertEqual(drives?.runtimeState, .loading)
        XCTAssertEqual(drives?.connectivity, .degraded)
        XCTAssertEqual(drives?.authState, .authenticationRequired)
        XCTAssertEqual(drives?.statusKey, .awaitingNetworkDrivesConfiguration)
        XCTAssertEqual(drives?.primaryAction, .open)
        XCTAssertEqual(drives?.secondaryActions, [.refresh])
    }

    func testDashboardSpecProvidesStableStatusLocalizationKeys() {
        XCTAssertEqual(
            PMDashboardSpec.statusLocalizationKey(for: .awaitingPortalConfiguration),
            "dashboard_status_awaiting_portal_configuration"
        )
        XCTAssertEqual(
            PMDashboardSpec.statusLocalizationKey(for: .awaitingNetworkDrivesConfiguration),
            "dashboard_status_awaiting_network_drives_configuration"
        )
    }

    func testDashboardSpecServiceModuleContractValidationHasNoErrors() {
        XCTAssertEqual(PMDashboardSpec.serviceModuleContractValidationErrors(), [])
    }

    @MainActor
    func testResolvedWarningThresholdFallsBackToSevenDays() {
        XCTAssertEqual(NotificationManager.resolvedWarningThreshold(), 7)
    }

    @MainActor
    func testResolvedWarningThresholdUsesSavedValue() {
        UserDefaults.standard.set(14, forKey: "warning_threshold")
        XCTAssertEqual(NotificationManager.resolvedWarningThreshold(), 14)
    }

    @MainActor
    func testIsWithinWarningThresholdReturnsFalseBeforeThreshold() {
        let now = Date(timeIntervalSince1970: 0)
        let expirationDate = now.addingTimeInterval(8 * 24 * 3600)

        XCTAssertFalse(
            NotificationManager.isWithinWarningThreshold(
                now: now,
                expirationDate: expirationDate,
                thresholdDays: 7
            )
        )
    }

    @MainActor
    func testIsWithinWarningThresholdReturnsTrueAtThreshold() {
        let now = Date(timeIntervalSince1970: 0)
        let expirationDate = now.addingTimeInterval(7 * 24 * 3600)

        XCTAssertTrue(
            NotificationManager.isWithinWarningThreshold(
                now: now,
                expirationDate: expirationDate,
                thresholdDays: 7
            )
        )
    }

    @MainActor
    func testAutomaticNotificationsAreSuppressedDuringQuietHours() {
        UserDefaults.standard.set("18:01", forKey: "quiet_hours_start")
        UserDefaults.standard.set("05:59", forKey: "quiet_hours_end")
        let quietTime = Date(timeIntervalSince1970: 20 * 3600)

        XCTAssertTrue(
            NotificationManager.isNotificationSuppressedForQuietHours(
                reason: .automatic,
                now: quietTime
            )
        )
    }

    @MainActor
    func testScheduledNotificationsAreAllowedDuringQuietHours() {
        UserDefaults.standard.set("18:01", forKey: "quiet_hours_start")
        UserDefaults.standard.set("05:59", forKey: "quiet_hours_end")
        let quietTime = Date(timeIntervalSince1970: 20 * 3600)

        XCTAssertFalse(
            NotificationManager.isNotificationSuppressedForQuietHours(
                reason: .scheduledTime,
                now: quietTime
            )
        )
    }

    @MainActor
    func testAutomaticNotificationsRespectActiveSnooze() {
        let now = Date(timeIntervalSince1970: 1000)
        let snoozeEnd = now.addingTimeInterval(3600)

        XCTAssertTrue(
            NotificationManager.isNotificationSuppressedBySnooze(
                reason: .automatic,
                isSnoozed: true,
                snoozeEndTime: snoozeEnd,
                now: now
            )
        )
    }

    @MainActor
    func testManualNotificationsAreAllowedDuringQuietHours() {
        UserDefaults.standard.set("18:01", forKey: "quiet_hours_start")
        UserDefaults.standard.set("05:59", forKey: "quiet_hours_end")
        let quietTime = Date(timeIntervalSince1970: 20 * 3600)

        XCTAssertFalse(
            NotificationManager.isNotificationSuppressedForQuietHours(
                reason: .manual,
                now: quietTime
            )
        )
    }

    @MainActor
    func testManualNotificationsBypassActiveSnooze() {
        let now = Date(timeIntervalSince1970: 1000)
        let snoozeEnd = now.addingTimeInterval(3600)

        XCTAssertFalse(
            NotificationManager.isNotificationSuppressedBySnooze(
                reason: .manual,
                isSnoozed: true,
                snoozeEndTime: snoozeEnd,
                now: now
            )
        )
    }

    @MainActor
    func testScheduledNotificationsBypassActiveSnooze() {
        let now = Date(timeIntervalSince1970: 1000)
        let snoozeEnd = now.addingTimeInterval(3600)

        XCTAssertFalse(
            NotificationManager.isNotificationSuppressedBySnooze(
                reason: .scheduledTime,
                isSnoozed: true,
                snoozeEndTime: snoozeEnd,
                now: now
            )
        )
    }

    @MainActor
    func testNotificationResetClearsDailyState() {
        let manager = NotificationManager.shared
        manager.markNotificationAsShown()
        XCTAssertTrue(manager.isNotificationShownToday)
        manager.resetDailyNotificationState()
        XCTAssertFalse(manager.isNotificationShownToday)
    }

    func testSemanticVersionComparisonOrdersNumericSegments() throws {
        let newer = try PMSemanticVersion("1.10.0")
        let older = try PMSemanticVersion("1.9.9")

        XCTAssertTrue(newer > older)
        XCTAssertEqual(try PMSemanticVersion("v1.7.1").description, "1.7.1")
    }

    func testArchiveValidatorRejectsPathTraversal() {
        XCTAssertThrowsError(
            try PMUpdateArchiveValidator.validateArchiveEntries(
                ["PasswordMonitor.app/Contents/../evil.txt"],
                expectedAppName: "PasswordMonitor.app"
            )
        )
    }

    func testArchiveValidatorRejectsMultipleRoots() {
        XCTAssertThrowsError(
            try PMUpdateArchiveValidator.validateArchiveEntries(
                [
                    "PasswordMonitor.app/Contents/Info.plist",
                    "Other.app/Contents/Info.plist"
                ],
                expectedAppName: "PasswordMonitor.app"
            )
        )
    }

    func testArchiveValidatorAcceptsSingleAppRoot() throws {
        try PMUpdateArchiveValidator.validateArchiveEntries(
            [
                "PasswordMonitor.app",
                "PasswordMonitor.app/Contents/Info.plist",
                "PasswordMonitor.app/Contents/MacOS/PasswordMonitor"
            ],
            expectedAppName: "PasswordMonitor.app"
        )
    }

    func testValidateNoSymlinksRejectsSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasswordMonitorSymlinkTest-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("PasswordMonitor.app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let symlinkURL = contents.appendingPathComponent("LinkedFile")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: URL(fileURLWithPath: "/tmp"))

        XCTAssertThrowsError(
            try PMUpdateArchiveValidator.validateNoSymlinks(in: bundle)
        )
    }

    func testValidateNoSymlinksAcceptsStandardFrameworkSymlinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasswordMonitorFrameworkSymlinkTest-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("PasswordMonitor.app", isDirectory: true)
        let framework = bundle.appendingPathComponent("Contents/Frameworks/PasswordMonitorCore.framework", isDirectory: true)
        let version = framework.appendingPathComponent("Versions/A", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: version.appendingPathComponent("Resources", isDirectory: true),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: version.appendingPathComponent("PasswordMonitorCore").path,
            contents: Data(),
            attributes: nil
        )
        try FileManager.default.createSymbolicLink(
            atPath: framework.appendingPathComponent("Resources").path,
            withDestinationPath: "Versions/Current/Resources"
        )
        try FileManager.default.createSymbolicLink(
            atPath: framework.appendingPathComponent("PasswordMonitorCore").path,
            withDestinationPath: "Versions/Current/PasswordMonitorCore"
        )
        try FileManager.default.createSymbolicLink(
            atPath: framework.appendingPathComponent("Versions/Current").path,
            withDestinationPath: "A"
        )

        XCTAssertNoThrow(
            try PMUpdateArchiveValidator.validateNoSymlinks(in: bundle)
        )
    }

    func testValidateNoSymlinksRejectsAbsoluteFrameworkSymlinkTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasswordMonitorAbsoluteFrameworkSymlinkTest-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("PasswordMonitor.app", isDirectory: true)
        let framework = bundle.appendingPathComponent("Contents/Frameworks/PasswordMonitorCore.framework", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: framework.appendingPathComponent("Resources").path,
            withDestinationPath: "/tmp"
        )

        XCTAssertThrowsError(
            try PMUpdateArchiveValidator.validateNoSymlinks(in: bundle)
        )
    }

    func testValidateNoSymlinksRejectsTraversingFrameworkSymlinkTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasswordMonitorTraversingFrameworkSymlinkTest-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("PasswordMonitor.app", isDirectory: true)
        let framework = bundle.appendingPathComponent("Contents/Frameworks/PasswordMonitorCore.framework", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: framework.appendingPathComponent("Resources").path,
            withDestinationPath: "../Resources"
        )

        XCTAssertThrowsError(
            try PMUpdateArchiveValidator.validateNoSymlinks(in: bundle)
        )
    }

    func testValidateNoSymlinksRejectsUnexpectedFrameworkSymlinkName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasswordMonitorUnexpectedFrameworkSymlinkTest-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("PasswordMonitor.app", isDirectory: true)
        let framework = bundle.appendingPathComponent("Contents/Frameworks/PasswordMonitorCore.framework", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: framework.appendingPathComponent("Unexpected").path,
            withDestinationPath: "Versions/Current/Unexpected"
        )

        XCTAssertThrowsError(
            try PMUpdateArchiveValidator.validateNoSymlinks(in: bundle)
        )
    }

    func testValidatePermissionsRejectsWorldWritableFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasswordMonitorPermissionTest-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("PasswordMonitor.app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let fileURL = contents.appendingPathComponent("Info.plist")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: fileURL.path)

        XCTAssertThrowsError(
            try PMUpdateArchiveValidator.validatePermissions(in: bundle)
        )
    }

    func testSignedManifestVerificationAcceptsValidSignature() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let manifest = PMUpdateManifest(
            version: "1.8.0",
            assetName: "PasswordMonitor.app.zip",
            assetSHA256: String(repeating: "a", count: 64),
            bundleIdentifier: "popo.PasswordMonitor",
            signingKeyID: "test-key"
        )
        let signedManifest = try signedManifest(
            manifest: manifest,
            privateKey: privateKey
        )

        let service = PMUpdateService(
            configuration: PMUpdateConfiguration(
                owner: "example",
                repository: "PasswordMonitor",
                appBundleIdentifier: "popo.PasswordMonitor",
                appBundleName: "PasswordMonitor.app",
                appZipAssetName: "PasswordMonitor.app.zip",
                manifestAssetName: "PasswordMonitor.update-manifest.json",
                githubAPIBaseURL: URL(string: "https://api.github.com")!,
                trustedSigningKeys: [
                    PMUpdateSigningKey(keyID: "test-key", publicKeyBase64: publicKeyBase64)
                ]
            )
        )

        try service.validateSignedManifest(signedManifest)
    }

    func testSignedManifestVerificationRejectsTampering() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let manifest = PMUpdateManifest(
            version: "1.8.0",
            assetName: "PasswordMonitor.app.zip",
            assetSHA256: String(repeating: "b", count: 64),
            bundleIdentifier: "popo.PasswordMonitor",
            signingKeyID: "test-key"
        )
        let signedManifest = try signedManifest(
            manifest: manifest,
            privateKey: privateKey
        )

        let service = PMUpdateService(
            configuration: PMUpdateConfiguration(
                owner: "example",
                repository: "PasswordMonitor",
                appBundleIdentifier: "popo.PasswordMonitor",
                appBundleName: "PasswordMonitor.app",
                appZipAssetName: "PasswordMonitor.app.zip",
                manifestAssetName: "PasswordMonitor.update-manifest.json",
                githubAPIBaseURL: URL(string: "https://api.github.com")!,
                trustedSigningKeys: [
                    PMUpdateSigningKey(keyID: "test-key", publicKeyBase64: publicKeyBase64)
                ]
            )
        )

        let tamperedManifest = PMSignedUpdateManifest(
            manifest: PMUpdateManifest(
                version: "1.8.1",
                assetName: manifest.assetName,
                assetSHA256: manifest.assetSHA256,
                bundleIdentifier: manifest.bundleIdentifier,
                signingKeyID: manifest.signingKeyID
            ),
            signature: signedManifest.signature
        )

        XCTAssertThrowsError(try service.validateSignedManifest(tamperedManifest))
    }

    func testSignedManifestVerificationRejectsUnknownKeyID() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let manifest = PMUpdateManifest(
            version: "1.8.0",
            assetName: "PasswordMonitor.app.zip",
            assetSHA256: String(repeating: "c", count: 64),
            bundleIdentifier: "popo.PasswordMonitor",
            signingKeyID: "unexpected-key"
        )
        let signedManifest = try signedManifest(
            manifest: manifest,
            privateKey: privateKey
        )

        let service = PMUpdateService(
            configuration: PMUpdateConfiguration(
                owner: "example",
                repository: "PasswordMonitor",
                appBundleIdentifier: "popo.PasswordMonitor",
                appBundleName: "PasswordMonitor.app",
                appZipAssetName: "PasswordMonitor.app.zip",
                manifestAssetName: "PasswordMonitor.update-manifest.json",
                githubAPIBaseURL: URL(string: "https://api.github.com")!,
                trustedSigningKeys: [
                    PMUpdateSigningKey(keyID: "different-key", publicKeyBase64: publicKeyBase64)
                ]
            )
        )

        XCTAssertThrowsError(try service.validateSignedManifest(signedManifest))
    }

    func testUpdateManifestDecodeDefaultsMissingUrgencyToNormal() throws {
        let data = Data("""
        {
          "version": "1.9.3",
          "assetName": "PasswordMonitor.app.zip",
          "assetSHA256": "\(String(repeating: "d", count: 64))",
          "bundleIdentifier": "popo.PasswordMonitor",
          "signingKeyID": "test-key"
        }
        """.utf8)

        let manifest = try JSONDecoder().decode(PMUpdateManifest.self, from: data)

        XCTAssertEqual(manifest.urgency, .normal)
    }

    func testUpdateManifestDecodeCriticalUrgency() throws {
        let data = Data("""
        {
          "version": "1.9.3",
          "assetName": "PasswordMonitor.app.zip",
          "assetSHA256": "\(String(repeating: "e", count: 64))",
          "bundleIdentifier": "popo.PasswordMonitor",
          "signingKeyID": "test-key",
          "urgency": "critical"
        }
        """.utf8)

        let manifest = try JSONDecoder().decode(PMUpdateManifest.self, from: data)

        XCTAssertEqual(manifest.urgency, .critical)
    }

    func testUpdateCandidateCarriesSignedManifestForInstallReuse() throws {
        let manifest = PMUpdateManifest(
            version: "1.9.4",
            assetName: "PasswordMonitor.app.zip",
            assetSHA256: String(repeating: "f", count: 64),
            bundleIdentifier: "popo.PasswordMonitor",
            signingKeyID: "test-key",
            urgency: .critical
        )
        let signedManifest = PMSignedUpdateManifest(manifest: manifest, signature: "signature")

        let candidate = PMUpdateCandidate(
            version: try PMSemanticVersion("1.9.4"),
            releaseTag: "v1.9.4",
            assetName: manifest.assetName,
            assetURL: URL(string: "https://api.github.com/repos/example/PasswordMonitor/releases/assets/1")!,
            manifestURL: URL(string: "https://api.github.com/repos/example/PasswordMonitor/releases/assets/2")!,
            manifestName: "PasswordMonitor.update-manifest.json",
            signedManifest: signedManifest,
            createdAt: Date(timeIntervalSince1970: 10_000),
            bundleIdentifier: manifest.bundleIdentifier,
            appBundleName: "PasswordMonitor.app",
            urgency: manifest.urgency
        )

        XCTAssertEqual(candidate.signedManifest, signedManifest)
        XCTAssertEqual(candidate.urgency, .critical)
        XCTAssertTrue(candidate.isFresh(now: Date(timeIntervalSince1970: 10_000 + 1_799), ttl: 1_800))
        XCTAssertFalse(candidate.isFresh(now: Date(timeIntervalSince1970: 10_000 + 1_801), ttl: 1_800))
    }

    func testAutomaticUpdateCheckCooldownPolicy() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(UpdateNotificationStateStore.shouldRunAutomaticCheck(
            automaticChecksEnabled: true,
            lastAutomaticCheckAt: nil,
            lastBackgroundErrorAt: nil,
            now: now,
            successCooldown: 100,
            failureCooldown: 20
        ))
        XCTAssertFalse(UpdateNotificationStateStore.shouldRunAutomaticCheck(
            automaticChecksEnabled: false,
            lastAutomaticCheckAt: nil,
            lastBackgroundErrorAt: nil,
            now: now,
            successCooldown: 100,
            failureCooldown: 20
        ))
        XCTAssertFalse(UpdateNotificationStateStore.shouldRunAutomaticCheck(
            automaticChecksEnabled: true,
            lastAutomaticCheckAt: now.addingTimeInterval(-99),
            lastBackgroundErrorAt: nil,
            now: now,
            successCooldown: 100,
            failureCooldown: 20
        ))
        XCTAssertTrue(UpdateNotificationStateStore.shouldRunAutomaticCheck(
            automaticChecksEnabled: true,
            lastAutomaticCheckAt: now.addingTimeInterval(-100),
            lastBackgroundErrorAt: nil,
            now: now,
            successCooldown: 100,
            failureCooldown: 20
        ))
    }

    func testAutomaticUpdateCheckFailureCooldownIsShorterThanSuccessCooldown() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertFalse(UpdateNotificationStateStore.shouldRunAutomaticCheck(
            automaticChecksEnabled: true,
            lastAutomaticCheckAt: nil,
            lastBackgroundErrorAt: now.addingTimeInterval(-59),
            now: now,
            successCooldown: 100,
            failureCooldown: 60
        ))
        XCTAssertTrue(UpdateNotificationStateStore.shouldRunAutomaticCheck(
            automaticChecksEnabled: true,
            lastAutomaticCheckAt: nil,
            lastBackgroundErrorAt: now.addingTimeInterval(-60),
            now: now,
            successCooldown: 100,
            failureCooldown: 60
        ))
    }

    func testUpdateStateStoreRecordsBackgroundErrorWithoutSuccessCooldown() {
        let suiteName = "popo.PasswordMonitor.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UpdateNotificationStateStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 10_000)

        store.recordBackgroundError("offline", at: now)

        XCTAssertNil(store.state.lastAutomaticCheckAt)
        XCTAssertEqual(store.state.lastBackgroundError, "offline")
        XCTAssertEqual(store.state.lastBackgroundErrorAt, now)
        XCTAssertFalse(store.shouldRunAutomaticCheck(now: now.addingTimeInterval(30), successCooldown: 100, failureCooldown: 60))
        XCTAssertTrue(store.shouldRunAutomaticCheck(now: now.addingTimeInterval(60), successCooldown: 100, failureCooldown: 60))
    }

    func testUpdateStatePendingInstallRequestConsumesOnce() {
        let suiteName = "popo.PasswordMonitor.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UpdateNotificationStateStore(defaults: defaults)

        store.setPendingInstallRequest(true)

        XCTAssertTrue(store.consumePendingInstallRequest())
        XCTAssertFalse(store.consumePendingInstallRequest())
    }

    func testUpdateStateAutomaticCheckClaimBlocksUntilTTL() {
        let suiteName = "popo.PasswordMonitor.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UpdateNotificationStateStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(store.claimAutomaticCheck(now: now, ttl: 120))
        XCTAssertFalse(store.claimAutomaticCheck(now: now.addingTimeInterval(119), ttl: 120))
        XCTAssertTrue(store.claimAutomaticCheck(now: now.addingTimeInterval(120), ttl: 120))
    }

    func testUpdateStateAutomaticCheckClaimClearsAfterFailure() {
        let suiteName = "popo.PasswordMonitor.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UpdateNotificationStateStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(store.claimAutomaticCheck(now: now, ttl: 120))
        store.recordBackgroundError("offline", at: now.addingTimeInterval(1))

        XCTAssertNil(store.state.checkInFlightUntil)
        XCTAssertTrue(store.claimAutomaticCheck(now: now.addingTimeInterval(2), ttl: 120))
    }

    func testUpdateStateRemindLaterSuppressesNormalNotificationOnly() {
        let suiteName = "popo.PasswordMonitor.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UpdateNotificationStateStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 10_000)

        store.recordAvailableUpdate(version: "1.9.4", releaseTag: "v1.9.4", urgency: .normal)
        store.remindLater(until: now.addingTimeInterval(60))
        XCTAssertFalse(store.shouldNotifyUser(now: now))

        store.recordAvailableUpdate(version: "1.9.5", releaseTag: "v1.9.5", urgency: .critical)
        XCTAssertTrue(store.state.isCriticalBlocking)
        XCTAssertTrue(store.shouldNotifyUser(now: now))
    }

    private func signedManifest(
        manifest: PMUpdateManifest,
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> PMSignedUpdateManifest {
        let payloadData = try PMUpdateService.manifestSigningPayload(for: manifest)
        let signature = try privateKey.signature(for: payloadData)
        return PMSignedUpdateManifest(
            manifest: manifest,
            signature: signature.base64EncodedString()
        )
    }

    func testNotificationDeliveryClaimBlocksImmediateDuplicate() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let expiryDate = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(store.claimNotificationDelivery(expirationDate: expiryDate, now: now))
        XCTAssertFalse(store.claimNotificationDelivery(expirationDate: expiryDate, now: now))
    }

    func testNotificationDeliveryClaimExpiresAfterWindow() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let expiryDate = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(store.claimNotificationDelivery(expirationDate: expiryDate, now: now))
        XCTAssertTrue(store.claimNotificationDelivery(expirationDate: expiryDate, now: now.addingTimeInterval(121)))
    }

    func testNotificationDeliveryClaimAllowsDifferentExpirationDate() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let firstExpiry = Date(timeIntervalSince1970: 10_000)
        let secondExpiry = Date(timeIntervalSince1970: 20_000)

        XCTAssertTrue(store.claimNotificationDelivery(expirationDate: firstExpiry, now: now))
        XCTAssertTrue(store.claimNotificationDelivery(expirationDate: secondExpiry, now: now.addingTimeInterval(1)))
    }

    func testScheduledNotificationEventClaimBlocksDuplicateSlot() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let eventKey = "2026-04-29@10:00"

        XCTAssertTrue(store.claimScheduledNotificationEvent(eventKey: eventKey, now: now))
        XCTAssertFalse(store.claimScheduledNotificationEvent(eventKey: eventKey, now: now.addingTimeInterval(30)))
    }

    func testScheduledNotificationEventClaimAllowsDifferentSlot() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let eventKey = "2026-04-29@10:00"
        let otherEventKey = "2026-04-29@13:00"

        XCTAssertTrue(store.claimScheduledNotificationEvent(eventKey: eventKey, now: now))
        XCTAssertTrue(store.claimScheduledNotificationEvent(eventKey: otherEventKey, now: now.addingTimeInterval(30)))
    }

    func testHelperTriggerClaimBlocksDuplicateRequest() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let triggerKey = "helper:scheduled:2026-04-29@10:00"

        XCTAssertTrue(store.claimHelperTrigger(triggerKey: triggerKey, now: now))
        XCTAssertFalse(store.claimHelperTrigger(triggerKey: triggerKey, now: now.addingTimeInterval(10)))
    }

    func testHelperTriggerClaimAllowsDifferentRequest() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let firstTriggerKey = "helper:scheduled:2026-04-29@10:00"
        let secondTriggerKey = "helper:wake:2026-04-29@10:01"

        XCTAssertTrue(store.claimHelperTrigger(triggerKey: firstTriggerKey, now: now))
        XCTAssertTrue(store.claimHelperTrigger(triggerKey: secondTriggerKey, now: now.addingTimeInterval(30)))
    }

    func testHelperProcessCleanupSelectsOnlyHelpersFromDifferentBundlePath() {
        let expectedPath = "/Applications/PasswordMonitor.app/Contents/Library/LoginItems/PasswordMonitorHelperApp.app"
        let stalePath = "/Users/test/Desktop/PasswordMonitor.app/Contents/Library/LoginItems/PasswordMonitorHelperApp.app"
        let helpers = [
            HelperProcessCleanup.RunningHelper(processIdentifier: 10, bundlePath: expectedPath),
            HelperProcessCleanup.RunningHelper(processIdentifier: 11, bundlePath: stalePath),
            HelperProcessCleanup.RunningHelper(processIdentifier: 12, bundlePath: nil)
        ]

        let staleHelpers = HelperProcessCleanup.staleHelpers(
            expectedBundlePath: expectedPath,
            runningHelpers: helpers
        )

        XCTAssertEqual(staleHelpers.map(\.processIdentifier), [11, 12])
    }

    func testHelperProcessCleanupDoesNotSelectCurrentHelperAsDuplicate() {
        let helpers = [
            HelperProcessCleanup.RunningHelper(processIdentifier: 20, bundlePath: "/current/helper.app"),
            HelperProcessCleanup.RunningHelper(processIdentifier: 21, bundlePath: "/stale/helper.app")
        ]

        let duplicates = HelperProcessCleanup.duplicateHelpers(
            currentProcessIdentifier: 20,
            runningHelpers: helpers
        )

        XCTAssertEqual(duplicates.map(\.processIdentifier), [21])
    }

    func testAppUninstallCleanupPlanIncludesHelperPreferencesAndUserData() {
        let home = URL(fileURLWithPath: "/Users/test")
        let paths = AppUninstallCleanupPlan.userDataPaths(
            homeDirectory: home,
            userInstalledAppURL: home.appendingPathComponent("Applications/PasswordMonitor.app"),
            desktopAppURL: home.appendingPathComponent("Desktop/PasswordMonitor/PasswordMonitor.app")
        ).map(\.path)

        XCTAssertTrue(paths.contains("/Users/test/Library/Preferences/popo.PasswordMonitor.plist"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Preferences/popo.PasswordMonitorHelperApp.plist"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Containers/popo.PasswordMonitorHelperApp"))
        XCTAssertTrue(paths.contains("/Users/test/Library/LaunchAgents/com.company.password-monitor.plist"))
        XCTAssertTrue(paths.contains("/Users/Shared/password-monitor.sh"))
        XCTAssertTrue(paths.contains("/tmp/password-monitor.out"))
        XCTAssertTrue(paths.contains("/tmp/password-monitor.err"))
        XCTAssertTrue(paths.contains("/Users/test/.password_monitor.log"))
        XCTAssertTrue(paths.contains("/Users/test/.password_monitor.log.1"))
        XCTAssertTrue(paths.contains("/Users/test/.password_monitor.log.lock"))
        XCTAssertTrue(paths.contains("/Applications/PasswordMonitor.app"))
        XCTAssertTrue(paths.contains("/Users/test/Applications/PasswordMonitor.app"))
        XCTAssertTrue(paths.contains("/Users/test/Desktop/PasswordMonitor/PasswordMonitor.app"))
        XCTAssertTrue(AppUninstallCleanupPlan.preferenceDomains.contains("popo.PasswordMonitorHelperApp"))
        XCTAssertTrue(AppUninstallCleanupPlan.loginItemIdentifiers.contains("com.company.password-monitor"))
    }

    @MainActor
    func testDuplicateNotificationPresentationIsSuppressedForSameExpirationDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        let expirationDate = Date(timeIntervalSince1970: 10_000)
        let lastPresentedAt = now.addingTimeInterval(-30)

        XCTAssertTrue(
            NotificationManager.shouldSuppressDuplicateNotificationPresentation(
                reason: .scheduledTime,
                expirationDate: expirationDate,
                lastPresentedExpirationDate: expirationDate,
                lastPresentedAt: lastPresentedAt,
                now: now,
                duplicatePresentationWindow: 120
            )
        )
    }

    @MainActor
    func testDuplicateNotificationPresentationAllowsDifferentExpirationDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        let expirationDate = Date(timeIntervalSince1970: 10_000)
        let otherExpirationDate = Date(timeIntervalSince1970: 11_000)
        let lastPresentedAt = now.addingTimeInterval(-30)

        XCTAssertFalse(
            NotificationManager.shouldSuppressDuplicateNotificationPresentation(
                reason: .checkNow,
                expirationDate: expirationDate,
                lastPresentedExpirationDate: otherExpirationDate,
                lastPresentedAt: lastPresentedAt,
                now: now,
                duplicatePresentationWindow: 120
            )
        )
    }

    @MainActor
    func testDuplicateNotificationPresentationDoesNotSuppressManualCheckNow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let expirationDate = Date(timeIntervalSince1970: 10_000)
        let lastPresentedAt = now.addingTimeInterval(-30)

        XCTAssertFalse(
            NotificationManager.shouldSuppressDuplicateNotificationPresentation(
                reason: .checkNow,
                expirationDate: expirationDate,
                lastPresentedExpirationDate: expirationDate,
                lastPresentedAt: lastPresentedAt,
                now: now,
                duplicatePresentationWindow: 120
            )
        )
    }
}
