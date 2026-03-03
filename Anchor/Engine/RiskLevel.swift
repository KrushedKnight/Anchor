enum RiskLevel: Int, Comparable {
    case stable = 0
    case atRisk = 1
    case drift  = 2

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
