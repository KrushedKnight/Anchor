import Foundation
import SwiftUI

enum WorkState: String {
    case deepFocus            = "Locked In"
    case productiveSwitching  = "On Track"
    case stuckCycling         = "Going in Circles"
    case noveltySeeking       = "Wandering"
    case passiveDrift         = "Zoned Out"
    case idle                 = "Away"

    var stateColor: Color {
        switch self {
        case .deepFocus:           Color.anchorSage
        case .productiveSwitching: Color.anchorSage.opacity(0.75)
        case .stuckCycling:        Color.anchorAmber
        case .noveltySeeking:      Color.anchorAmber
        case .passiveDrift:        .anchorRed
        case .idle:                Color.anchorTextMuted
        }
    }

    var baseTargetScore: Double {
        switch self {
        case .deepFocus:           0.95
        case .productiveSwitching: 0.80
        case .stuckCycling:        0.60
        case .noveltySeeking:      0.40
        case .passiveDrift:        0.35
        case .idle:                0.50
        }
    }

    var decayFloor: Double {
        switch self {
        case .deepFocus:           0.90
        case .productiveSwitching: 0.70
        case .stuckCycling:        0.40
        case .noveltySeeking:      0.15
        case .passiveDrift:        0.10
        case .idle:                0.35
        }
    }
}
