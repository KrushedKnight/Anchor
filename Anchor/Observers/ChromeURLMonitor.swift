import Foundation

final class ChromeURLMonitor {
    var interval: TimeInterval = 1.0

    private var timer: Timer?
    private var lastURL:      String = ""
    private var lastTitle:    String = ""
    private var lastTabIndex: Int    = -1
    private var switchTimestamps: [Date] = []
    private let switchWindow: TimeInterval = 60

    func start() {
        if let r = queryChrome() { absorb(r) }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let result = queryChrome(), !result.url.isEmpty else { return }
        guard result.url != lastURL else { return }

        let url      = result.url
        let title    = result.title
        let tabIndex = result.tabIndex
        let domain   = extractDomain(from: url)
        let prevDomain = extractDomain(from: lastURL)
        let sessionId  = SessionManager.shared.activeSession?.id.uuidString ?? ""

        let now = Date()
        switchTimestamps.append(now)
        switchTimestamps.removeAll { now.timeIntervalSince($0) > switchWindow }

        EventStore.shared.append(
            type: "browser_domain",
            data: [
                "browser":        "chrome",
                "domain":         domain,
                "url":            url,
                "switchesLast60s": String(switchTimestamps.count)
            ]
        )

        let isTabSwitch = lastTabIndex != -1 && tabIndex != lastTabIndex

        if isTabSwitch {
            EventStore.shared.append(
                type: "browser_tab_changed",
                data: [
                    "session_id":         sessionId,
                    "browser_name":       "Chrome",
                    "previous_tab_title": lastTitle,
                    "new_tab_title":      title,
                    "previous_domain":    prevDomain,
                    "new_domain":         domain
                ]
            )
        } else {
            EventStore.shared.append(
                type: "browser_navigation",
                data: [
                    "session_id":      sessionId,
                    "browser_name":    "Chrome",
                    "previous_url":    lastURL,
                    "new_url":         url,
                    "previous_domain": prevDomain,
                    "new_domain":      domain
                ]
            )
        }

        if let session = SessionManager.shared.activeSession {
            emitDomainPolicyEvents(session: session, domain: domain, sessionId: sessionId)
        }

        absorb(result)
    }

    private func absorb(_ r: ChromeResult) {
        lastURL      = r.url
        lastTitle    = r.title
        lastTabIndex = r.tabIndex
    }

    private func emitDomainPolicyEvents(session: FocusSession, domain: String, sessionId: String) {
        if session.blockedDomains.contains(domain) {
            EventStore.shared.append(
                type: "context_entered_blocked_domain",
                data: ["session_id": sessionId, "domain": domain]
            )
        } else if session.allowedDomains.contains(domain) {
            EventStore.shared.append(
                type: "context_entered_allowed_domain",
                data: ["session_id": sessionId, "domain": domain]
            )
        }
    }

    private struct ChromeResult {
        var url:      String
        var title:    String
        var tabIndex: Int
    }

    private func queryChrome() -> ChromeResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", """
            tell application "Google Chrome"
                if (count of windows) = 0 then return ""
                set t to active tab of front window
                set idx to active tab index of front window
                return (URL of t) & "\t" & (title of t) & "\t" & (idx as string)
            end tell
            """]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = Pipe()

        do { try process.run() } catch { return nil }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else { return nil }

        let parts = raw.components(separatedBy: "\t")
        let url      = parts.first ?? ""
        let tabIndex = parts.count >= 3 ? (Int(parts[2]) ?? -1) : -1
        let title    = parts.count >= 2 ? parts[1] : ""

        return ChromeResult(url: url, title: title, tabIndex: tabIndex)
    }

    private func extractDomain(from url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
