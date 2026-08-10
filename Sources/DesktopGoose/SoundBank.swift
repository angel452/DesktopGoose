import AppKit

/// Plays honks from `Assets/Sounds`, falling back to a system sound so the app is
/// never silent just because no audio has been added yet.
final class SoundBank {
    private var honks: [NSSound]
    private var nextIndex = 0

    init() {
        honks = Assets.soundURLs().compactMap { NSSound(contentsOf: $0, byReference: true) }
    }

    func honk() {
        guard !honks.isEmpty else {
            NSSound(named: "Pop")?.play()
            return
        }

        let sound = honks[nextIndex % honks.count]
        nextIndex += 1
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}
