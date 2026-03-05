import Foundation

final class DecisionBus {
    static let shared = DecisionBus()

    private var continuation: AsyncStream<EngineDecision>.Continuation?
    private var nextId: Int64 = 0

    let stream: AsyncStream<EngineDecision>

    init() {
        var cap: AsyncStream<EngineDecision>.Continuation?
        stream = AsyncStream { cap = $0 }
        continuation = cap
    }

    func publish(_ decision: EngineDecision) {
        var stamped  = decision
        stamped.id   = nextId
        stamped.ts   = Date().timeIntervalSince1970
        nextId      += 1
        continuation?.yield(stamped)
    }
}
