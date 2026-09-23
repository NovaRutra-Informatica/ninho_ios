import AppIntents
import SwiftUI

/// Consumed only after the profile is ready. A shortcut never starts study time.
@MainActor final class SystemRouteRequests: ObservableObject {
    static let shared = SystemRouteRequests()
    @Published var pendingRoute: String?
    func request(_ route: String) { pendingRoute = route }
}

struct OpenNinhoFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir meu foco"
    static let description = IntentDescription("Abre o cronômetro do Ninho. Você escolhe quando começar.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        SystemRouteRequests.shared.request("focus")
        return .result()
    }
}

struct OpenNinhoReviewsIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir minhas revisões"
    static let description = IntentDescription("Abre as revisões disponíveis no Ninho, sem expor o conteúdo dos cartões ao atalho.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        SystemRouteRequests.shared.request("reviews")
        return .result()
    }
}

struct NinhoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenNinhoFocusIntent(), phrases: ["Abrir meu foco no \(.applicationName)"], shortTitle: "Hora de focar", systemImageName: "timer")
        AppShortcut(intent: OpenNinhoReviewsIntent(), phrases: ["Abrir minhas revisões no \(.applicationName)"], shortTitle: "Minhas revisões", systemImageName: "rectangle.on.rectangle")
    }
    static var shortcutTileColor: ShortcutTileColor { .green }
}
