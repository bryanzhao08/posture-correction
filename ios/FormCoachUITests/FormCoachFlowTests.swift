import XCTest

/// End-to-end flow in the Simulator: needs the backend on http://localhost:8000 and a DEBUG build,
/// where the session screen replays a recorded golf session (3 swings) instead of the camera.
final class FormCoachFlowTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    private func shot(_ name: String) {
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

        let end = app.buttons["End session"]
        XCTAssertTrue(end.waitForExistence(timeout: 20))
        sleep(12)
        shot("3-session-mid")
        let done = app.staticTexts["Demo complete · tap End session"]
        XCTAssertTrue(done.waitForExistence(timeout: 60), "replay finished")
        shot("4-session-end")
        end.tap()

        XCTAssertTrue(app.navigationBars["Session summary"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Synced"].waitForExistence(timeout: 30) ||
                      app.buttons["Synced"].exists, "session uploaded to the backend")
        shot("5-summary")
        app.swipeUp()
        shot("6-summary-scrolled")
        app.buttons["Done"].tap()

        app.tabBars.buttons["History"].tap()
        sleep(3)
        shot("7-history")
    }
}
