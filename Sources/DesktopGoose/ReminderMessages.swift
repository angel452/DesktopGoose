import AppKit
import GooseArt
import GooseCore

/// The pool of lines the goose can say for each reminder. Add as many as you like —
/// one is picked at random each time a reminder is delivered.
enum ReminderMessages {
    private static let water = [
        "¡Tomá agua! 💧",
        "Hidratate, campeón.",
        "Un vaso de agua, dale.",
        "Tu cuerpo pide agua. 🚰",
    ]

    private static let move = [
        "¡Pará y caminá! 🦶",
        "Estirá esas patas.",
        "Levantate un toque.",
        "Movete, que oxida. 🚶",
    ]

    /// A styled line for `kind`, reusing the bubble's shared typography.
    static func attributed(for kind: ReminderKind) -> NSAttributedString {
        let pool = kind == .water ? water : move
        return SpeechBubble.text(pool.randomElement() ?? "honk!")
    }
}
