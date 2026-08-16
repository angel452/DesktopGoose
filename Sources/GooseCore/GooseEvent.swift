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
    /// Heading off screen to fetch a reminder, interrupting the wander.
    case deliveringExit
    /// Walking in from a side edge toward the centre, reminder in tow.
    case deliveringEntry
    /// Standing at the centre while the reminder is on screen.
    case presenting
    /// Locked onto an invading cursor, glaring it down before the charge — the
    /// telegraph that gives the human a moment to run.
    case alerting
    /// Charging at a cursor that invaded its personal space.
    case charging
}

/// Something the goose did that the outside world has to react to.
///
/// The brain never draws, plays audio or opens windows. It only reports.
public enum GooseEvent: Equatable, Sendable {
    /// A foot touched down. `muddy` prints leave a mark on screen.
    case footprint(position: CGPoint, muddy: Bool)
    /// Honk.
    case honk
    /// The goose caught the cursor with a peck, at this position. Carries a taunt.
    case pecked(position: CGPoint)
    /// The goose ran out of chase and gave up, at this position — earning the cursor
    /// a parting threat rather than a peck.
    case gaveUpChase(position: CGPoint)
    /// The goose arrived at the centre with a reminder to show at `position`.
    case showReminder(position: CGPoint)
    /// The goose stopped standing around and set off again. Anything that was only
    /// true while it stood still — a speech bubble, above all — ends here.
    case startedMoving
    /// The goose walked off screen (`false`) or came back (`true`).
    case visibilityChanged(isVisible: Bool)
}
