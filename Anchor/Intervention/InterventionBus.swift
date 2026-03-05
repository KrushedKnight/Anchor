import Foundation

final class InterventionBus {
    static let shared = InterventionBus()

    private var subscribers: [UUID: AsyncStream<Intervention>.Continuation] = [:]

    func subscribe() -> (UUID, AsyncStream<Intervention>) {
        var cap: AsyncStream<Intervention>.Continuation!
        let stream = AsyncStream<Intervention> { cap = $0 }
        let id = UUID()
        subscribers[id] = cap
        return (id, stream)
    }

    func unsubscribe(_ id: UUID) {
        subscribers[id]?.finish()
        subscribers.removeValue(forKey: id)
    }

    func publish(_ intervention: Intervention) {
        for continuation in subscribers.values {
            continuation.yield(intervention)
        }
    }
}
