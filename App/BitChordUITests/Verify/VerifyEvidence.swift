import XCTest

/// Helpers for the verification drives in this folder, which run in the `BitChordE2E` test plan.
/// Each `capture` keeps a named screenshot in the result bundle, even when the test passes, so a
/// run can be checked by eye in Xcode's test report. Name steps "1-launched", "2-…" so they sort in order.
extension XCTestCase {
    func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The app as a user starts it for a verification drive: `-uitesting` gives an empty queue, and
    /// `arguments` adds a demo mode or deep open (the screens under `Features/` read them, mostly in
    /// `*DebugLaunch.swift` and `*DemoService.swift`).
    func launchForVerify(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"] + arguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "the app did not come to the front")
        return app
    }

    /// Choosing a song opens Now Playing by default. Drives that continue on the list close it
    /// and use the mini player underneath.
    func dismissFullPlayer(_ app: XCUIApplication) {
        let player = app.descendants(matching: .any).matching(identifier: "screen.nowPlaying").firstMatch
        guard player.waitForExistence(timeout: 12) else { return }
        let close = app.buttons["nowPlaying.close"].firstMatch
        guard close.waitForExistence(timeout: 5) else { return }
        close.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: player)
        _ = XCTWaiter().wait(for: [gone], timeout: 8)
    }
}
