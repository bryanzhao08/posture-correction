import XCTest

/// End-to-end flow in the Simulator: needs the backend on http://127.0.0.1:18004 and a DEBUG build,
/// where the session screen replays a recorded golf session (3 swings) instead of the camera.
final class FormCoachFlowTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        let backend = ProcessInfo.processInfo.environment["FORMCOACH_UI_TEST_BACKEND"] ?? "http://127.0.0.1:18004"
        app.launchArguments = ["-uiTesting", "-resetTestAccount", "-backendURL", backend, "-offerMovementDemos", "YES", "-resetTrainingChoices", "-resetScoreboard"]
        app.launch()
    }

    private func shot(_ name: String) {
        usleep(500_000) // Capture the settled HUD rather than a transition frame.
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func type(_ field: XCUIElement, _ text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        for _ in 0..<5 {
            field.tap()
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { break }
            usleep(500_000)
        }
        field.typeText(text)
    }

    private func logOutIfNeeded() {
        let settings = app.tabBars.buttons["Settings"]
        guard settings.waitForExistence(timeout: 5) else { return }
        settings.tap()
        let logOut = app.buttons["Log out"]
        for _ in 0..<6 where !logOut.isHittable { app.swipeUp() }
        logOut.tap()
    }

    func testRegisterPractiseGolfAndSync() {
        logOutIfNeeded()
        XCTAssertTrue(app.buttons["Register"].waitForExistence(timeout: 10))
        app.buttons["Register"].tap()
        type(app.textFields["Name"], "Sam Tester")
        type(app.textFields["Email"], "sam\(Int(Date().timeIntervalSince1970))@example.com")
        type(app.textFields["Password"], "correct horse 1")
        shot("1-register")
        app.buttons["Create account"].tap()

        let golf = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Golf'")).firstMatch
        XCTAssertTrue(golf.waitForExistence(timeout: 20), "home screen with sport cards")
        shot("2-home")
        golf.tap()
        XCTAssertTrue(app.buttons["training.start"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["End session"].exists)
        shot("2a-preparation")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.navigationBars["Practise"].waitForExistence(timeout: 10))
        XCTAssertTrue(golf.label.contains("0 sessions"), "Backing out creates no session")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'waiting to sync'")).firstMatch.exists)
        golf.tap()
        XCTAssertTrue(app.buttons["training.start"].waitForExistence(timeout: 10))
        app.buttons["training.start"].tap()

        let end = app.buttons["End session"]
        XCTAssertTrue(end.waitForExistence(timeout: 20))
        let cueDemo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'demo.show.golf.'")).firstMatch
        XCTAssertTrue(cueDemo.waitForExistence(timeout: 40))
        XCTAssertTrue(app.staticTexts["REPS"].exists)
        XCTAssertTrue(app.staticTexts["SCORE"].exists)
        shot("3a-scoreboard-full")
        app.buttons["scoreboard.minimize"].tap()
        XCTAssertTrue(app.buttons["scoreboard.show"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["REPS"].exists)
        shot("3a-scoreboard-minimized")
        app.buttons["scoreboard.show"].tap()
        XCTAssertTrue(app.staticTexts["SCORE"].waitForExistence(timeout: 5))
        app.buttons["scoreboard.minimize"].tap()
        XCTAssertTrue(app.buttons["scoreboard.hide"].waitForExistence(timeout: 5))
        app.buttons["scoreboard.hide"].tap()
        XCTAssertTrue(app.buttons["scoreboard.show"].exists)
        XCTAssertFalse(app.buttons["scoreboard.hide"].exists)
        shot("3a-scoreboard-hidden")
        app.buttons["scoreboard.show"].tap()
        XCTAssertTrue(app.staticTexts["REPS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SCORE"].exists)
        shot("3a-scoreboard-restored")
        cueDemo.tap()
        XCTAssertTrue(app.buttons["hologram.close"].waitForExistence(timeout: 10))
        sleep(1)
        shot("3b-golf-hologram-both")
        app.buttons["Wrong"].tap()
        sleep(1)
        shot("3c-golf-hologram-wrong")
        app.buttons["Correct"].tap()
        sleep(1)
        shot("3d-golf-hologram-correct")
        app.buttons["Replay"].tap()
        app.buttons["hologram.close"].tap()
        shot("3-session-mid")
        let done = app.staticTexts["Demo complete · tap End session"]
        XCTAssertTrue(done.waitForExistence(timeout: 60), "replay finished")
        shot("4-session-end")
        let setupInstructions = app.buttons["setup.instructions"]
        XCTAssertTrue(setupInstructions.waitForExistence(timeout: 5))
        for _ in 0..<3 where !setupInstructions.isHittable { app.swipeUp() }
        setupInstructions.tap()
        let setupDemo = app.buttons["demo.show.setup.golf"]
        XCTAssertTrue(setupDemo.waitForExistence(timeout: 5))
        for _ in 0..<3 where !setupDemo.isHittable { app.swipeUp() }
        setupDemo.tap()
        XCTAssertTrue(app.buttons["hologram.close"].waitForExistence(timeout: 10))
        sleep(1)
        shot("4a-setup-hologram")
        app.buttons["Correct"].tap()
        sleep(1)
        shot("4b-setup-hologram-correct")
        app.buttons["hologram.close"].tap()
        setupInstructions.tap()
        end.tap()

        XCTAssertTrue(app.navigationBars["Session summary"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Synced"].waitForExistence(timeout: 30) ||
                      app.buttons["Synced"].exists, "session uploaded to the backend")
        shot("5-summary")
        app.swipeUp()
        shot("6-summary-scrolled")
        for _ in 0..<3 where app.navigationBars["Session summary"].exists {
            app.buttons["Done"].tap()
            sleep(1)
        }
        XCTAssertFalse(app.navigationBars["Session summary"].exists)

        app.tabBars.buttons["History"].tap()
        sleep(3)
        shot("7-history")
        app.tabBars.buttons["Practise"].tap()
        let tennis = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Tennis'")).firstMatch
        for _ in 0..<4 { if tennis.isHittable { break }; app.swipeUp() }
        tennis.tap()
        XCTAssertTrue(app.buttons["training.start"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["training.camera"].label.contains("From behind"))
        app.buttons["training.type"].tap()
        app.buttons["Serve"].tap()
        XCTAssertTrue(app.staticTexts["training.camera"].label.contains("Side-on"))
        app.buttons["From behind"].tap()
        XCTAssertTrue(app.staticTexts["training.camera"].label.contains("From behind"))
        shot("8-tennis-training")
        app.buttons["training.start"].tap()
        XCTAssertTrue(app.buttons["End session"].waitForExistence(timeout: 10))
        app.buttons["End session"].tap()
        XCTAssertTrue(app.navigationBars["Session summary"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Tennis · Serve · from behind"].exists)
        for _ in 0..<3 where app.navigationBars["Session summary"].exists {
            app.buttons["Done"].tap()
            sleep(1)
        }
        XCTAssertFalse(app.navigationBars["Session summary"].exists)
        tennis.tap()
        XCTAssertTrue(app.buttons["training.start"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["training.camera"].label.contains("From behind"))
        XCTAssertTrue(app.buttons["training.type"].label.contains("Serve"))
        app.buttons["Back"].tap()
    }
}

final class DemoCatalogCoverageTests: XCTestCase {
    func testEveryCatalogEntryHasParameters() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cue_catalog", withExtension: "json"))
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let keys = try entries.map { try XCTUnwrap($0["key"] as? String) }
        XCTAssertEqual(keys.count,46)
        XCTAssertEqual(Set(keys).count,keys.count)
        for key in keys { XCTAssertNotNil(DemoMotionTable.entries[key],key) }
        for sport in ["golf","basketball","tennis","pickleball"] { XCTAssertNotNil(DemoMotionTable.entries["setup." + sport]) }
        for view in ["front","back","side"] { XCTAssertNotNil(DemoMotionTable.entries["setup.tennis." + view]) }
        XCTAssertEqual(DemoMotionTable.entries.count,53)
        for (key,spec) in DemoMotionTable.entries {
            XCTAssertNotEqual(spec.wrong,spec.correct,key)
        }
        XCTAssertEqual(Set(DemoMotionTable.entries.values.map(\.base)),Set(BaseMotion.allCases))
    }
}
