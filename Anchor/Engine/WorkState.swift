import Foundation
import SwiftUI

enum WorkState: String {
    case deepFocus            = "Deep Focus"
    case productiveSwitching  = "Productive Switching"
    case stuckCycling         = "Stuck Cycling"
    case noveltySeeking       = "Novelty Seeking"
    case passiveDrift         = "Passive Drift"
    case idle                 = "Idle"

    var symbol: String {
        switch self {
        case .deepFocus:           "🎯"
        case .productiveSwitching: "🔀"
        case .stuckCycling:        "🔄"
        case .noveltySeeking:      "🦋"
        case .passiveDrift:        "📺"
        case .idle:                "💤"
        }
    }

    var stateColor: Color {
        switch self {
        case .deepFocus:           .green
        case .productiveSwitching: .blue
        case .stuckCycling:        .yellow
        case .noveltySeeking:      .orange
        case .passiveDrift:        .red
        case .idle:                .secondary
        }
    }
}
