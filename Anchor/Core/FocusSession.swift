import Foundation

struct FocusSession {
    enum Strictness: String, CaseIterable {
        case normal = "Normal"
        case strict = "Strict"
    }

    var id:             UUID         = UUID()
    var startedAt:      Date         = .now
    var taskTitle:      String
    var strictness:     Strictness
    var allowedApps:    Set<String>  = []
    var ambiguousApps:  Set<String>  = []
    var blockedApps:    Set<String>  = []
    var allowedDomains: Set<String>  = []
    var blockedDomains: Set<String>  = []
}
