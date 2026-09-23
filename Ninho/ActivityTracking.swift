import SwiftUI
import NinhoCore

private struct NinhoActivityModifier: ViewModifier {
    @EnvironmentObject private var store: NinhoStore
    let route: MentorRoute
    @State private var token = UUID()
    func body(content: Content) -> some View {
        content.onAppear { store.showRoute(route, token: token) }
            .onDisappear { store.hideRoute(token: token) }
    }
}

extension View {
    func ninhoActivity(_ route: MentorRoute) -> some View { modifier(NinhoActivityModifier(route: route)) }
}
