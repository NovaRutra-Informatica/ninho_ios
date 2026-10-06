import XCTest
@testable import NinhoCore

final class AppAcquisitionTests: XCTestCase, @unchecked Sendable {
    private let configuration = AppAcquisitionConfiguration(bundleID: "test.ninho", appID: "123456789")

    private func record(bundleID: String = "test.ninho", appID: UInt64? = 123456789,
                        environment: AppAcquisitionEnvironment = .production, version: Int = 1,
                        signedTransaction: String = "synthetic-evidence-not-a-valid-signature") -> AppAcquisitionRecord {
        AppAcquisitionRecord(bundleID: bundleID, appID: appID, environment: environment,
                             originalPurchaseDate: Date(timeIntervalSince1970: 0),
                             signedDate: Date(timeIntervalSince1970: 1), signedTransaction: signedTransaction, version: version)
    }

    func testProductionIdentityMustMatchAndRequireStoreConfiguration() {
        XCTAssertTrue(record().matches(configuration))
        XCTAssertFalse(record(bundleID: "another.app").matches(configuration))
        XCTAssertFalse(record(appID: 10).matches(configuration))
        XCTAssertFalse(record(appID: nil).matches(configuration))
        for value in ["", "0", "-1", "+123", "123 456", "$(NINHO_APP_STORE_ID)", "18446744073709551616", "１２３"] {
            XCTAssertFalse(record().matches(AppAcquisitionConfiguration(bundleID: "test.ninho", appID: value)), value)
        }
    }

    func testRecordRejectsUnknownSchemaEmptyEvidenceAndExcessiveSize() {
        XCTAssertFalse(record(version: 2).matches(configuration))
        XCTAssertFalse(record(signedTransaction: "").matches(configuration))
        XCTAssertFalse(record(signedTransaction: String(repeating: "a", count: 131_073)).matches(configuration))
    }

    func testSandboxAllowsApplesMissingAppIDButStillChecksBundleAndConfiguration() {
        XCTAssertTrue(record(appID: nil, environment: .sandbox).matches(configuration))
        XCTAssertFalse(record(bundleID: "other", appID: nil, environment: .sandbox).matches(configuration))
        XCTAssertFalse(record(appID: 99, environment: .sandbox).matches(configuration))
        XCTAssertFalse(record(appID: nil, environment: .sandbox).matches(AppAcquisitionConfiguration(bundleID: "test.ninho", appID: "")))
    }

    func testProtectedRecordRoundTripPreservesEvidenceAndAcquisition() throws {
        let original = record()
        XCTAssertEqual(try JSONDecoder().decode(AppAcquisitionRecord.self, from: JSONEncoder().encode(original)), original)
        XCTAssertThrowsError(try JSONDecoder().decode(AppAcquisitionRecord.self, from: Data("{\"purchased\":true}".utf8)))
    }

    func testMissingConfigurationDoesNotConsultStoreOrCache() async {
        let provider = AcquisitionProviderFixture(record: record())
        let cache = AcquisitionCacheFixture(record: record())
        let service = AppAcquisitionService(configuration: .init(bundleID: "test.ninho", appID: ""), provider: provider, cache: cache)
        let result = await service.open()
        XCTAssertEqual(result, .blocked(.notConfigured))
        let calls = await provider.calls
        let loads = await cache.loads
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(loads, 0)
    }

