import AppKit
import GooseArt
import GooseCore

/// The line the goose says when a reminder is delivered. The bank lives in
/// `GooseLines`, shared with every platform; this only styles it for AppKit.
enum ReminderMessages {
    /// A styled reminder line, reusing the bubble's shared typography.
    static func attributed() -> NSAttributedString {
        SpeechBubble.text(GooseLines.reminders.randomElement() ?? GooseLines.fallback)
    }
}
