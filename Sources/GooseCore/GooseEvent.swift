import CoreGraphics
import Foundation

/// What the goose is currently doing.
public enum GooseState: Equatable, Sendable {
    /// Standing still, waiting out a timer.
    case idle
    /// Walking to a point inside the screen.
    case walking
    /// Walking to a point past the screen edge, on its way out.
    case leaving
    /// Out of sight, presumably stepping in mud.
    case offscreen
    /// Walking back in from the edge, feet dirty.
    case returning
}

/// Something the goose did that the outside world has to react to.
///
/// The brain never draws, plays audio or opens windows. It only reports.
public enum GooseEvent: Equatable, Sendable {
    /// A foot touched down. `muddy` prints leave a mark on screen.
    case footprint(position: CGPoint, muddy: Bool)
    /// Honk.
    case honk
    /// The goose dropped a meme at this position.
    case droppedMeme(position: CGPoint)
    /// The goose stopped standing around and set off again. Anything that was only
    /// true while it stood still — a speech bubble, above all — ends here.
    case startedMoving
    /// The goose walked off screen (`false`) or came back (`true`).
    case visibilityChanged(isVisible: Bool)
}
