import XCTest
import Foundation
import NinhoCore
@testable import Ninho

@MainActor final class CompactBackupCoordinatorTests: XCTestCase {
    private let date = StudyEngine.parseTimestamp("2026-09-23T12:00:00Z")!

    func testAvailableCloudRequiresOptInAndExplicitDisablePersists() async throws {
        let root = try temporary()
        let local = root.appendingPathComponent("local"), cloud = root.appendingPathComponent("cloud")
        let coordinator = make(local: local, cloud: cloud)
        let automatic = await coordinator.cloudEnabled()
        XCTAssertFalse(automatic)
        try await coordinator.setCloudEnabled(true)
        let activated = await coordinator.cloudEnabled()
        XCTAssertTrue(activated)
        try await coordinator.setCloudEnabled(false)
        let reopened = make(local: local, cloud: cloud)
        let enabled = await reopened.cloudEnabled()
        XCTAssertFalse(enabled)
        let status = try await reopened.save(fixture(), activity: LocalActivity(), at: date)
        XCTAssertNotNil(status.local)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.path))
    }

    func testUnavailableCloudRejectsActivationAndKeepsLocalCopy() async throws {
        let root = try temporary()
        let coordinator = CompactBackupCoordinator(localDirectory: root, usesCloud: true, cloudContainer: { nil })
        do { try await coordinator.setCloudEnabled(true); XCTFail("Unavailable cloud was enabled") }
        catch is CloudBackupUnavailable { }
        let enabled = await coordinator.cloudEnabled()
        XCTAssertFalse(enabled)
        let status = try await coordinator.save(fixture(), activity: LocalActivity(), at: date)
        XCTAssertNotNil(status.local)
        XCTAssertFalse(status.cloudAvailable)
        XCTAssertFalse(status.cloudEnabled)
        XCTAssertTrue(status.cloudMessage.contains("não protege"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cloud-preference.json").path))
    }

    func testAutomaticSaveCreatesItsOwnCloudDirectoryWithoutSelection() async throws {
        let root = try temporary(), cloud = root.appendingPathComponent("cloud")
        let coordinator = make(local: root.appendingPathComponent("local"), cloud: cloud)
        try await coordinator.setCloudEnabled(true)
        let status = try await coordinator.save(fixture(), activity: LocalActivity(), at: date)
        let file = cloud.appendingPathComponent("Documents/CompactBackups").appendingPathComponent(try XCTUnwrap(status.local).url.lastPathComponent)
        XCTAssertEqual(try CompactBackup.read(from: file).state, fixture())
        XCTAssertTrue(status.cloudAvailable)
        XCTAssertTrue(status.cloudEnabled)
    }

    func testUnavailableInitialCloudRecoveryPreservesProtectionInsteadOfReportingEmpty() async throws {
        let root = try temporary()
        let coordinator = CompactBackupCoordinator(localDirectory: root, usesCloud: true, cloudContainer: { nil })
        try await coordinator.requireInitialCloudRecovery()
        do {
            _ = try await coordinator.initialCloudRecovery(attempts: 1)
            XCTFail("Unavailable cloud was treated as an empty cloud")
        } catch is CloudBackupUnavailable { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("cloud-recovery-required.json").path))
    }

    func testInitialRecoveryProtectionSurvivesRestartAndNeverOverwritesPriorCloudCopy() async throws {
        let root = try temporary(), cloud = root.appendingPathComponent("cloud"), local = root.appendingPathComponent("local")
        let file = cloud.appendingPathComponent("Documents/CompactBackups/Ninho-2026-09-23.compact.zip")
        _ = try CompactBackup.write(fixture(), to: file, at: date)
        let original = try Data(contentsOf: file)
        let coordinator = make(local: local, cloud: cloud)
        try await coordinator.setCloudEnabled(true)
        try await coordinator.requireInitialCloudRecovery()
        var replacement = fixture(); replacement.settings.name = "Coleção nova"
        let reopened = make(local: local, cloud: cloud)
        let status = try await reopened.save(replacement, activity: LocalActivity(), at: date)
        XCTAssertTrue(status.cloudRecoveryAvailable)
        XCTAssertEqual(try Data(contentsOf: file), original)
        let preservedLocal = try await reopened.local.newest()
        XCTAssertEqual(preservedLocal?.state, replacement)
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.appendingPathComponent("cloud-recovery-required.json").path))
    }

    func testConfirmedEmptyCloudAllowsFirstAutomaticCopy() async throws {
        let root = try temporary(), cloud = root.appendingPathComponent("cloud"), local = root.appendingPathComponent("local")
        let coordinator = make(local: local, cloud: cloud)
        try await coordinator.setCloudEnabled(true)
        try await coordinator.requireInitialCloudRecovery()
        let status = try await coordinator.save(fixture(), activity: LocalActivity(), at: date)
        XCTAssertFalse(status.cloudRecoveryAvailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent("cloud-recovery-required.json").path))
        let restored = try await coordinator.initialCloudRecovery(attempts: 1)
        let copy = try XCTUnwrap(restored)
        defer { try? FileManager.default.removeItem(at: copy.url) }
        XCTAssertEqual(try CompactBackup.read(from: copy.url).state, fixture())
    }

    func testInitialRecoveryRetriesAnIncompleteListingAndRestoresOnlyAfterItCompletes() async throws {
        let root = try temporary(), cloud = root.appendingPathComponent("cloud")
        let file = cloud.appendingPathComponent("Documents/CompactBackups/Ninho-2026-09-23.compact.zip")
        _ = try CompactBackup.write(fixture(), to: file, at: date)
        let attempts = CloudDiscoveryAttempts()
        let coordinator = CompactBackupCoordinator(localDirectory: root.appendingPathComponent("local"), usesCloud: true,
            cloudContainer: { cloud }, discover: { _ in
                let count = await attempts.increment()
                return CloudSnapshotListing(urls: [file], complete: count > 1)
            })
        let recovered = try await coordinator.initialCloudRecovery(attempts: 2, retryDelay: .zero)
        let copy = try XCTUnwrap(recovered)
        defer { try? FileManager.default.removeItem(at: copy.url) }
        XCTAssertEqual(try CompactBackup.read(from: copy.url).state, fixture())
        let count = await attempts.count
        XCTAssertEqual(count, 2)
        let uploading = await coordinator.cloudEnabled()
        XCTAssertFalse(uploading)
    }

    func testPendingRecoveryStopsAfterBoundedAttemptsAndCancellationPropagates() async throws {
        let root = try temporary(), cloud = root.appendingPathComponent("cloud")
        let attempts = CloudDiscoveryAttempts()
        let coordinator = CompactBackupCoordinator(localDirectory: root.appendingPathComponent("local"), usesCloud: true,
            cloudContainer: { cloud }, discover: { _ in
                _ = await attempts.increment()
                return CloudSnapshotListing(urls: [], complete: false)
            })
        do { _ = try await coordinator.initialCloudRecovery(attempts: 2, retryDelay: .zero); XCTFail("Unfinished discovery was treated as an empty cloud") }
        catch is CloudRecoveryPending { }
        let count = await attempts.count
        XCTAssertEqual(count, 2)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await coordinator.initialCloudRecovery(attempts: 2, retryDelay: .zero)
        }
        do { _ = try await task.value; XCTFail("Cancelled recovery succeeded") }
        catch is CancellationError { }
    }

    func testUnreadableCloudCopiesCannotBeTreatedAsEmpty() async throws {
        let root = try temporary(), cloud = root.appendingPathComponent("cloud")
        let directory = cloud.appendingPathComponent("Documents/CompactBackups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Ninho-2026-09-23.compact.zip")
        let bytes = Data("invalid archive".utf8)
        try bytes.write(to: file)
        let coordinator = make(local: root.appendingPathComponent("local"), cloud: cloud)
        try await coordinator.setCloudEnabled(true)
        try await coordinator.requireInitialCloudRecovery()
        let status = try await coordinator.save(fixture(), activity: LocalActivity(), at: date)
        XCTAssertTrue(status.cloudMessage.contains("validar"))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testDisablingCloudDuringRecoveryPreventsUploadAndReturnsDisabledStatus() async throws {
        let root = try temporary(), cloud = root.appendingPathComponent("cloud"), local = root.appendingPathComponent("local")
        let discovery = SuspendedCloudDiscovery()
        let coordinator = CompactBackupCoordinator(localDirectory: local, usesCloud: true,
            cloudContainer: { cloud }, discover: { _ in await discovery.run() })
        try await coordinator.setCloudEnabled(true)
        try await coordinator.requireInitialCloudRecovery()
        let state = fixture(), snapshotDate = date
        let saving = Task { try await coordinator.save(state, activity: LocalActivity(), at: snapshotDate) }
        await discovery.waitUntilStarted()
        try await coordinator.setCloudEnabled(false)
        await discovery.finish()
        let status = try await saving.value
        XCTAssertNotNil(status.local)
        XCTAssertFalse(status.cloudEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.appendingPathComponent("cloud-recovery-required.json").path))
        let enabled = await coordinator.cloudEnabled()
        XCTAssertFalse(enabled)
    }

    private func make(local: URL, cloud: URL) -> CompactBackupCoordinator {
        CompactBackupCoordinator(localDirectory: local, usesCloud: true, cloudContainer: { cloud },
            discover: { _ in CloudSnapshotListing(urls: [], complete: true) })
    }

    private func fixture() -> AppState {
        var profile = StudentProfile()
        profile.name = "Pessoa sintética"
        profile.goal = "Aprender frações"
        profile.completedAt = StudyEngine.timestamp(date)
        return AppState(settings: Settings(name: "Pessoa sintética"), profile: profile)
    }

    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NinhoCloudTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}

private actor CloudDiscoveryAttempts {
    private(set) var count = 0
    func increment() -> Int { count += 1; return count }
}

private actor SuspendedCloudDiscovery {
    private var started = false
    private var continuation: CheckedContinuation<CloudSnapshotListing, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run() async -> CloudSnapshotListing {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish() {
        continuation?.resume(returning: CloudSnapshotListing(urls: [], complete: true))
        continuation = nil
    }
}
