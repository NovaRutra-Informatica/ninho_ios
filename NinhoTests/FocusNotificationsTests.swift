import XCTest
import UserNotifications
import NinhoCore
@testable import Ninho

@MainActor final class FocusNotificationsTests: XCTestCase {
    func testFreshInstanceCancelsPriorProcessRequestsAndDeliveredAlertsOnlyForFocus() async {
        let center = NotificationCenterDouble()
        center.pending = ["ninho.focus.finished.old-process", "ninho.focus.finished-other", "other-feature"]
        center.delivered = ["ninho.focus.finished", "ninho.focus.finished.old-delivery", "other-feature"]
        await FocusNotifications(center: center).cancel()
        XCTAssertEqual(center.pending, ["ninho.focus.finished-other", "other-feature"])
        XCTAssertEqual(center.delivered, ["other-feature"])
        XCTAssertEqual(center.permissionRequests, 0)
    }

    func testLateCancellationReadCannotRemoveANewerScheduledTimer() async throws {
        let center = NotificationCenterDouble()
        center.pending = ["ninho.focus.finished.old", "other-feature"]
        center.holdNextPendingRead = true
        let notifications = FocusNotifications(center: center)
        let cancelling = Task { await notifications.cancel() }
        for _ in 0..<100 where center.pendingContinuation == nil { try await Task.sleep(for: .milliseconds(1)) }
        guard let continuation = center.pendingContinuation else {
            cancelling.cancel(); XCTFail("The cancellation did not reach the pending-request read."); return
        }
        defer {
            if let pending = center.pendingContinuation {
                center.pendingContinuation = nil; pending.resume(returning: [])
            }
        }
        var timer = FocusTimer()
        try timer.configure(subjectId: "", minutes: 10); try timer.start()
        let result = await notifications.update(timer)
        XCTAssertTrue(result.contains("agendado"))
        let newlyScheduled = try XCTUnwrap(center.added.last?.identifier)
        center.pendingContinuation = nil
        continuation.resume(returning: ["ninho.focus.finished.old", newlyScheduled, "other-feature"])
        await cancelling.value
        XCTAssertEqual(Set(center.pending), [newlyScheduled, "other-feature"])
        XCTAssertEqual(center.permissionRequests, 0)
    }
}

@MainActor private final class NotificationCenterDouble: FocusNotificationCenter {
    var pending: [String] = []
    var delivered: [String] = []
    var added: [UNNotificationRequest] = []
    var permissionRequests = 0
    var holdNextPendingRead = false
    var pendingContinuation: CheckedContinuation<[String], Never>?
    func requestPermission() async throws -> Bool { permissionRequests += 1; return true }
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func pendingIdentifiers() async -> [String] {
        if holdNextPendingRead {
            holdNextPendingRead = false
            return await withCheckedContinuation { pendingContinuation = $0 }
        }
        return pending
    }
    func deliveredIdentifiers() async -> [String] { delivered }
    func removePending(_ identifiers: [String]) { pending.removeAll { identifiers.contains($0) } }
    func removeDelivered(_ identifiers: [String]) { delivered.removeAll { identifiers.contains($0) } }
    func add(_ request: UNNotificationRequest) async throws { added.append(request); pending.append(request.identifier) }
}
