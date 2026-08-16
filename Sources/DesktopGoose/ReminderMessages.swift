import AppKit
import GooseArt
import GooseCore

/// The pool of lines the goose can say when a reminder is delivered. One clock
/// drives every reminder, so the water and move nudges share a single bank — add
/// as many as you like; one is picked at random each time.
enum ReminderMessages {
    private static let lines = [
        "¡Tomá agua! 💧",
        "Hidratate, campeón.",
        "Un vaso de agua, dale.",
        "Tu cuerpo pide agua. 🚰",
        "¡Pará y caminá! 🦶",
        "Estirá esas patas.",
        "Levantate un toque.",
        "Movete, que oxida. 🚶",
    ]

    /// A styled reminder line, reusing the bubble's shared typography.
    static func attributed() -> NSAttributedString {
        SpeechBubble.text(lines.randomElement() ?? "honk!")
    }
}
