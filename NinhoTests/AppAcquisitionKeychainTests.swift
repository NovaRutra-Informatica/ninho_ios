import XCTest
import Security
import NinhoCore
@testable import Ninho

@MainActor final class AppAcquisitionKeychainTests: XCTestCase {
    private func record(_ evidence: String = "synthetic-test-evidence", environment: AppAcquisitionEnvironment = .production) -> AppAcquisitionRecord {
        AppAcquisitionRecord(bundleID: "test.ninho", appID: 1, environment: environment,
                             originalPurchaseDate: Date(timeIntervalSince1970: 0),
                             signedDate: Date(timeIntervalSince1970: 1), signedTransaction: evidence)
    }

    func testKeychainRoundTripUpdateAndRemovalAreIsolatedFromOtherAppRecords() async throws {
        let cache = KeychainAppAcquisitionCache(bundleID: "test.ninho.acquisition.\(UUID())")
        do {
            let empty = try await cache.load()
            XCTAssertNil(empty)
            try await cache.save(record())
            let first = try await cache.load()
            XCTAssertEqual(first, record())
            try await cache.save(record("updated-synthetic-evidence"))
            let second = try await cache.load()
            XCTAssertEqual(second, record("updated-synthetic-evidence"))
            try await cache.remove()
            let removed = try await cache.load()
            XCTAssertNil(removed)
        } catch {
            try? await cache.remove()
            throw error
        }
    }

    func testAcquisitionIsDeviceOnlyAndNotSynchronizable() async throws {
        let bundleID = "test.ninho.acquisition.\(UUID())"
        let cache = KeychainAppAcquisitionCache(bundleID: bundleID)
        try await cache.save(record())
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: bundleID + ".app-acquisition.v1",
                                    kSecAttrAccount as String: "app-store-production",
                                    kSecUseDataProtectionKeychain as String: true,
                                    kSecReturnAttributes as String: true]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        try await cache.remove()
        XCTAssertEqual(status, errSecSuccess)
        let attributes = try XCTUnwrap(item as? [String: Any])
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertNotEqual(attributes[kSecAttrSynchronizable as String] as? Bool, true)
    }

    func testSandboxCannotBeWrittenIntoPermanentAcquisitionCache() async throws {
        let cache = KeychainAppAcquisitionCache(bundleID: "test.ninho.acquisition.\(UUID())")
        do {
            try await cache.save(record(environment: .sandbox))
            XCTFail("Sandbox must not become a permanent production acquisition")
            try await cache.remove()
        } catch let error as AppAcquisitionFailure {
            XCTAssertEqual(error, .unverified)
        }
        let saved = try await cache.load()
        XCTAssertNil(saved)
    }

    func testSuspensionRemainsDeniedWhenCacheIsReopened() async throws {
        let bundleID = "test.ninho.acquisition.\(UUID())"
        let cache = KeychainAppAcquisitionCache(bundleID: bundleID)
        do {
            try await cache.save(record())
            try await cache.suspend()
            let reopened = KeychainAppAcquisitionCache(bundleID: bundleID)
            let blocked = try await reopened.load()
            XCTAssertNil(blocked)
            try await reopened.save(record("fresh-confirmation"))
            let restored = try await cache.load()
            XCTAssertEqual(restored, record("fresh-confirmation"))
            try await cache.remove()
        } catch {
            try? await cache.remove()
            throw error
        }
    }
}
