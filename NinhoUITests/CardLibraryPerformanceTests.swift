import XCTest

@MainActor final class CardLibraryPerformanceTests: XCTestCase {
    func testLibraryWith71Cards() { measureLibrary(count: 71) }
    func testLibraryWith1000Cards() { measureLibrary(count: 1_000) }
    func testLibraryWith5000Cards() { measureLibrary(count: 5_000) }

    private func measureLibrary(count: Int) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["NINHO_TEST_PROFILE"] = UUID().uuidString
        app.launchArguments = ["--uitesting", "--disable-ai", "--reset-test-data", "--test-card-count", "\(count)",
                               "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["screen.today"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Revisões"].tap()
        let library = app.buttons["Organizar meus cartões"]
        for _ in 0..<3 where !library.isHittable { app.swipeUp() }
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        let options = XCTMeasureOptions(); options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()], options: options) {
            library.tap()
            XCTAssertTrue(app.buttons["Pergunta de carga 0"].waitForExistence(timeout: 10))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(library.waitForExistence(timeout: 10))
        }
        library.tap()
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Pergunta de carga \(count - 1)")
        let last = app.buttons["Pergunta de carga \(count - 1)"]
        XCTAssertTrue(last.waitForExistence(timeout: 5)); last.tap()
        XCTAssertTrue(app.navigationBars["Editar cartão"].waitForExistence(timeout: 5))
    }
}
