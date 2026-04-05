import Foundation

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
}

@Observable
final class AppAlertManager {
    static let shared = AppAlertManager()
    private init() {}

    var current: AppAlert?

    func post(title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        current = AppAlert(title: title, message: message, actionTitle: actionTitle, action: action)
    }
}
