import AppKit
import GooseArt
import GooseCore

/// The lines the goose throws after a cursor chase. The banks themselves live in
/// `GooseLines`, shared with every platform; this only styles them for AppKit.
enum TauntMessages {
    /// A styled gloat for a landed peck.
    static func attributedCatch() -> NSAttributedString {
        SpeechBubble.text(GooseLines.onCatch.randomElement() ?? GooseLines.fallback)
    }

    /// A styled parting threat for a chase the goose lost.
    static func attributedGiveUp() -> NSAttributedString {
        SpeechBubble.text(GooseLines.onGiveUp.randomElement() ?? GooseLines.fallback)
    }
}
