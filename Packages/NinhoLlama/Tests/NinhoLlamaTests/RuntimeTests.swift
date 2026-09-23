import Foundation
import XCTest
@testable import NinhoLlama

final class RuntimeTests: XCTestCase {
    func testCancellationPreventsOpeningOrGeneratingWithoutAnyWeights() {
        let cancellation = ModelCancellation(); cancellation.cancel()
        XCTAssertThrowsError(try NinhoLlamaRuntime.validate(path: "/no-model.gguf", cancellation: cancellation)) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertThrowsError(try NinhoLlamaRuntime.generate(path: "/no-model.gguf", instructions: "test", prompt: "test", cancellation: cancellation)) {
            XCTAssertTrue($0 is CancellationError)
        }
    }
    func testMissingFileFailsWithoutNetworkOrGeneratedFallback() {
        XCTAssertThrowsError(try NinhoLlamaRuntime.validate(path: "/no-model.gguf", cancellation: ModelCancellation())) {
            guard case LocalModelError.load = $0 else { return XCTFail("Expected a model-loading error") }
        }
    }
}
