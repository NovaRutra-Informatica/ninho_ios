import XCTest
@testable import Ninho

@MainActor final class SystemRouteRequestsTests: XCTestCase {
    func testFocusShortcutQueuesOnlyNavigation() async throws {
        let requests = SystemRouteRequests.shared
        requests.pendingRoute = nil
        defer { requests.pendingRoute = nil }
        _ = try await OpenNinhoFocusIntent().perform()
        XCTAssertEqual(requests.pendingRoute, "focus")
        XCTAssertTrue(OpenNinhoFocusIntent.openAppWhenRun)
    }
    func testReviewsShortcutReplacesAndCanBeConsumedAfterWelcome() async throws {
        let requests = SystemRouteRequests.shared
        defer { requests.pendingRoute = nil }
        requests.request("focus")
        _ = try await OpenNinhoReviewsIntent().perform()
        XCTAssertEqual(requests.pendingRoute, "reviews")
        requests.pendingRoute = nil
        XCTAssertNil(requests.pendingRoute)
    }
}
