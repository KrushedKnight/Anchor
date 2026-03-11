import XCTest
@testable import Anchor

@MainActor
final class BehaviorAnalyzerTests: XCTestCase {

    private func makeStore(events: [(type: String, data: [String: String])]) -> EventStore {
        let store = EventStore()
        for e in events { store.append(type: e.type, data: e.data) }
        return store
    }

    private func analyzer(events: [(type: String, data: [String: String])]) -> BehaviorAnalyzer {
        let store    = makeStore(events: events)
        let analyzer = BehaviorAnalyzer(store: store)
        analyzer.update()
        return analyzer
    }

    func testEmptyStore_allZero() {
        let a = analyzer(events: [])
        XCTAssertEqual(a.snapshot.currentApp, "")
        XCTAssertEqual(a.snapshot.currentDomain, "")
        XCTAssertFalse(a.snapshot.isIdle)
        XCTAssertEqual(a.snapshot.switchesPerMinute, 0)
        XCTAssertEqual(a.snapshot.appSwitchRate30s, 0)
    }

    func testActiveApp_setsCurrentApp() {
        let a = analyzer(events: [
            (type: "active_app", data: ["appName": "Xcode"])
        ])
        XCTAssertEqual(a.snapshot.currentApp, "Xcode")
        XCTAssertEqual(a.snapshot.currentDomain, "")
    }

    func testBrowserDomain_setsDomain() {
        let a = analyzer(events: [
            (type: "active_app",     data: ["appName": "Google Chrome"]),
            (type: "browser_domain", data: ["domain": "github.com"])
        ])
        XCTAssertEqual(a.snapshot.currentApp, "Google Chrome")
        XCTAssertEqual(a.snapshot.currentDomain, "github.com")
    }

    func testSwitchingToNonBrowser_clearsDomain() {
        let a = analyzer(events: [
            (type: "active_app",     data: ["appName": "Google Chrome"]),
            (type: "browser_domain", data: ["domain": "github.com"]),
            (type: "active_app",     data: ["appName": "Xcode"])
        ])
        XCTAssertEqual(a.snapshot.currentApp, "Xcode")
        XCTAssertEqual(a.snapshot.currentDomain, "")
    }

    func testIdleStart_setsIsIdle() {
        let a = analyzer(events: [
            (type: "active_app", data: ["appName": "Xcode"]),
            (type: "idle_start", data: [:])
        ])
        XCTAssertTrue(a.snapshot.isIdle)
        XCTAssertEqual(a.snapshot.currentFocusStreak, 0)
    }

    func testIdleEnd_clearsIsIdle() {
        let a = analyzer(events: [
            (type: "idle_start", data: [:]),
            (type: "idle_end",   data: [:])
        ])
        XCTAssertFalse(a.snapshot.isIdle)
    }

    func testTabSwitches_countedInSwitchesPerMinute() {
        let events: [(type: String, data: [String: String])] = (0..<5).map { i in
            (type: "browser_domain", data: ["domain": "site\(i).com"])
        }
        let a = analyzer(events: events)
        XCTAssertEqual(a.snapshot.switchesPerMinute, 5)
        XCTAssertEqual(a.snapshot.tabSwitchRate30s, 5)
    }

    func testAppSwitches_countedInAppSwitchRate30s() {
        let apps = ["Xcode", "Slack", "Safari", "Finder"]
        let events = apps.map { (type: "active_app", data: ["appName": $0]) }
        let a = analyzer(events: events)
        XCTAssertEqual(a.snapshot.appSwitchRate30s, Double(apps.count))
    }

    func testIdleRatio_zeroWhenNeverIdle() {
        let a = analyzer(events: [
            (type: "active_app", data: ["appName": "Xcode"])
        ])
        XCTAssertEqual(a.snapshot.idleRatio120s, 0)
    }

    func testIdleRatio_nonZeroAfterIdlePeriod() {
        let a = analyzer(events: [
            (type: "idle_start", data: [:]),
            (type: "idle_end",   data: [:])
        ])
        XCTAssertGreaterThanOrEqual(a.snapshot.idleRatio120s, 0)
        XCTAssertLessThanOrEqual(a.snapshot.idleRatio120s, 1)
    }

    func testDwellInCurrentContext_greaterThanZero() {
        let a = analyzer(events: [
            (type: "active_app", data: ["appName": "Xcode"])
        ])
        XCTAssertGreaterThanOrEqual(a.snapshot.dwellInCurrentContext, 0)
    }

    func testFocusStreak_resetOnIdle() {
        let a = analyzer(events: [
            (type: "active_app", data: ["appName": "Xcode"]),
            (type: "idle_start", data: [:])
        ])
        XCTAssertEqual(a.snapshot.currentFocusStreak, 0)
    }

    func testFocusStreak_resumesAfterIdleEnd() {
        let a = analyzer(events: [
            (type: "idle_start", data: [:]),
            (type: "idle_end",   data: [:])
        ])
        XCTAssertGreaterThanOrEqual(a.snapshot.currentFocusStreak, 0)
    }

    func testIncrementalUpdate_onlyProcessesNewEvents() {
        let store    = EventStore()
        let analyzer = BehaviorAnalyzer(store: store)

        store.append(type: "active_app", data: ["appName": "Xcode"])
        analyzer.update()
        XCTAssertEqual(analyzer.snapshot.currentApp, "Xcode")

        store.append(type: "active_app", data: ["appName": "Slack"])
        analyzer.update()
        XCTAssertEqual(analyzer.snapshot.currentApp, "Slack")
        XCTAssertEqual(analyzer.snapshot.appSwitchRate30s, 2)
    }

    func testSameDomainTwice_doesNotAddTabSwitch() {
        let a = analyzer(events: [
            (type: "browser_domain", data: ["domain": "github.com"]),
            (type: "browser_domain", data: ["domain": "github.com"])
        ])
        XCTAssertEqual(a.snapshot.switchesPerMinute, 1)
    }
}
