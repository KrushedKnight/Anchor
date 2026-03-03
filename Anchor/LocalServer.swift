import Foundation
import Network

final class LocalServer {
    let port: UInt16 = 4545
    private var listener: NWListener?

    func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        listener = try? NWListener(using: .tcp, on: nwPort)
        listener?.newConnectionHandler = { conn in
            conn.start(queue: .global(qos: .utility))
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                guard let data, let text = String(data: data, encoding: .utf8) else {
                    conn.cancel(); return
                }
                Task { @MainActor in LocalServer.route(text, conn: conn) }
            }
        }
        listener?.start(queue: .global(qos: .utility))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    @MainActor
    private static func route(_ request: String, conn: NWConnection) {
        let line = request.components(separatedBy: "\r\n").first ?? ""
        let parts = line.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { conn.cancel(); return }

        let (path, params) = parsePath(String(parts[1]))

        switch path {
        case "/health":
            send(200, #"{"ok":true}"#, to: conn)
        case "/events":
            let after = Int64(params["after"] ?? "") ?? -1
            let events = EventStore.shared.slice(after: after)
            let body = (try? JSONEncoder().encode(events)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            send(200, body, to: conn)
        case "/metrics":
            send(200, buildMetrics(), to: conn)
        default:
            send(404, #"{"error":"not found"}"#, to: conn)
        }
    }

    private static func parsePath(_ raw: String) -> (path: String, params: [String: String]) {
        guard let qi = raw.firstIndex(of: "?") else { return (raw, [:]) }
        let path = String(raw[..<qi])
        var params: [String: String] = [:]
        for pair in raw[raw.index(after: qi)...].split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            params[String(kv[0]).removingPercentEncoding ?? ""] = String(kv[1]).removingPercentEncoding ?? ""
        }
        return (path, params)
    }

    @MainActor
    private static func buildMetrics() -> String {
        struct Metrics: Encodable {
            struct AppInfo: Encodable { let bundleId, appName: String }
            struct DomainInfo: Encodable { let browser, domain: String }
            let isIdle: Bool
            let dwellSec: Int
            let switchesLast60s: Int
            let activeApp: AppInfo?
            let currentDomain: DomainInfo?
        }

        let log = EventStore.shared.log
        let lastApp    = log.last { $0.type == "active_app" }
        let lastDomain = log.last { $0.type == "browser_domain" }
        let lastIdle   = log.last { $0.type == "idle_start" }
        let lastResume = log.last { $0.type == "idle_end" }

        let m = Metrics(
            isIdle: (lastIdle?.id ?? -1) > (lastResume?.id ?? -1),
            dwellSec: lastApp.map { Int(Date().timeIntervalSince1970 - $0.ts) } ?? 0,
            switchesLast60s: Int(lastDomain?.data["switchesLast60s"] ?? "0") ?? 0,
            activeApp: lastApp.map { .init(bundleId: $0.data["bundleId"] ?? "", appName: $0.data["appName"] ?? "") },
            currentDomain: lastDomain.map { .init(browser: $0.data["browser"] ?? "", domain: $0.data["domain"] ?? "") }
        )
        return (try? JSONEncoder().encode(m)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private static func send(_ status: Int, _ body: String, to conn: NWConnection) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Not Found")\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
    }
}
