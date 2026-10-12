import XCTest

/// End-to-end flow in the Simulator: needs the backend on http://127.0.0.1:18004 and a DEBUG build,
/// where the session screen replays a recorded golf session (3 swings) instead of the camera.
final class FormCoachFlowTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        let backend = ProcessInfo.processInfo.environment["FORMCOACH_UI_TEST_BACKEND"] ?? "http://127.0.0.1:18004"
        app.launchArguments = ["-uiTesting", "-resetTestAccount", "-backendURL", backend, "-offerMovementDemos", "YES", "-resetTrainingChoices", "-resetScoreboard", "-resetReplayPreferences"]
        app.launch()
    }

    private func shot(_ name: String) {
        usleep(500_000) // Capture the settled HUD rather than a transition frame.
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func close(_ identifier: String) {
        let button=app.buttons[identifier]
        for _ in 0..<3 {
            if !button.exists { return }
            button.tap()
            if button.waitForNonExistence(timeout:2) { return }
        }
        XCTAssertFalse(button.exists,"Presentation dismissed before the next action")
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

    private func register() {
        logOutIfNeeded()
        XCTAssertTrue(app.buttons["Register"].waitForExistence(timeout: 10))
        let register=app.segmentedControls.buttons["Register"]
        for _ in 0..<3 where !register.isSelected { register.tap(); usleep(500_000) }
        XCTAssertTrue(register.isSelected)
        type(app.textFields["Name"], "Sam Tester")
        type(app.textFields["Email"], "sam\(Int(Date().timeIntervalSince1970))@example.com")
        type(app.textFields["Password"], "correct horse 1")
        shot("1-register")
        app.buttons["Create account"].tap()

    }

    private func startPractice() {
        app.buttons["training.start"].tap()
        let decline=app.alerts.buttons["Not now"]
        if decline.waitForExistence(timeout:2) { decline.tap() }
    }

    func testReplayOfferIsShownOnceAndRespectsDecline() {
        register()
        let basketball=app.buttons.containing(NSPredicate(format:"label CONTAINS 'Basketball'")).firstMatch
        XCTAssertTrue(basketball.waitForExistence(timeout:20)); basketball.tap()
        XCTAssertTrue(app.buttons["training.start"].waitForExistence(timeout:10))
        XCTAssertEqual(app.switches["replays.save"].value as? String,"0")
        app.buttons["training.start"].tap()
        XCTAssertTrue(app.alerts.buttons["Not now"].waitForExistence(timeout:5))
        shot("replay-offer")
        app.alerts.buttons["Not now"].tap()
        XCTAssertTrue(app.buttons["End session"].waitForExistence(timeout:15))
        app.buttons["End session"].tap()
        XCTAssertTrue(app.navigationBars["Session summary"].waitForExistence(timeout:20))
        XCTAssertFalse(app.staticTexts["replay.saved.count"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(basketball.waitForExistence(timeout:10)); basketball.tap()
        XCTAssertTrue(app.buttons["training.start"].waitForExistence(timeout:10))
        XCTAssertEqual(app.switches["replays.save"].value as? String,"0")
        app.buttons["training.start"].tap()
        XCTAssertFalse(app.alerts.buttons["Not now"].waitForExistence(timeout:2))
        XCTAssertTrue(app.buttons["End session"].waitForExistence(timeout:15))
        app.buttons["End session"].tap()
    }

    func testReplayCaptureStaysLocal() {
        register()
        let basketball=app.buttons.containing(NSPredicate(format:"label CONTAINS 'Basketball'")).firstMatch
        XCTAssertTrue(basketball.waitForExistence(timeout:20)); basketball.tap()
        let save=app.switches["replays.save"]
        XCTAssertTrue(save.waitForExistence(timeout:10))
        for _ in 0..<3 where save.value as? String != "1" { save.coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.5)).tap(); usleep(500_000) }
        XCTAssertEqual(save.value as? String,"1")
        startPractice()
        XCTAssertTrue(app.staticTexts["Demo complete · tap End session"].waitForExistence(timeout:80))
        app.buttons["End session"].tap()
        XCTAssertTrue(app.navigationBars["Session summary"].waitForExistence(timeout:30))
        XCTAssertTrue(app.staticTexts["replay.saved.count"].exists || app.otherElements["replay.saved.count"].exists,"At least one local clip was encoded")
        shot("replay-capture-saved")
        let row=app.buttons["replay.row.1"]
        for _ in 0..<24 {
            if row.isHittable,row.frame.minY > 110,row.frame.maxY < app.frame.height-80 { break }
            app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.7)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)))
        }
        XCTAssertTrue(row.exists); row.tap()
        XCTAssertTrue(app.buttons["replay.freeze"].waitForExistence(timeout:15))
        XCTAssertTrue(app.sliders["replay.scrub"].exists)
        XCTAssertTrue(app.buttons["replay.share"].waitForExistence(timeout:20))
        shot("replay-player-motion")
        app.buttons["replay.freeze"].tap()
        shot("replay-player-fix")
        app.sliders["replay.scrub"].adjust(toNormalizedSliderPosition:0.2)
        shot("replay-player-scrubbed")
        let demo=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'replay.demo.'")).firstMatch
        for _ in 0..<4 where !demo.isHittable { app.swipeUp() }
        XCTAssertTrue(demo.exists,"Timing cue offers a hologram alongside the corrected cue")
        demo.tap()
        XCTAssertTrue(app.buttons["hologram.close"].waitForExistence(timeout:10))
        shot("replay-timing-hologram")
        close("hologram.close")
        XCTAssertTrue(app.buttons["replay.close"].exists)
        close("replay.close")
        app.buttons["Done"].tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout:10))
        app.buttons["history.sport"].tap()
        app.buttons["Basketball"].tap()
        let entry=app.buttons.containing(NSPredicate(format:"label CONTAINS 'Saved replays'")).firstMatch
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.exists,"History marks sessions with local clips")
        shot("replay-history")
        entry.tap()
        XCTAssertTrue(app.navigationBars["Session summary"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["replay.row.1"].exists,"History detail retains local replay rows")
        app.navigationBars["Session summary"].buttons.element(boundBy:0).tap()
        logOutIfNeeded()
        XCTAssertTrue(app.buttons["Register"].waitForExistence(timeout:10))
        shot("replay-logout")
    }

    func testRegisterPractiseGolfAndSync() {
        register()

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
        startPractice()

        let end = app.buttons["End session"]
        XCTAssertTrue(end.waitForExistence(timeout: 20))
        let card=app.buttons["rep.feedback.card"]
        XCTAssertTrue(card.waitForExistence(timeout:40))
        XCTAssertTrue(app.staticTexts["REPS"].exists)
        XCTAssertTrue(app.staticTexts["SCORE"].exists)
        XCTAssertFalse(app.staticTexts["Want to see what this means?"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'demo.show.golf.'")).firstMatch.exists)
        shot("3a-scoreboard-compact")
        app.buttons["scoreboard.cycle"].tap()
        XCTAssertFalse(app.staticTexts["REPS"].exists)
        XCTAssertEqual(app.buttons["scoreboard.cycle"].label,"Hide scoreboard")
        shot("3a-scoreboard-mini")
        app.buttons["scoreboard.cycle"].tap()
        XCTAssertEqual(app.buttons["scoreboard.cycle"].label,"Show scoreboard")
        shot("3a-scoreboard-hidden")
        app.buttons["scoreboard.cycle"].tap()
        XCTAssertTrue(app.staticTexts["REPS"].waitForExistence(timeout:5))
        shot("3a-last-rep-card")
        card.tap()
        XCTAssertTrue(app.buttons["rep.feedback.close"].waitForExistence(timeout:5))
        shot("3a-rep-feedback-detail")
        let cueDemo=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'demo.show.golf.'")).firstMatch
        XCTAssertTrue(cueDemo.waitForExistence(timeout:5))
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
        close("hologram.close")
        close("rep.feedback.close")
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
        close("hologram.close")
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
        startPractice()
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
    func testBasketballCorrectionCardAndSummary() {
        register()
        let basketball=app.buttons.containing(NSPredicate(format:"label CONTAINS 'Basketball'")).firstMatch
        XCTAssertTrue(basketball.waitForExistence(timeout:20)); basketball.tap()
        XCTAssertTrue(app.buttons["training.start"].waitForExistence(timeout:10)); startPractice()
        let card=app.buttons["rep.feedback.card"]
        XCTAssertTrue(card.waitForExistence(timeout:40))
        shot("quiet-basketball-card")
        card.tap()
        XCTAssertTrue(app.buttons["rep.feedback.close"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["Your pose (white) vs the fix (cyan)"].exists)
        shot("quiet-basketball-correction")
        close("rep.feedback.close")
        XCTAssertTrue(app.staticTexts["Demo complete · tap End session"].waitForExistence(timeout:60))
        app.buttons["End session"].tap()
        XCTAssertTrue(app.navigationBars["Session summary"].waitForExistence(timeout:20))
        let stored=app.buttons["summary.feedback.1"]
        for _ in 0..<24 {
            if stored.isHittable, stored.frame.minY > 110, stored.frame.maxY < app.frame.height-80 { break }
            let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.7))
            let end=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4))
            start.press(forDuration:0.05,thenDragTo:end)
        }
        XCTAssertTrue(stored.exists); stored.tap()
        XCTAssertTrue(app.buttons["rep.feedback.close"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["Your pose (white) vs the fix (cyan)"].exists)
        shot("quiet-summary-correction")
        close("rep.feedback.close")
    }

    /// Height, level and a drill adapt the session: rep goal and hand speed live, level and focus in the summary.
    func testDrillGoalHandSpeedAndLevel() {
        app.terminate()
        app.launchArguments += ["-player.heightCm", "180", "-player.level", "beginner", "-player.metric", "YES",
                                "-drill.basketball", "form_shooting"]
        app.launch()
        register()
        let basketball=app.buttons.containing(NSPredicate(format:"label CONTAINS 'Basketball'")).firstMatch
        XCTAssertTrue(basketball.waitForExistence(timeout:20)); basketball.tap()
        XCTAssertTrue(app.buttons["training.start"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'One-hand form shots'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'Goal 30 reps · scored as Beginner · height 180 cm'")).firstMatch.exists)
        shot("drill-setup")
        startPractice()
        XCTAssertTrue(app.buttons["rep.feedback.card"].waitForExistence(timeout:40))
        XCTAssertTrue(app.staticTexts["KM/H"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label ENDSWITH '/30'")).firstMatch.exists)
        shot("drill-scoreboard")
        XCTAssertTrue(app.staticTexts["Demo complete · tap End session"].waitForExistence(timeout:60))
        app.buttons["End session"].tap()
        XCTAssertTrue(app.navigationBars["Session summary"].waitForExistence(timeout:20))
        XCTAssertTrue(app.staticTexts["Scored as Beginner"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label BEGINSWITH 'Hand speed'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'Form shooting'")).firstMatch.exists)
        shot("drill-summary")
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
