import AppKit
import GooseCore

/// Plays honks from `Assets/Sounds`, falling back to a system sound so the app is
/// never silent just because no audio has been added yet. How loud is the human's
/// call, and it outlives a restart.
final class SoundBank {
    private static let levelKey = "soundLevel"

    private var honks: [NSSound]
    private var nextIndex = 0

    var level: SoundLevel {
        didSet { UserDefaults.standard.set(level.storedValue, forKey: SoundBank.levelKey) }
    }

    init() {
        honks = Assets.soundURLs().compactMap { NSSound(contentsOf: $0, byReference: true) }
        level = SoundLevel(storedValue: UserDefaults.standard.string(forKey: SoundBank.levelKey))
    }

    func honk() {
        guard level != .mute else { return }
        guard let sound = honks.isEmpty ? NSSound(named: "Pop") : honks[nextIndex % honks.count] else { return }

        nextIndex += 1
        if sound.isPlaying { sound.stop() }
        // NSSound's own volume: only the goose gets quieter, never the Mac.
        sound.volume = Float(level.gain)
        sound.play()
    }
}
