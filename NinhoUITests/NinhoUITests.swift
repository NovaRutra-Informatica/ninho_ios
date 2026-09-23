import XCTest

@MainActor final class NinhoUITests: XCTestCase {
    private var app: XCUIApplication!
    private var profile = ""
    private var dismissedTutorials = Set<String>()

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        profile = UUID().uuidString
        dismissedTutorials = []
        app = XCUIApplication()
        app.launchEnvironment["NINHO_TEST_PROFILE"] = profile
        let reviewDueSeconds = name.contains("DueReview") ? 15 : nil
        launch(reset: true, reviewDueSeconds: reviewDueSeconds, withTutorials: name.contains("WithTutorials"), withOnboarding: name.contains("FreshOnboarding"))
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

    private func launch(reset: Bool = false, focusSeconds: Int = 60, withMaterial: Bool = false, reviewDueSeconds: Int? = nil, withTutorials: Bool = false, withOnboarding: Bool = false) {
        app.launchArguments = ["--uitesting", "--disable-ai", "--test-focus-seconds", "\(focusSeconds)", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        if reset { app.launchArguments.append("--reset-test-data") }
        if withMaterial { app.launchArguments.append("--with-test-material") }
        if withTutorials { app.launchArguments.append("--test-tutorials") }
        if withOnboarding { app.launchArguments.append("--test-onboarding") }
        if let reviewDueSeconds { app.launchArguments += ["--test-review-due-seconds", "\(reviewDueSeconds)"] }
        app.launch()
        let screen = withOnboarding ? "screen.welcome" : withTutorials && !dismissedTutorials.contains("today") ? "tutorial.today.modal" : "screen.today"
        XCTAssertTrue(element(screen).waitForExistence(timeout: 15))
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

    private func nativeSwitch(_ id: String) -> XCUIElement {
        let outer = app.switches[id].firstMatch
        for _ in 0..<12 {
            if outer.exists {
                let inner = outer.switches.firstMatch
                let control = inner.exists ? inner : outer
                if control.isHittable { return control }
                if control.frame.maxY < app.navigationBars.firstMatch.frame.maxY {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                        .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)))
                    continue
                }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        }
        XCTAssertTrue(outer.waitForExistence(timeout: 8))
        let inner = outer.switches.firstMatch
        return inner.exists ? inner : outer
    }

    private func setNativeSwitch(_ id: String, value: String) {
        let control = nativeSwitch(id)
        XCTAssertTrue(control.isHittable)
        if control.value as? String != value { control.tap() }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
    }

    private func tab(_ name: String) {
        if name == "agenda" { tab("more"); tap("more.agenda"); dismissTutorialIfNeeded("agenda"); return }
        if name == "more" { if !element("screen.more").exists { tap("navigation.profile") }; return }
        let target = tabButton(name)
        XCTAssertTrue(target.waitForExistence(timeout: 8)); target.tap()
        dismissTutorialIfNeeded(name)
    }

    private func tabButton(_ name: String) -> XCUIElement {
        let labels = ["today": "Hoje", "studies": "Estudos", "focus": "Foco", "reviews": "Revisões", "assistant": "Assistente"]
        return app.tabBars.buttons[labels[name] ?? name].firstMatch
    }

