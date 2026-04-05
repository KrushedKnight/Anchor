import Foundation
import UserNotifications

@Observable
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    private(set) var isGranted: Bool?

    private let bus: InterventionBus
    private var subscriptionId: UUID?
    private var task: Task<Void, Never>?

    init(bus: InterventionBus = .shared) {
        self.bus = bus
    }

    func start() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { self.isGranted = granted }
        }
        UNUserNotificationCenter.current().delegate = self

        let (id, stream) = bus.subscribe()
        subscriptionId = id

        task = Task { @MainActor in
            for await intervention in stream {
                fire(intervention)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if let id = subscriptionId {
            bus.unsubscribe(id)
            subscriptionId = nil
        }
    }

    private func fire(_ intervention: Intervention) {
        print("[NotificationHandler] firing: \(intervention.title)")
        let content       = UNMutableNotificationContent()
        content.title     = intervention.title
        content.body      = intervention.body
        content.sound     = intervention.level == .strong ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: intervention.id.uuidString,
            content:    content,
            trigger:    nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[NotificationHandler] add failed: \(error)") }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
