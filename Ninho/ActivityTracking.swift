import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import NinhoCore

struct NinhoInteractionObserver: UIViewRepresentable {
    var onInteraction: @MainActor () -> Void

    func makeUIView(context: Context) -> NinhoInteractionView {
        let view = NinhoInteractionView()
        view.isUserInteractionEnabled = false
        view.recognizer.onInteraction = onInteraction
        return view
    }

    func updateUIView(_ view: NinhoInteractionView, context: Context) {
        view.recognizer.onInteraction = onInteraction
    }

    static func dismantleUIView(_ view: NinhoInteractionView, coordinator: ()) {
        view.detach()
    }
}

final class NinhoInteractionView: UIView {
    let recognizer = NinhoInteractionRecognizer()
    private weak var observedWindow: UIWindow?

    override init(frame: CGRect) {
        super.init(frame: frame)
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard observedWindow !== window else { return }
        detach()
        guard let window else { return }
        window.addGestureRecognizer(recognizer)
        observedWindow = window
    }

    func detach() {
        observedWindow?.removeGestureRecognizer(recognizer)
        observedWindow = nil
    }
}

final class NinhoInteractionRecognizer: UIGestureRecognizer {
    var onInteraction: @MainActor () -> Void = {}
    private var activeTouches = Set<UITouch>()

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        activeTouches.formUnion(touches)
        onInteraction()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        onInteraction()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        activeTouches.subtract(touches)
        if activeTouches.isEmpty { state = .failed }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        activeTouches.subtract(touches)
        if activeTouches.isEmpty { state = .failed }
    }

    override func reset() {
        super.reset()
        activeTouches.removeAll()
    }
}

private struct NinhoActivityModifier: ViewModifier {
    @EnvironmentObject private var store: NinhoStore
    let route: MentorRoute
    @State private var token = UUID()
    func body(content: Content) -> some View {
        content.onAppear { store.showRoute(route, token: token); store.playNavigationSound() }
            .onDisappear { store.hideRoute(token: token) }
    }
}

extension View {
    func ninhoActivity(_ route: MentorRoute) -> some View { modifier(NinhoActivityModifier(route: route)) }
}
