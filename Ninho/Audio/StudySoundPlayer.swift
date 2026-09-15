import Foundation
import AVFAudio
import NinhoCore

@MainActor final class StudySoundPlayer {
    private var player: AVAudioPlayer?
    private var cache: [SoundCue: Data] = [:]

    /// Ambient obeys Silent mode and mixes with other audio.
    func play(_ cue: SoundCue, enabled: Bool) {
        guard enabled else { stop(); return }
        let session = AVAudioSession.sharedInstance()
        // Preserve AVKit's playback category.
        guard session.category == .ambient || session.category == .soloAmbient else { return }
        do {
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            let data = cache[cue] ?? StudySounds.waveData(for: cue)
            cache[cue] = data
            player?.stop()
            let next = try AVAudioPlayer(data: data)
            next.volume = 0.42
            next.prepareToPlay()
            player = next
            next.play()
        } catch {
            // Audio failure must not fail a persisted action.
            player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        // AVAudioSession is shared with AVKit; do not deactivate another player.
    }
}
