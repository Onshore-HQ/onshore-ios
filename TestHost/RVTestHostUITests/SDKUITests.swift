// Taps and types in the SDK's real views on a simulator, against a live install.
// Each client token works once, so each test has its own, from scripts/test-ios-sim.mjs.
import Onshore
import XCTest

final class TrustTestServer: NSObject, URLSessionDelegate {
    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge, completionHandler h: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let t = c.protectionSpace.serverTrust { h(.useCredential, URLCredential(trust: t)) } else { h(.performDefaultHandling, nil) }
    }
}

final class SDKUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private func need(_ k: String) -> String { env[k] ?? "" }

    override func setUp() { continueAfterFailure = false }

    private func launch(_ screen: String, token: String, hideAfter: Int = 60) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["RV_SCREEN": screen, "RV_TOKEN": token, "RV_BASE": need("RV_BASE"), "RV_APP_ORIGIN": need("RV_APP_ORIGIN"), "RV_HIDE_AFTER": String(hideAfter)]
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func text(_ app: XCUIApplication, id: String) -> String { app.staticTexts[id].exists ? app.staticTexts[id].label : "" }

    private func waitFor(_ what: String, timeout: TimeInterval = 20, _ cond: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("timed out waiting for \(what)")
    }

    /// Swipes up from the bottom edge and holds, as a person does on an iPhone with no home button.
    /// The test can only attach what this shows, so its screenshot has to be looked at.
    private func openAppSwitcher(_ app: XCUIApplication) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.999))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 1.5)
        RunLoop.current.run(until: Date().addingTimeInterval(3))
    }

    func testCollectFormTypoThenToken() {
        let app = launch("collect", token: need("RV_COLLECT"))
        let field = app.textFields["BVN"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the form's field should come from the live token")
        shot("collect-empty")
        field.tap()
        field.typeText("123")
        shot("collect-typed")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Check this value"].waitForExistence(timeout: 20), "a typo should be named on the field")
        shot("collect-typo")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        field.typeText(need("RV_VALUE"))
        app.buttons["Continue"].tap()
        waitFor("a token") { text(app, id: "result").hasPrefix("tok_bvn_") }
        XCTAssertFalse(text(app, id: "result").contains(need("RV_VALUE")))
        XCTAssertFalse(app.staticTexts[need("RV_VALUE")].exists)
        XCTAssertNotEqual(field.value as? String, need("RV_VALUE"), "the form should clear after submitting")
        shot("collect-done")
    }

    func testCollectFormFieldTraits() {
        let app = launch("collect", token: need("RV_TRAITS"))
        XCTAssertTrue(app.textFields["BVN"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.textFields["Email"].exists)
        app.buttons["Inspect"].tap()
        waitFor("traits") { !text(app, id: "traits").isEmpty }
        let traits = text(app, id: "traits")
        print("RV_TRAITS_READ=\(traits)")
        let fields = traits.components(separatedBy: "|")
        XCTAssertEqual(fields.count, 2, traits)
        XCTAssertTrue(fields.contains { $0.contains("keyboard=\(UIKeyboardType.numberPad.rawValue) ") }, "a BVN uses the number pad: \(traits)")
        for f in fields {
            XCTAssertTrue(f.contains("autocorrect=\(UITextAutocorrectionType.no.rawValue) "), "suggestions off: \(f)")
            XCTAssertTrue(f.contains("spell=\(UITextSpellCheckingType.no.rawValue) "), "spell check off: \(f)")
            XCTAssertTrue(f.contains("capitalize=\(UITextAutocapitalizationType.none.rawValue) "), "capitalisation off: \(f)")
            XCTAssertTrue(f.contains("content=none"), "no autofill hint: \(f)")
            XCTAssertTrue(f.contains("copy=false"), "copy off: \(f)")
            XCTAssertTrue(f.contains("cut=false"), "cut off: \(f)")
        }
    }

    func testCollectFormCoveredWhenLeavingTheApp() {
        let app = launch("collect", token: need("RV_COVER"))
        let field = app.textFields["BVN"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText(need("RV_VALUE"))
        shot("cover-before")
        openAppSwitcher(app)
        shot("cover-app-switcher")
        app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        shot("cover-after")
        XCTAssertEqual(field.value as? String, need("RV_VALUE"), "a person coming back keeps what they typed")
    }

    func testRevealShowsThenHidesAfterTime() {
        let app = launch("reveal", token: need("RV_REVEAL_TIMED"), hideAfter: 8)
        let value = app.staticTexts[need("RV_REVEAL_VALUE")]
        XCTAssertTrue(value.waitForExistence(timeout: 20), "the revealed value should show")
        shot("reveal-showing")
        waitFor("the value to hide", timeout: 20) { !value.exists }
        shot("reveal-hidden")
    }

    func testRevealHidesWhenLeavingTheApp() {
        let app = launch("reveal", token: need("RV_REVEAL_BG"))
        let value = app.staticTexts[need("RV_REVEAL_VALUE")]
        XCTAssertTrue(value.waitForExistence(timeout: 20))
        openAppSwitcher(app)
        shot("reveal-app-switcher")
        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertFalse(value.exists, "a value should not survive leaving the app")
        shot("reveal-after-return")
    }

    func testRevealRefusedByPolicyShowsNoValue() {
        let app = launch("reveal", token: need("RV_DENIED"))
        XCTAssertTrue(app.staticTexts["You do not have access to this"].waitForExistence(timeout: 20))
        shot("reveal-denied")
    }

    /// The client itself, in a process on the simulator rather than on macOS.
    func testClientOnSimulator() async throws {
        let session = URLSession(configuration: .ephemeral, delegate: TrustTestServer(), delegateQueue: nil)
        let base = URL(string: need("RV_BASE"))!
        let client = SecureClient(baseURL: base, appOrigin: need("RV_APP_ORIGIN"), session: session)
        let other = SecureClient(baseURL: base, appOrigin: "rvapp://ng.other.app", session: session)
        let token = need("RV_CLIENT")
        do { _ = try await other.describe(clientToken: token); XCTFail("another app was accepted") } catch let e as VaultError { XCTAssertEqual(e, .invalidClientToken) }
        let tokens = try await client.collect(clientToken: token, values: ["bvn": need("RV_VALUE")])
        XCTAssertTrue(tokens["bvn"]?.hasPrefix("tok_bvn_") == true)
        do { _ = try await client.collect(clientToken: token, values: ["bvn": need("RV_VALUE")]); XCTFail("a token worked twice") } catch let e as VaultError { XCTAssertEqual(e, .invalidClientToken) }
    }
}