    func testConfirmedProductionAcquisitionWorksOfflineWithoutExpiryOrStoreCalls() async {
        let oldRecord = record()
        let provider = AcquisitionProviderFixture(failure: .unavailable)
        let cache = AcquisitionCacheFixture(record: oldRecord)
        let service = AppAcquisitionService(configuration: configuration, provider: provider, cache: cache)
        let result = await service.open()
        XCTAssertEqual(result, .granted(oldRecord, .deviceCache, nil))
        let calls = await provider.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testStoreVerificationIsPersistedBeforeSubsequentOfflineOpening() async {
        let evidence = record()
        let provider = AcquisitionProviderFixture(record: evidence)
        let cache = AcquisitionCacheFixture()
        let first = await AppAcquisitionService(configuration: configuration, provider: provider, cache: cache).open()
        XCTAssertEqual(first, .granted(evidence, .store, nil))
        let offline = AcquisitionProviderFixture(failure: .unavailable)
        let second = await AppAcquisitionService(configuration: configuration, provider: offline, cache: cache).open()
        XCTAssertEqual(second, .granted(evidence, .deviceCache, nil))
        let calls = await provider.calls
        XCTAssertEqual(calls, [false])
    }

    func testSandboxVerificationIsNotPersistedAsPaidProductionAcquisition() async {
        let sandbox = record(appID: nil, environment: .sandbox)
        let provider = AcquisitionProviderFixture(record: sandbox)
        let cache = AcquisitionCacheFixture()
        let result = await AppAcquisitionService(configuration: configuration, provider: provider, cache: cache).open()
        XCTAssertEqual(result, .granted(sandbox, .store, nil))
        let writes = await cache.writes
        XCTAssertEqual(writes, 0)
    }

    func testSandboxAndOtherAppCachesNeverAuthorizeOfflineProduction() async {
        for evidence in [record(appID: nil, environment: .sandbox), record(bundleID: "other"), record(appID: 99), record(version: 2)] {
            let provider = AcquisitionProviderFixture(failure: .unavailable)
            let cache = AcquisitionCacheFixture(record: evidence)
            let result = await AppAcquisitionService(configuration: configuration, provider: provider, cache: cache).open()
            XCTAssertEqual(result, .blocked(.unavailable))
        }
    }

    func testUnverifiedAcquisitionIsBlockedAndNeverSaved() async {
        let provider = AcquisitionProviderFixture(failure: .unverified)
        let cache = AcquisitionCacheFixture()
        let result = await AppAcquisitionService(configuration: configuration, provider: provider, cache: cache).open()
        XCTAssertEqual(result, .blocked(.unverified))
        let writes = await cache.writes
        XCTAssertEqual(writes, 0)
    }

    func testVerifiedWrongAppIsBlockedAndNotCached() async {
        let provider = AcquisitionProviderFixture(record: record(bundleID: "other"))
        let cache = AcquisitionCacheFixture()
        let result = await AppAcquisitionService(configuration: configuration, provider: provider, cache: cache).open()
        XCTAssertEqual(result, .blocked(.wrongApplication))
        let writes = await cache.writes
        XCTAssertEqual(writes, 0)
    }

    func testOfflineFirstLaunchRequiresAcquisition() async {
        let provider = AcquisitionProviderFixture(failure: .unavailable)
        let cache = AcquisitionCacheFixture()
        let result = await AppAcquisitionService(configuration: configuration, provider: provider, cache: cache).open()
        XCTAssertEqual(result, .blocked(.unavailable))
        let writes = await cache.writes
        XCTAssertEqual(writes, 0)
    }

    func testRestoreUsesExplicitRefreshAndPreservesLicenseOnNetworkFailure() async {
        let provider = AcquisitionProviderFixture(failure: .unavailable)
        let cache = AcquisitionCacheFixture(record: record())
        let result = await AppAcquisitionService(configuration: configuration, provider: provider, cache: cache).restore()
        XCTAssertEqual(result, .granted(record(), .deviceCache, .restoreUnavailable))
        let calls = await provider.calls
        let removes = await cache.removes
        XCTAssertEqual(calls, [true])
        XCTAssertEqual(removes, 0)
    }

    func testCancelledRestoreRetainsPriorAcquisition() async {
        let provider = AcquisitionProviderFixture(failure: .cancelled)
        let cache = AcquisitionCacheFixture(record: record())
        let result = await AppAcquisitionService(configuration: configuration, provider: provider, cache: cache).restore()
        XCTAssertEqual(result, .granted(record(), .deviceCache, .restoreCancelled))
        let removes = await cache.removes
        XCTAssertEqual(removes, 0)
    }

    func testTaskCancellationRetainsPriorAcquisitionWithoutReplacingEvidence() async {
        let cache = AcquisitionCacheFixture(record: record())
        let service = AppAcquisitionService(configuration: configuration, provider: CancelledAcquisitionProvider(), cache: cache)
        let result = await service.restore()
        XCTAssertEqual(result, .granted(record(), .deviceCache, .restoreCancelled))
        let writes = await cache.writes
        XCTAssertEqual(writes, 1)
    }

    func testUnverifiedExplicitRefreshDoesNotFallBackToOldConfirmation() async {
        let provider = AcquisitionProviderFixture(failure: .unverified)
        let cache = AcquisitionCacheFixture(record: record())
        let service = AppAcquisitionService(configuration: configuration, provider: provider, cache: cache)
        let result = await service.restore()
        XCTAssertEqual(result, .blocked(.unverified))
        let saved = await cache.record
        XCTAssertNil(saved)
    }

    func testFailedCacheRemovalAfterInvalidVerificationCannotRestoreOldAcquisition() async {
        let provider = AcquisitionProviderFixture(failure: .unverified)
        let cache = AcquisitionCacheFixture(record: record(), failRemove: true)
        let service = AppAcquisitionService(configuration: configuration, provider: provider, cache: cache)
        let rejected = await service.restore()
        XCTAssertEqual(rejected, .blocked(.unverified))
        let retry = await service.open()
        XCTAssertEqual(retry, .blocked(.unverified))
        let restarted = AppAcquisitionService(configuration: configuration, provider: AcquisitionProviderFixture(failure: .unavailable), cache: cache)
        let afterRestart = await restarted.open()
        XCTAssertEqual(afterRestart, .blocked(.unavailable))
    }

    func testFailureToPersistDenialNeverContactsStoreAndPreservesPreviouslyTrustedCache() async {
        let provider = AcquisitionProviderFixture(failure: .unverified)
        let cache = AcquisitionCacheFixture(record: record(), failSuspend: true)
        let service = AppAcquisitionService(configuration: configuration, provider: provider, cache: cache)
        let result = await service.restore()
        XCTAssertEqual(result, .granted(record(), .deviceCache, .restoreUnavailable))
        let calls = await provider.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testFailedRecoveryAfterCancelledRefreshKeepsDenialForNextLaunch() async {
        let cache = AcquisitionCacheFixture(record: record(), failWrite: true)
        let service = AppAcquisitionService(configuration: configuration, provider: AcquisitionProviderFixture(failure: .cancelled), cache: cache)
        let current = await service.restore()
        XCTAssertEqual(current, .granted(record(), .deviceCache, .cacheUnavailable))
        let restarted = AppAcquisitionService(configuration: configuration, provider: AcquisitionProviderFixture(failure: .unavailable), cache: cache)
        let nextLaunch = await restarted.open()
        XCTAssertEqual(nextLaunch, .blocked(.unavailable))
    }

    func testUnreadableCacheRequiresStoreVerification() async {
        let provider = AcquisitionProviderFixture(failure: .unavailable)
        let cache = AcquisitionCacheFixture(record: record(), failRead: true)
        let result = await AppAcquisitionService(configuration: configuration, provider: provider, cache: cache).open()
        XCTAssertEqual(result, .blocked(.unavailable))
    }

    func testCacheWriteFailureAllowsOnlyVerifiedCurrentSessionAndExplainsOfflineLimit() async {
        let provider = AcquisitionProviderFixture(record: record())
        let cache = AcquisitionCacheFixture(failWrite: true)
        let result = await AppAcquisitionService(configuration: configuration, provider: provider, cache: cache).open()
        XCTAssertEqual(result, .granted(record(), .store, .cacheUnavailable))
        let saved = await cache.record
        XCTAssertNil(saved)
    }
}

private struct CancelledAcquisitionProvider: AppAcquisitionProvider {
    func verifiedAcquisition(refresh: Bool) async throws -> AppAcquisitionRecord { throw CancellationError() }
}

private actor AcquisitionProviderFixture: AppAcquisitionProvider {
    private let result: Result<AppAcquisitionRecord, AppAcquisitionFailure>
    private(set) var calls: [Bool] = []
    init(record: AppAcquisitionRecord) { result = .success(record) }
    init(failure: AppAcquisitionFailure) { result = .failure(failure) }
    func verifiedAcquisition(refresh: Bool) throws -> AppAcquisitionRecord {
        calls.append(refresh)
        return try result.get()
    }
}

private actor AcquisitionCacheFixture: AppAcquisitionCache {
    private(set) var record: AppAcquisitionRecord?
    private(set) var loads = 0
    private(set) var writes = 0
    private(set) var removes = 0
    private let failRead: Bool
    private let failWrite: Bool
    private let failRemove: Bool
    private let failSuspend: Bool
    init(record: AppAcquisitionRecord? = nil, failRead: Bool = false, failWrite: Bool = false,
         failRemove: Bool = false, failSuspend: Bool = false) {
        self.record = record
        self.failRead = failRead
        self.failWrite = failWrite
        self.failRemove = failRemove
        self.failSuspend = failSuspend
    }
    func load() throws -> AppAcquisitionRecord? {
        loads += 1
        if failRead { throw AppAcquisitionFailure.unavailable }
        return record
    }
    func save(_ record: AppAcquisitionRecord) throws {
        if failWrite { throw AppAcquisitionFailure.unavailable }
        writes += 1
        self.record = record
    }
    func suspend() throws {
        if failSuspend { throw AppAcquisitionFailure.unavailable }
        record = nil
    }
    func remove() throws {
        if failRemove { throw AppAcquisitionFailure.unavailable }
        removes += 1
        record = nil
    }
}
