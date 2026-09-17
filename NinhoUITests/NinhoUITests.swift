import XCTest

/// Each test owns a UUID profile; relaunch must preserve it.
@MainActor final class NinhoUITests: XCTestCase {
    private var app: XCUIApplication!
    private var profile = ""

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        profile = UUID().uuidString
        app = XCUIApplication()
        app.launchEnvironment["NINHO_TEST_PROFILE"] = profile
        let reviewDueSeconds = name.contains("DueReview") ? 15 : nil
        launch(reset: true, reviewDueSeconds: reviewDueSeconds)
    }

    @MainActor override func tearDown() async throws {
        if let app, app.state != .notRunning {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name; attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(reset: Bool = false, focusSeconds: Int = 60, withMaterial: Bool = false, reviewDueSeconds: Int? = nil) {
        app.launchArguments = ["--uitesting", "--disable-ai", "--test-focus-seconds", "\(focusSeconds)", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        if reset { app.launchArguments.append("--reset-test-data") }
        if withMaterial { app.launchArguments.append("--with-test-material") }
        if let reviewDueSeconds { app.launchArguments += ["--test-review-due-seconds", "\(reviewDueSeconds)"] }
        app.launch()
        XCTAssertTrue(element("screen.today").waitForExistence(timeout: 15))
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(id)
        // Scroll to materialize lazy rows.
        for _ in 0..<7 {
            if target.exists && target.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(target.waitForExistence(timeout: 8), "Missing \(id)", file: file, line: line)
        XCTAssertTrue(target.isHittable, "Not hittable: \(id)", file: file, line: line)
        waitEnabled(id)
        target.tap()
    }

    private func waitEnabled(_ id: String) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element(id))
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
    }

    private func tab(_ name: String) {
        let labels = ["today": "Hoje", "studies": "Estudos", "reviews": "Revisões", "agenda": "Agenda", "more": "Mais"]
        let byID = app.tabBars.buttons["tab.\(name)"]
        let target = byID.exists ? byID : app.tabBars.buttons[labels[name]!]
        XCTAssertTrue(target.waitForExistence(timeout: 8)); target.tap()
    }

    private func type(_ id: String, _ text: String, replacing previous: String = "") {
        tap(id)
        let target = element(id)
        if !previous.isEmpty { target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count)) }
        target.typeText(text)
    }

    private func savedForm() {
        tap("form.save")
        XCTAssertTrue(element("form.save").waitForNonExistence(timeout: 8))
        XCTAssertFalse(element("app.error").exists)
    }

    private func openFixtureLesson() {
        tab("studies")
        tap("program.test-program"); tap("subject.test-subject")
        tap("course.test-course"); tap("lesson.test-lesson")
    }

    private func back() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(button.waitForExistence(timeout: 8)); button.tap()
    }

    func testEveryMainScreenAndLandscapeLayout() {
        for screen in ["studies", "reviews", "agenda", "more", "today"] {
            tab(screen); XCTAssertTrue(element("screen.\(screen)").waitForExistence(timeout: 8))
        }
        tab("more")
        for screen in ["materials", "focus", "progress", "assistant", "settings"] {
            tap("more.\(screen)"); XCTAssertTrue(element("screen.\(screen)").waitForExistence(timeout: 8))
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 8))
            XCTAssertFalse(element("app.error").exists)
            XCUIDevice.shared.orientation = .portrait
            back()
        }
    }

    func testCourseSubjectModuleAndLessonCreationPersistAcrossRelaunch() {
        tab("studies"); tap("add.program")
        XCTAssertFalse(element("form.save").isEnabled)
        type("form.name", "Curso sintético"); savedForm()
        app.buttons.containing(.staticText, identifier: "Curso sintético").firstMatch.tap()
        tap("add.subject"); type("form.name", "Matéria sintética"); savedForm()
        app.buttons.containing(.staticText, identifier: "Matéria sintética").firstMatch.tap()
        tap("add.course"); type("form.title", "Módulo sintético"); savedForm()
        app.buttons.containing(.staticText, identifier: "Módulo sintético").firstMatch.tap()
        tap("add.lesson"); type("form.title", "Aula sintética"); savedForm()
        XCTAssertTrue(app.staticTexts["Aula sintética"].waitForExistence(timeout: 8))
        app.terminate(); launch()
        tab("studies")
        app.buttons.containing(.staticText, identifier: "Curso sintético").firstMatch.tap()
        app.buttons.containing(.staticText, identifier: "Matéria sintética").firstMatch.tap()
        app.buttons.containing(.staticText, identifier: "Módulo sintético").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Aula sintética"].waitForExistence(timeout: 8))
    }

    func testLessonNotesStatusAndEditingPreserveEachOther() {
        openFixtureLesson()
        tap("lesson.status"); app.buttons["Em andamento"].tap()
        type("lesson.notes", "Resumo escrito no teste."); tap("lesson.saveNotes")
        app.swipeDown(); app.navigationBars.buttons["Editar aula"].tap()
        type("form.title", "Aula revisada", replacing: "Aula de teste"); savedForm()
        app.terminate(); launch(); openFixtureLesson()
        XCTAssertTrue(app.navigationBars["Aula revisada"].waitForExistence(timeout: 8))
        XCTAssertTrue(element("lesson.status").label.contains("Em andamento") || String(describing: element("lesson.status").value).contains("Em andamento"))
        tap("lesson.notes")
        XCTAssertEqual(element("lesson.notes").value as? String, "Resumo escrito no teste.")
    }

    private func review(_ rating: String) {
        tab("reviews")
        XCTAssertFalse(element("review.answer").exists)
        tap("review.reveal")
        XCTAssertEqual(element("review.answer").label, "4")
        tap("review.\(rating)")
        XCTAssertTrue(element("review.answer").waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Por hoje, tudo em dia"].waitForExistence(timeout: 8))
        app.terminate(); launch(); tab("reviews")
        XCTAssertTrue(app.staticTexts["Por hoje, tudo em dia"].waitForExistence(timeout: 8))
    }

    func testAgainReviewSchedulesLaterAndPersists() { review("again") }
    func testHardReviewSchedulesLaterAndPersists() { review("hard") }
    func testGoodReviewSchedulesLaterAndPersists() { review("good") }
    func testEasyReviewSchedulesLaterAndPersists() { review("easy") }

    func testCardCreateEditClassifySuspendAndDelete() {
        tab("reviews"); tap("add.card")
        type("form.question", "Qual é a função de uma chave?")
        type("form.answer", "Identificar um registro."); savedForm()
        app.swipeUp(); app.buttons["Organizar meus cartões"].tap()
        let question = app.buttons["Qual é a função de uma chave?"]
        XCTAssertTrue(question.waitForExistence(timeout: 8)); question.tap()
        type("form.answer", "Identificar unicamente um registro.", replacing: "Identificar um registro."); savedForm()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'card.'")).containing(.button, identifier: "Qual é a função de uma chave?").firstMatch
        row.buttons["Organizar cartão"].tap(); app.buttons["Marcar como desatualizado"].tap()
        XCTAssertTrue(row.staticTexts["Você marcou: precisa atualizar"].waitForExistence(timeout: 8))
        row.buttons["Organizar cartão"].tap(); app.buttons["Pausar revisões"].tap()
        XCTAssertTrue(row.staticTexts["Pausado"].waitForExistence(timeout: 8))
        row.buttons["Organizar cartão"].tap(); app.buttons["Retomar revisões"].tap()
        XCTAssertTrue(row.staticTexts["Pausado"].waitForNonExistence(timeout: 8))
        row.buttons["Organizar cartão"].tap(); app.buttons["Excluir cartão"].tap()
        app.buttons["Excluir"].tap()
        XCTAssertTrue(question.waitForNonExistence(timeout: 8))
    }

    func testAgendaExamAndTaskCreateEditCompleteDelete() {
        tab("agenda"); tap("add.exam")
        type("form.title", "Prova sintética"); savedForm()
        let exam = app.buttons["Prova sintética"]
        XCTAssertTrue(exam.waitForExistence(timeout: 8)); exam.tap()
        type("form.title", "Prova revisada", replacing: "Prova sintética"); savedForm()
        tap("add.task"); type("form.title", "Revisar notas"); savedForm()
        app.buttons["Concluir tarefa"].tap()
        XCTAssertTrue(app.buttons["Reabrir tarefa"].waitForExistence(timeout: 8))
        app.terminate(); launch(); tab("agenda")
        for _ in 0..<4 { if app.buttons["Prova revisada"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["Prova revisada"].exists)
        app.buttons["Prova revisada"].swipeLeft(); app.buttons["Excluir"].tap(); app.buttons["Excluir"].tap()
        XCTAssertTrue(app.buttons["Prova revisada"].waitForNonExistence(timeout: 8))
        for _ in 0..<4 { if app.buttons["Revisar notas"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["Reabrir tarefa"].exists)
        app.buttons["Revisar notas"].swipeLeft(); app.buttons["Excluir"].tap(); app.buttons["Excluir"].tap()
        XCTAssertTrue(app.buttons["Revisar notas"].waitForNonExistence(timeout: 8))
    }

    func testLessonFocusPauseRelaunchResumeAndFinish() {
        openFixtureLesson(); tap("lesson.timer"); tap("focus.start")
        XCTAssertTrue(element("focus.pause").waitForExistence(timeout: 8))
        let changed = NSPredicate(format: "label != %@", element("focus.elapsed").label)
        expectation(for: changed, evaluatedWith: element("focus.elapsed")); waitForExpectations(timeout: 4)
        tap("focus.pause")
        waitEnabled("focus.resume")
        let remaining = element("focus.elapsed").label
        app.terminate(); launch(); openFixtureLesson(); tap("lesson.timer")
        XCTAssertTrue(element("focus.resume").waitForExistence(timeout: 8))
        XCTAssertEqual(element("focus.elapsed").label, remaining)
        tap("focus.resume"); tap("focus.finish")
        XCTAssertTrue(element("focus.start").waitForExistence(timeout: 8))
        waitEnabled("focus.start")
        XCTAssertTrue(element("app.notice").label.contains("Tempo registrado"))
        back()
        XCTAssertTrue(element("lesson.time").label.contains("1 sessão"))
        app.terminate(); launch(); openFixtureLesson()
        XCTAssertTrue(element("lesson.time").label.contains("1 sessão"))
    }

    func testFocusAutoCompletesOnceAndResetRequiresConfirmation() {
        app.terminate(); launch(focusSeconds: 2)
        openFixtureLesson(); tap("lesson.timer"); tap("focus.start")
        XCTAssertTrue(element("app.notice").waitForExistence(timeout: 10))
        XCTAssertTrue(element("focus.start").exists)
        back(); XCTAssertTrue(element("lesson.time").label.contains("1 sessão"))
        app.terminate(); launch(focusSeconds: 60)
        openFixtureLesson(); tap("lesson.timer"); tap("focus.start"); tap("focus.reset")
        XCTAssertTrue(app.buttons["Reiniciar sem registrar"].waitForExistence(timeout: 8))
        app.buttons["Reiniciar sem registrar"].tap()
        XCTAssertTrue(element("focus.start").waitForExistence(timeout: 8))
        back(); XCTAssertTrue(element("lesson.time").label.contains("1 sessão"))
    }

    func testMaterialsOpensRealFilePickerAndCancelKeepsCollection() {
        openFixtureLesson(); tap("lesson.addMaterial")
        let cancel = app.buttons["Cancelar"].exists ? app.buttons["Cancelar"] : app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        XCTAssertTrue(element("lesson.addMaterial").waitForExistence(timeout: 8))
        XCTAssertFalse(element("app.error").exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'material.'")).count, 0)
    }

    func testImportedFixturePDFPreviewNotesAndRemovalPersist() {
        app.terminate(); launch(withMaterial: true)
        openFixtureLesson()
        let file = app.buttons.containing(.staticText, identifier: "test-material.pdf").firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10)); file.tap()
        tap("material.open")
        XCTAssertTrue(element("material.pdf").waitForExistence(timeout: 10))
        XCTAssertFalse(element("material.pdfError").exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "PDF sintético aberto pelo PDFKit"; screenshot.lifetime = .keepAlways
        add(screenshot)
        back(); type("form.notes", "Página 1: resumo sintético."); tap("form.save")
        app.terminate(); launch()
        openFixtureLesson(); XCTAssertTrue(file.waitForExistence(timeout: 10)); file.tap()
        tap("form.notes")
        XCTAssertEqual(element("form.notes").value as? String, "Página 1: resumo sintético.")
        app.swipeUp(); app.buttons["Remover da biblioteca"].tap(); app.buttons["Remover"].tap()
        XCTAssertTrue(file.waitForNonExistence(timeout: 8))
        app.terminate(); launch(); openFixtureLesson()
        XCTAssertFalse(file.exists)
    }

    func testSettingsPersistAndUnavailableAssistantDoesNotInventAnswers() {
        tab("more"); tap("more.settings")
        type("settings.name", "Pessoa sintética", replacing: "Teste")
        let soundBefore = element("settings.sound").value as? String
        tap("settings.sound")
        tap("settings.reducedMotion"); tap("settings.save")
        waitEnabled("settings.save")
        app.terminate(); launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Pessoa'")).firstMatch.exists)
        tab("more"); tap("more.settings")
        XCTAssertEqual(element("settings.name").value as? String, "Pessoa sintética")
        XCTAssertEqual(element("settings.reducedMotion").value as? String, "1")
        XCTAssertEqual(element("settings.sound").value as? String, soundBefore == "1" ? "0" : "1")
        back(); tap("more.assistant")
        XCTAssertTrue(element("assistant.unavailable").waitForExistence(timeout: 8))
        XCTAssertFalse(element("assistant.generating").exists)
        XCTAssertFalse(element("assistant.send").exists && element("assistant.send").isEnabled)
        XCTAssertFalse(element("app.error").exists)
    }

    func testBackupExportPreparesRealShareAndRestorePickerCanBeCancelled() {
        tab("more"); tap("more.settings"); tap("settings.export")
        XCTAssertTrue(element("settings.shareBackup").waitForExistence(timeout: 15))
        XCTAssertFalse(element("app.error").exists)
        tap("settings.restore")
        let cancel = app.buttons["Cancelar"].exists ? app.buttons["Cancelar"] : app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        XCTAssertTrue(element("settings.restore").waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Restaurar coleção"].exists)
        app.terminate(); launch()
        openFixtureLesson()
        XCTAssertTrue(element("lesson.timer").exists)
    }

    func testInvalidLinkAndTimeKeepDraftsAndAllowCorrection() {
        openFixtureLesson(); app.navigationBars.buttons["Editar aula"].tap()
        type("form.url", "javascript:invalid")
        tap("form.save")
        if app.buttons["Entendi"].waitForExistence(timeout: 2) { app.buttons["Entendi"].tap() }
        XCTAssertTrue(element("form.error").waitForExistence(timeout: 8))
        XCTAssertEqual(element("form.url").value as? String, "javascript:invalid")
        type("form.url", "https://example.com/aula", replacing: "javascript:invalid")
        savedForm()

        tab("agenda"); tap("add.exam"); type("form.title", "Prova com horário")
        let time = app.textFields["Horário (HH:mm, opcional)"]
        XCTAssertTrue(time.waitForExistence(timeout: 8)); time.tap(); time.typeText("25:99")
        tap("form.save")
        if app.buttons["Entendi"].waitForExistence(timeout: 2) { app.buttons["Entendi"].tap() }
        XCTAssertTrue(element("form.error").waitForExistence(timeout: 8))
        XCTAssertEqual(element("form.title").value as? String, "Prova com horário")
        time.tap(); time.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "10:30")
        savedForm()
        XCTAssertTrue(app.buttons["Prova com horário"].waitForExistence(timeout: 8))
    }

    func testUnsavedLessonNotesSurviveTimerAndPDFRoundTrips() {
        app.terminate(); launch(withMaterial: true)
        openFixtureLesson()
        let draft = "Rascunho ainda não salvo: manter ao estudar."
        type("lesson.notes", draft)
        for _ in 0..<5 { app.swipeDown() }
        tap("lesson.timer")
        XCTAssertTrue(element("screen.focus").waitForExistence(timeout: 8)); back()
        tap("lesson.notes")
        XCTAssertEqual(element("lesson.notes").value as? String, draft)
        for _ in 0..<5 { app.swipeDown() }
        let file = app.buttons.containing(.staticText, identifier: "test-material.pdf").firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 8)); file.tap()
        tap("material.open")
        XCTAssertTrue(element("material.pdf").waitForExistence(timeout: 10))
        back(); back()
        tap("lesson.notes")
        XCTAssertEqual(element("lesson.notes").value as? String, draft)
        tap("lesson.saveNotes"); waitEnabled("lesson.saveNotes")
        app.terminate(); launch(); openFixtureLesson(); tap("lesson.notes")
        XCTAssertEqual(element("lesson.notes").value as? String, draft)
    }

    func testUnsavedMaterialNotesAndOrganizationSurvivePDFRoundTrip() {
        app.terminate(); launch(withMaterial: true)
        openFixtureLesson()
        let file = app.buttons.containing(.staticText, identifier: "test-material.pdf").firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 8)); file.tap()
        let draft = "Anotação nova antes de reler o PDF."
        type("form.notes", draft)
        tap("material.subject"); app.buttons["Geral"].tap()
        for _ in 0..<5 { app.swipeDown() }
        tap("material.open")
        XCTAssertTrue(element("material.pdf").waitForExistence(timeout: 10)); back()
        tap("form.notes")
        XCTAssertEqual(element("form.notes").value as? String, draft)
        let subject = element("material.subject"), lesson = element("material.lesson")
        XCTAssertTrue((subject.label + String(describing: subject.value)).contains("Geral"))
        XCTAssertTrue((lesson.label + String(describing: lesson.value)).contains("Na matéria, sem aula"))
        tap("form.save"); waitEnabled("form.save")
        app.terminate(); launch(); tab("more"); tap("more.materials")
        XCTAssertTrue(file.waitForExistence(timeout: 8)); file.tap(); tap("form.notes")
        XCTAssertEqual(element("form.notes").value as? String, draft)
        XCTAssertTrue((element("material.subject").label + String(describing: element("material.subject").value)).contains("Geral"))
    }

    func testDueReviewAppearsWithoutNavigationOrStoreMutation() {
        // Only the fixture's initial dueAt is shortened.
        tab("reviews")
        XCTAssertTrue(app.staticTexts["Por hoje, tudo em dia"].waitForExistence(timeout: 8))
        XCTAssertFalse(element("review.reveal").exists)
        XCTAssertTrue(element("review.reveal").waitForExistence(timeout: 25))
        XCTAssertTrue(element("card.test-card").exists)
        XCTAssertFalse(element("review.answer").exists)
        tap("review.reveal"); XCTAssertEqual(element("review.answer").label, "4")
    }

    func testDueReviewAppearsWhenReturningFromBackground() {
        tab("reviews")
        XCTAssertTrue(app.staticTexts["Por hoje, tudo em dia"].waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 8))
        let deadline = Date().addingTimeInterval(16)
        let elapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Date() >= deadline }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [elapsed], timeout: 20), .completed)
        app.activate()
        XCTAssertTrue(element("review.reveal").waitForExistence(timeout: 8))
        XCTAssertTrue(element("card.test-card").exists)
        XCTAssertFalse(element("review.answer").exists)
    }
}
