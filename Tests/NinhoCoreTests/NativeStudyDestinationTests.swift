import XCTest
@testable import NinhoCore

final class NativeStudyDestinationTests: XCTestCase {
    func testWidgetLinksRoundTripToKnownDestinations() throws {
        for destination in NativeStudyDestination.allCases {
            XCTAssertEqual(NativeStudyDestination(url: destination.url), destination)
        }
        XCTAssertEqual(NativeStudyDestination(url: try XCTUnwrap(URL(string: "NINHO://FOCUS/"))), .focus)
        XCTAssertEqual(NativeStudyDestination.focus.tabIndex, 2)
        XCTAssertEqual(NativeStudyDestination.reviews.tabIndex, 3)
    }

    func testExternalLinksCannotImportFilesMutateRecordsOrSmuggleParameters() throws {
        for link in ["https://focus", "ninho://focus?start=true", "ninho://focus#start",
                     "ninho://focus/import", "ninho://user@focus", "ninho://focus:443",
                     "ninho://delete", "file:///state.json", "ninho:///focus"] {
            XCTAssertNil(NativeStudyDestination(url: try XCTUnwrap(URL(string: link))), link)
        }
    }
}
