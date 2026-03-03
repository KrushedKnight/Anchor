import Foundation

final class ChromeURLMonitor {
    var interval: TimeInterval = 1.0

    private var timer: Timer?
    private var lastURL: String = ""
    private var switchTimestamps: [Date] = []
    private let switchWindow: TimeInterval = 60

    func start() {
        _ = queryChrome()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let url = queryChrome(), !url.isEmpty else { return }
        guard url != lastURL else { return }

        lastURL = url
        let domain = extractDomain(from: url)

        let now = Date()
        switchTimestamps.append(now)
        switchTimestamps.removeAll { now.timeIntervalSince($0) > switchWindow }

        EventStore.shared.append(
            type: "browser_domain",
            data: [
                "browser": "chrome",
                "domain": domain,
                "url": url,
                "switchesLast60s": String(switchTimestamps.count)
            ]
        )
    }

    private func queryChrome() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", """
            tell application "Google Chrome"
                if (count of windows) = 0 then return ""
                return URL of active tab of front window
            end tell
            """]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do { try process.run() } catch { return nil }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractDomain(from url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
