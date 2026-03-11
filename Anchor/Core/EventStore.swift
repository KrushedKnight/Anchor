import Foundation
import Observation

@Observable
final class EventStore {
    static let shared = EventStore()

    var log: [AnchorEvent] = []
    private var nextId: Int64 = 0
    private let maxEvents = 10_000

    private init() {}

    func append(type: String, data: [String: String]) {
        let event = AnchorEvent(
            id: nextId,
            ts: Date().timeIntervalSince1970,
            type: type,
            data: data
        )
        nextId += 1
        log.append(event)
        if log.count > maxEvents {
            log.removeFirst(log.count - maxEvents)
        }
    }

    func slice(after id: Int64) -> [AnchorEvent] {
        log.filter { $0.id > id }
    }

    func recent(seconds: TimeInterval) -> [AnchorEvent] {
        let cutoff = Date().addingTimeInterval(-seconds).timeIntervalSince1970
        return log.filter { $0.ts >= cutoff }
    }
}
