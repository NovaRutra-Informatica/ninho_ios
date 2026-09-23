import SwiftUI

private struct NinhoPageTransition: ViewModifier {
    @EnvironmentObject private var store: NinhoStore
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @State private var appeared = false
    private var reducedMotion: Bool { systemReducedMotion || store.displaySettings.reducedMotion }

    func body(content: Content) -> some View {
        content
            .opacity(reducedMotion || appeared ? 1 : 0)
            .offset(y: reducedMotion || appeared ? 0 : 6)
            .onAppear {
                withAnimation(reducedMotion ? nil : .easeOut(duration: 0.22)) { appeared = true }
            }
            .onDisappear { appeared = false }
    }
}

extension View {
    func ninhoPageTransition() -> some View { modifier(NinhoPageTransition()) }
}

struct NinhoMascot: View {
    @EnvironmentObject private var store: NinhoStore
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @State private var appearance = 0
    let size: CGFloat
    private var reducedMotion: Bool { systemReducedMotion || store.displaySettings.reducedMotion }

    private struct Pose {
        var scale: CGFloat = 1
        var rotation: Double = 0
        var offset: CGFloat = 0
    }

    var body: some View {
        let motionEnabled = !reducedMotion
        Image("owl")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: Pose(), trigger: appearance) { content, pose in
                content
                    .scaleEffect(motionEnabled ? pose.scale : 1)
                    .rotationEffect(.degrees(motionEnabled ? pose.rotation : 0))
                    .offset(y: motionEnabled ? pose.offset : 0)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.035, duration: 0.28)
                    CubicKeyframe(1, duration: 0.42)
                }
                KeyframeTrack(\.rotation) {
                    CubicKeyframe(-3, duration: 0.20)
                    CubicKeyframe(2, duration: 0.24)
                    CubicKeyframe(0, duration: 0.26)
                }
                KeyframeTrack(\.offset) {
                    CubicKeyframe(-2, duration: 0.28)
                    CubicKeyframe(0, duration: 0.42)
                }
            }
            .onAppear { if !reducedMotion { appearance += 1 } }
            .accessibilityHidden(true)
    }
}
