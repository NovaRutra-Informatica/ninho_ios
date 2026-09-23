import Foundation
import AVFAudio
import NinhoCore

@MainActor final class StudySoundPlayer {
    private var player: AVAudioPlayer?
    private var cache: [SoundCue: Data] = [:]
    private var lastNavigationUptime: TimeInterval = -.infinity

    func play(_ cue: SoundCue, enabled: Bool) {
        guard enabled else { stop(); return }
        let uptime = ProcessInfo.processInfo.systemUptime
        if cue == .navigation {
            guard uptime - lastNavigationUptime >= 0.14, player?.isPlaying != true else { return }
        }
        let session = AVAudioSession.sharedInstance()
        guard !session.isOtherAudioPlaying else { stop(); return }
        // Preserve AVKit's playback category.
        guard session.category == .ambient || session.category == .soloAmbient else { return }
        do {
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            let data = cache[cue] ?? StudySounds.waveData(for: cue)
            cache[cue] = data
            player?.stop()
            let next = try AVAudioPlayer(data: data)
            next.volume = cue == .navigation ? 0.24 : 0.42
            next.prepareToPlay()
            player = next
            if next.play(), cue == .navigation { lastNavigationUptime = uptime }
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
