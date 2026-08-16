import AppKit
import GooseArt
import GooseCore

/// The lines the goose throws after a cursor chase. Two banks: one to gloat when it
/// lands a peck, one to save face when the cursor got away. Add as many as you like —
/// one is picked at random each time.
enum TauntMessages {
    private static let onCatch = [
        "¡JAJA noob!",
        "¡A casa! 🏠",
        "¿Qué mirás, bobo?",
        "Te agarré. 😤",
        "Más lento imposible.",
    ]

    private static let onGiveUp = [
        "Te estaré vigilando. 👀",
        "Tenés suerte que tengo cosas que hacer.",
        "Esta me la guardo.",
        "Corré, corré...",
    ]

    /// A styled gloat for a landed peck.
    static func attributedCatch() -> NSAttributedString {
        SpeechBubble.text(onCatch.randomElement() ?? "honk!")
    }

    /// A styled parting threat for a chase the goose lost.
    static func attributedGiveUp() -> NSAttributedString {
        SpeechBubble.text(onGiveUp.randomElement() ?? "honk!")
    }
}
