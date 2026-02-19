//
//  PasswordMonitorCoreTests.swift
//  PasswordMonitorCoreTests
//
//  Created by Kamil Popowicz on 19/02/2026.
//

import XCTest
@testable import PasswordMonitorCore

final class PasswordMonitorCoreTests: XCTestCase {
    private let cacheKey = "cached_password_info"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        super.tearDown()
    }

    func testPasswordCacheSaveLoadMarksFromCache() {
        let info = PasswordInfo(
            lastSetDate: Date(timeIntervalSince1970: 0),
            daysUntilExpiration: 7,
            expiryDate: Date(timeIntervalSince1970: 60),
            isFromCache: false
        )

        PasswordCache.shared.save(info)

        let loaded = PasswordCache.shared.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.daysUntilExpiration, 7)
        XCTAssertEqual(loaded?.expiryDate, Date(timeIntervalSince1970: 60))
        XCTAssertEqual(loaded?.lastSetDate, Date(timeIntervalSince1970: 0))
        XCTAssertTrue(loaded?.isFromCache ?? false)
    }

    func testPasswordCacheLoadInvalidDataReturnsNil() {
        UserDefaults.standard.set(Data([0x00, 0x01, 0x02]), forKey: cacheKey)
        let loaded = PasswordCache.shared.load()
        XCTAssertNil(loaded)
    }

    func testParseSMBPasswordLastSetEpoch() throws {
        let output = "SMBPasswordLastSet: 116444736000000000\n"
        let date = try ActiveDirectoryManager.parseSMBPasswordLastSet(from: output)
        XCTAssertEqual(date, Date(timeIntervalSince1970: 0))
    }

    func testParseSMBPasswordLastSetInvalid() {
        XCTAssertThrowsError(try ActiveDirectoryManager.parseSMBPasswordLastSet(from: "nope"))
    }

    @MainActor
    func testNotificationResetClearsDailyState() {
        let manager = NotificationManager.shared
        manager.markNotificationAsShown()
        XCTAssertTrue(manager.isNotificationShownToday)
        manager.resetDailyNotificationState()
        XCTAssertFalse(manager.isNotificationShownToday)
    }
}
