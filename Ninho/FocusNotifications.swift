import Foundation
import UserNotifications
import NinhoCore

@MainActor protocol FocusNotificationCenter: AnyObject {
    func requestPermission() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func authorizationStatus() async -> UNAuthorizationStatus
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor private final class SystemFocusNotificationCenter: FocusNotificationCenter {
    private let center = UNUserNotificationCenter.current()
    func requestPermission() async throws -> Bool { try await center.requestAuthorization(options: [.alert]) }
    func pendingIdentifiers() async -> [String] {
        let requests = await center.pendingNotificationRequests()
        return requests.map(\.identifier)
    }
    func deliveredIdentifiers() async -> [String] {
        let notifications = await center.deliveredNotifications()
        return notifications.map { $0.request.identifier }
    }
    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }
    func removePending(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func removeDelivered(_ identifiers: [String]) { center.removeDeliveredNotifications(withIdentifiers: identifiers) }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
}

@MainActor final class FocusNotifications {
    private let center: any FocusNotificationCenter
    private let prefix = "ninho.focus.finished"
    private var pendingIdentifiers: Set<String> = []
    private var revision = 0

    init(center: (any FocusNotificationCenter)? = nil) { self.center = center ?? SystemFocusNotificationCenter() }
    private func owns(_ identifier: String) -> Bool { identifier == prefix || identifier.hasPrefix(prefix + ".") }

    func requestPermission() async throws -> Bool {
        try await center.requestPermission()
    }

    func update(_ timer: FocusTimer, at now: Date = Date()) async -> String {
        revision += 1; let requestRevision = revision
        center.removePending(Array(pendingIdentifiers)); pendingIdentifiers.removeAll()
        let oldIdentifiers = await center.pendingIdentifiers()
        guard requestRevision == revision else { return "" }
        center.removePending(oldIdentifiers.filter(owns))
        guard let deadline = timer.completionDate(at: now) else { return "" }
        let authorization = await center.authorizationStatus()
        guard requestRevision == revision else { return "" }
        guard authorization == .authorized || authorization == .provisional else {
            return "Ative o aviso para receber uma notificação ao terminar. O cronômetro funciona sem essa permissão."
        }
        let content = UNMutableNotificationContent()
        content.title = "Seu bloco de foco terminou"
        content.body = "Você fez espaço para aprender. Ao voltar, o Ninho registra o tempo desta sessão."
        content.sound = nil
        guard deadline > Date() else { return "" }
        let identifier = prefix + "." + UUID().uuidString
        pendingIdentifiers.insert(identifier)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            guard requestRevision == revision else {
                center.removePending([identifier]); pendingIdentifiers.remove(identifier); return ""
            }
            return "Aviso silencioso agendado. O modo Foco e os ajustes de notificações do iPhone podem silenciá-lo."
        } catch { return "Não foi possível agendar o aviso. A contagem continua salva: \(error.localizedDescription)" }
    }

    func cancel() async {
        revision += 1; let requestRevision = revision
        center.removePending(Array(pendingIdentifiers))
        center.removeDelivered(Array(pendingIdentifiers))
        pendingIdentifiers.removeAll()
        // Recovery can run before update() in a new process. Query the OS instead of relying
        // on this instance having seen the timer's original request identifier.
        let oldPending = await center.pendingIdentifiers()
        guard requestRevision == revision else { return }
        center.removePending(oldPending.filter(owns))
        let oldDelivered = await center.deliveredIdentifiers()
        guard requestRevision == revision else { return }
        center.removeDelivered(oldDelivered.filter(owns))
    }
}
