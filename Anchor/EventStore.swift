import Foundation
import Observation

@Observable
final class EventStore {
    static let shared = EventStore()

    private var events: [AnchorEvent] = []
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
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    func events(after id: Int64) -> [AnchorEvent] {
        events.filter { $0.id > id }
    }

    func allEvents() -> [AnchorEvent] { events }
}