    private func dismissTutorialIfNeeded(_ page: String) {
        let pages = ["today", "studies", "focus", "reviews", "assistant", "materials", "agenda", "progress"]
        guard app.launchArguments.contains("--test-tutorials"), pages.contains(page), !dismissedTutorials.contains(page) else { return }
        let modal = element("tutorial.\(page).modal")
        XCTAssertTrue(modal.waitForExistence(timeout: 8))
        tap("tutorial.\(page).skip")
        XCTAssertTrue(modal.waitForNonExistence(timeout: 8))
        dismissedTutorials.insert(page)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

    func testHomeStreakAndIconOnlyHeaderOpenTheirDestinations() {
        let streak = element("navigation.streak")
        XCTAssertTrue(streak.waitForExistence(timeout: 8))
        XCTAssertTrue(streak.label.contains("Sua sequência:"))
        XCTAssertEqual(streak.label, "Sua sequência: 0 dias")
        XCTAssertEqual(streak.value as? String, "Ainda sem estudo hoje")
        capture("Hoje com sequência de zero dias e barra nativa")
        XCTAssertGreaterThanOrEqual(streak.frame.height, 44)
        XCTAssertGreaterThanOrEqual(streak.frame.width, 88)
        XCTAssertFalse(element("today.streak").exists)
        let profileButton = element("navigation.profile")
        XCTAssertEqual(profileButton.label, "Meu perfil e preferências")
        XCTAssertGreaterThanOrEqual(profileButton.frame.width, 44)
        let help = element("navigation.help")
        XCTAssertEqual(help.label, "Como usar Hoje")
        XCTAssertGreaterThanOrEqual(help.frame.height, 44)
        tap("navigation.help")
        let replay = element("tutorial.today.modal")
        XCTAssertTrue(replay.waitForExistence(timeout: 8))
        capture("Tutorial reaberto pelo botão de ajuda")
        tap("tutorial.today.skip")
        XCTAssertTrue(replay.waitForNonExistence(timeout: 8))
        tap("navigation.streak")
        XCTAssertTrue(element("screen.streak").waitForExistence(timeout: 8))
        XCTAssertTrue(element("streak.calendar").waitForExistence(timeout: 8))
        let originalMonth = element("streak.month").label
        tap("streak.previous")
        XCTAssertNotEqual(element("streak.month").label, originalMonth)
        tap("streak.today")
        XCTAssertEqual(element("streak.month").label, originalMonth)
        tap("streak.close")
        for horizontalPosition in [0.25, 0.75] {
            XCTAssertTrue(streak.waitForExistence(timeout: 8))
            streak.coordinate(withNormalizedOffset: CGVector(dx: horizontalPosition, dy: 0.5)).tap()
            XCTAssertTrue(element("streak.calendar").waitForExistence(timeout: 8))
            tap("streak.close")
        }
        tap("navigation.profile"); tap("more.widgets")
        XCTAssertTrue(element("screen.widgets").waitForExistence(timeout: 8))
        XCTAssertFalse(element("app.error").exists)
    }

    func testEveryMainScreenAndLandscapeLayout() {
        for screen in ["studies", "reviews", "focus", "assistant", "today"] {
            tab(screen); XCTAssertTrue(element("screen.\(screen)").waitForExistence(timeout: 8))
        }
        tab("more")
        for screen in ["materials", "agenda", "progress", "assistant", "settings"] {
            tap("more.\(screen)"); XCTAssertTrue(element("screen.\(screen)").waitForExistence(timeout: 8))
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 8))
            XCTAssertFalse(element("app.error").exists)
            XCUIDevice.shared.orientation = .portrait
            back()
        }
    }

    func testProfileMenusNavigateAndReturnAcrossTabs() {
        assertProfileMenusNavigateAndReturnAcrossTabs()
    }

    func testProfileMenusWithTutorialsNavigateAndReturnAcrossTabs() {
        XCTAssertTrue(element("tutorial.today.modal").waitForExistence(timeout: 8))
        capture("Tutorial modal antes da navegação")
        assertProfileMenusNavigateAndReturnAcrossTabs()
    }

    func testFreshOnboardingWithTutorialsKeepsNavigationInteractive() {
        for step in 0..<10 {
            if step < 2 {
                let label = step == 0 ? "Seu nome" : "O que você quer conquistar?"
                let textField = app.textFields[label].firstMatch
                let field = textField.exists ? textField : app.textViews[label].firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 8))
                for _ in 0..<5 {
                    if field.isHittable { break }
                    app.swipeUp()
                }
                XCTAssertTrue(field.isHittable)
                field.tap()
                field.typeText(step == 0 ? "Pessoa de teste" : "Aprender matemática")
            }
            let heading = element("welcome.heading")
            let previous = heading.label
            tap("welcome.continue")
            let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", previous), object: heading)
            XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 8), .completed)
        }
        tap("welcome.finish")
        let tutorial = element("tutorial.today.modal")
        XCTAssertTrue(tutorial.waitForExistence(timeout: 30))
        capture("Tutorial após concluir o onboarding")
        XCTAssertFalse(tabButton("studies").isHittable)
        XCTAssertFalse(element("navigation.profile").isHittable)
        XCTAssertEqual(tutorial.buttons.count, 2)
        XCTAssertFalse(app.buttons["Anterior"].exists)
        XCTAssertEqual(element("tutorial.today.step").label, "1/3")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 5, dy: app.frame.height / 2)).tap()
        XCTAssertTrue(tutorial.exists)
        tap("tutorial.today.continue")
        XCTAssertEqual(element("tutorial.today.step").label, "2/3")
        tap("tutorial.today.continue")
        XCTAssertEqual(element("tutorial.today.step").label, "3/3")
        XCTAssertEqual(element("tutorial.today.continue").label, "Entendi")
        tap("tutorial.today.continue")
        XCTAssertTrue(tutorial.waitForNonExistence(timeout: 8))
        dismissedTutorials.insert("today")
        XCTAssertTrue(element("screen.today").waitForExistence(timeout: 8))
        capture("Hoje com barra nativa e sequência visível")
        for destination in ["focus", "studies", "reviews", "assistant", "today"] {
            tab(destination)
            XCTAssertTrue(element("screen.\(destination)").waitForExistence(timeout: 8))
        }
        assertProfileMenusNavigateAndReturnAcrossTabs()
        app.terminate()
        launch(withTutorials: true)
        XCTAssertFalse(element("tutorial.today.modal").exists)
        tab("focus")
        XCTAssertFalse(element("tutorial.focus.modal").exists)
        XCTAssertFalse(element("app.error").exists)
    }

    private func assertProfileMenusNavigateAndReturnAcrossTabs() {
        dismissTutorialIfNeeded("today")
        tap("navigation.profile")
        XCTAssertTrue(element("screen.more").waitForExistence(timeout: 8))
        for destination in ["profile", "settings", "materials", "agenda", "progress", "assistant", "widgets"] {
            tap("more.\(destination)")
            dismissTutorialIfNeeded(destination)
            XCTAssertTrue(element("screen.\(destination)").waitForExistence(timeout: 8), "Profile menu did not open \(destination)")
            back()
            XCTAssertTrue(element("screen.more").waitForExistence(timeout: 8))
        }
        for value in ["0", "1"] {
            setNativeSwitch("profile.trackNavigation", value: value)
        }
        back()
        XCTAssertTrue(element("screen.today").waitForExistence(timeout: 8))
        for name in ["studies", "focus", "reviews", "assistant"] {
            tab(name)
            tap("navigation.profile")
            tap("more.widgets")
            XCTAssertTrue(element("screen.widgets").waitForExistence(timeout: 8))
            back()
            XCTAssertTrue(element("screen.more").waitForExistence(timeout: 8))
            back()
            XCTAssertTrue(element("screen.\(name)").waitForExistence(timeout: 8))
        }
        XCTAssertFalse(element("app.error").exists)
    }

    func testFocusDurationPresetPreviewsImmediatelyAndSurvivesTabRoundTrip() {
        tab("focus")
        tap("focus.preset.45")
        XCTAssertEqual(element("focus.elapsed").label, "45:00")
        tab("today"); tab("focus")
        XCTAssertEqual(element("focus.elapsed").label, "45:00")
        tap("focus.preset.15")
        XCTAssertEqual(element("focus.elapsed").label, "15:00")
        XCTAssertTrue(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.tabBars.buttons["Agenda"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Foco e navegação nativa"; capture.lifetime = .keepAlways
        add(capture)
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
        tab("today")
        let studied = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@ AND value == %@", "Sua sequência: 1 dia", "Estudou hoje"),
            object: element("navigation.streak")
        )
        XCTAssertEqual(XCTWaiter.wait(for: [studied], timeout: 8), .completed)
        capture("Sequência ativa após uma sessão salva")
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

    func testSettingsPersistAndEmbeddedAssistantNeedsNoModel() {
        tab("more"); tap("more.settings")
        type("settings.name", "Pessoa sintética", replacing: "Teste")
        element("settings.name").typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 8))
        let saved = app.staticTexts.matching(NSPredicate(format: "label == %@", "Salvo neste iPhone")).firstMatch
        for (id, value) in [("settings.sound", "1"), ("settings.sound", "0"), ("settings.reducedMotion", "1")] {
            setNativeSwitch(id, value: value)
            XCTAssertTrue(saved.waitForExistence(timeout: 8))
        }
        app.terminate(); launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Pessoa'")).firstMatch.exists)
        tab("more"); tap("more.settings")
        XCTAssertEqual(element("settings.name").value as? String, "Pessoa sintética")
        XCTAssertEqual(nativeSwitch("settings.sound").value as? String, "0")
        XCTAssertEqual(nativeSwitch("settings.reducedMotion").value as? String, "1")
        back(); tap("more.assistant")
        XCTAssertTrue(element("assistant.embedded").waitForExistence(timeout: 8))
        XCTAssertFalse(element("assistant.prompt").exists)
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
