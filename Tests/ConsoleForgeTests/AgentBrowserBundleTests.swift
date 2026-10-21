import XCTest
@testable import ConsoleForge

/// An agent browser must not run from the user's own Chrome bundle — GitHub #48.
///
/// macOS LaunchServices tracks running applications by BUNDLE, so a headless
/// `com.google.Chrome` registers as a running instance of the user's desktop Chrome. With
/// their Chrome quit, a Dock / Spotlight / `open` launch does not start a new process: it
/// ACTIVATES one of ours, which becomes frontmost and can never draw a window. Observed
/// 2026-10-20 — Chrome's menu bar with no window, nothing in the Window menu, and three
/// Force Quits that each killed a tab's agent browser instead of Chrome.
///
/// These are the RESOLUTION rules, which is where the bug is decided. They are pure on
/// purpose: the real filesystem cannot describe a machine with no Chrome for Testing, and
/// that machine is exactly the one the bug comes back on.
@MainActor
final class AgentBrowserBundleTests: XCTestCase {

    private let forTesting =
        "/Applications/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
    private let desktop = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    private let canary =
        "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"
    private let chromium = "/Applications/Chromium.app/Contents/MacOS/Chromium"

    /// A machine described by the set of executables that exist on it.
    private func resolve(_ present: Set<String>,
                         cache: [String: [String]] = [:],
                         home: String = "/Users/test") -> ManagedChrome.AgentBrowser? {
        ManagedChrome.resolveAgentBrowser(
            home: home,
            isExecutable: { present.contains($0) },
            contentsOfDirectory: { cache[$0] ?? [] })
    }

    func testChromeForTestingBeatsTheUsersOwnChrome() {
        let got = resolve([forTesting, desktop])
        XCTAssertEqual(got?.path, forTesting)
        XCTAssertEqual(got?.isolatedFromDesktopChrome, true)
    }

    func testTheUsersOwnChromeIsAcceptedButFlaggedAsNotIsolated() {
        // Accepted, because a machine with only stable Chrome must still be able to
        // browse — but flagged, because this is the configuration the bug lives in.
        let got = resolve([desktop])
        XCTAssertEqual(got?.path, desktop)
        XCTAssertEqual(got?.isolatedFromDesktopChrome, false)
    }

    func testCanaryAndChromiumAreIsolatedToo() {
        // Their bundle ids are com.google.Chrome.canary and org.chromium.Chromium, so a
        // com.google.Chrome launch cannot be routed to them either.
        XCTAssertEqual(resolve([canary, desktop])?.path, canary)
        XCTAssertEqual(resolve([canary, desktop])?.isolatedFromDesktopChrome, true)
        XCTAssertEqual(resolve([chromium, desktop])?.path, chromium)
        XCTAssertEqual(resolve([chromium, desktop])?.isolatedFromDesktopChrome, true)
    }

    func testPuppeteersCacheCountsAsAnInstalledChromeForTesting() {
        // This is where `@puppeteer/browsers install` puts it, and the same cache
        // chrome-devtools-mcp's own Puppeteer resolves from — one download serves both.
        let app = "/Users/test/.cache/puppeteer/chrome/mac_arm-145.0.7632.46/"
            + "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/"
            + "Google Chrome for Testing"
        let got = resolve([app, desktop], cache: [
            "/Users/test/.cache/puppeteer/chrome": ["mac_arm-145.0.7632.46"],
            "/Users/test/.cache/puppeteer/chrome/mac_arm-145.0.7632.46": ["chrome-mac-arm64"],
        ])
        XCTAssertEqual(got?.path, app)
        XCTAssertEqual(got?.isolatedFromDesktopChrome, true)
    }

    func testTheNewestCachedVersionWinsNumericallyNotLexically() {
        // "mac_arm-99…" sorts AFTER "mac_arm-145…" as a string. Picking by string order
        // would pin every machine to whatever old build happens to be cached.
        XCTAssertEqual(
            ManagedChrome.orderedPuppeteerVersions(["mac_arm-99.0.1.0",
                                                    "mac_arm-145.0.7632.46",
                                                    "mac_arm-139.0.7258.154"]),
            ["mac_arm-145.0.7632.46", "mac_arm-139.0.7258.154", "mac_arm-99.0.1.0"])
    }

    func testAMalformedCacheEntryIsIgnoredRatherThanCrashing() {
        XCTAssertEqual(
            ManagedChrome.orderedPuppeteerVersions([".DS_Store", "mac_arm-145.0.7632.46",
                                                    "chrome-headless-shell"]),
            ["mac_arm-145.0.7632.46"])
    }

    func testNoBrowserAtAllResolvesToNothing() {
        XCTAssertNil(resolve([]))
    }
}
