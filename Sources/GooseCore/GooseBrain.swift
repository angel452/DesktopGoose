import CoreGraphics
import Foundation

/// The goose's behaviour, expressed as a state machine advanced by elapsed time.
///
/// It owns no timer, no view and no window. You feed it `deltaTime` and it hands
/// back the events the presentation layer has to perform. That is what makes the
/// whole thing testable without ever opening a window.
public struct GooseBrain<RNG: RandomNumberGenerator> {
    public private(set) var state: GooseState = .idle
    public private(set) var position: CGPoint
    public private(set) var isVisible: Bool = true
    public private(set) var facingLeft: Bool = false
    public private(set) var muddyStepsRemaining: Int = 0
    /// While dragging a reminder in, which side the meme trails on — the edge the
    /// goose came from. Only meaningful during `.deliveringEntry`/`.presenting`.
    public private(set) var dragFromLeft: Bool = false

    /// The area the goose considers "the screen". Update it when the screen resizes.
    public var bounds: CGRect
    public let config: GooseConfig

    private var rng: RNG
    private var target: CGPoint
    private var timer: TimeInterval = 0
    private var distanceSinceStep: CGFloat = 0
    private var walksRemaining: Int = 0
    /// Multiplies `config.speed` for the current move. Dashes set it above 1.
    private var speedMultiplier: CGFloat = 1
    /// When true the goose faces against its motion — walking backward to drag a
    /// meme, rather than facing where it is going.
    private var facesBackward = false
    /// Desk time left until each reminder is due. Counts down every frame.
    private var waterTimer: TimeInterval
    private var moveTimer: TimeInterval
    /// A reminder waiting for a safe moment to interrupt the wander.
    private var pendingReminder: ReminderKind?
    /// The reminder currently being delivered, or nil when just wandering.
    private var activeReminder: ReminderKind?

    public init(bounds: CGRect, config: GooseConfig = GooseConfig(), rng: RNG) {
        self.bounds = bounds
        self.config = config
        self.rng = rng
        self.position = CGPoint(x: bounds.midX, y: bounds.midY)
        self.target = self.position
        self.waterTimer = config.waterInterval
        self.moveTimer = config.moveInterval

        self.walksRemaining = Int.random(in: config.walksBeforeExit, using: &self.rng)
        self.timer = TimeInterval.random(in: config.idleDuration, using: &self.rng)
    }

    /// Triggers a reminder delivery by hand — from a menu, or a test — the same way
    /// the internal clock does when it runs out.
    public mutating func requestReminder(_ kind: ReminderKind) {
        // Queue it unconditionally. If a delivery is in flight this fires right
        // after it (so the menu click is never a silent no-op), and the frozen
        // clocks mean a scheduled reminder bumped from the slot is not lost.
        pendingReminder = kind
    }

    /// Advances the goose by `deltaTime` seconds and returns everything that happened.
    public mutating func update(deltaTime: TimeInterval) -> [GooseEvent] {
        var events: [GooseEvent] = []

        advanceReminderClocks(deltaTime: deltaTime)
        startDeliveryIfDue(&events)

        switch state {
        case .idle:
            timer -= deltaTime
            if timer <= 0 {
                beginWalk()
                events.append(.startedMoving)
            }
        case .offscreen:
            timer -= deltaTime
            if timer <= 0 {
                beginReturn(&events)
                events.append(.startedMoving)
            }
        case .presenting:
            timer -= deltaTime
            if timer <= 0 {
                activeReminder = nil
                events.append(.startedMoving)
                beginIdle()
            }
        case .walking, .leaving, .returning, .deliveringExit, .deliveringEntry:
            advance(deltaTime: deltaTime, events: &events)
        }

        return events
    }

    // MARK: - Reminders

    private mutating func advanceReminderClocks(deltaTime: TimeInterval) {
        // While a delivery is in flight the clocks freeze. Otherwise the other
        // reminder's clock drains during the ~15s fetch and fires the instant this
        // one ends, dumping two interruptions back-to-back.
        guard activeReminder == nil else { return }

        // These count time actually spent at the desk. The caller clamps the frame
        // delta, so a sleeping Mac barely advances them — "sit for 45 minutes"
        // should not keep ticking while you are away.
        waterTimer -= deltaTime
        moveTimer -= deltaTime

        // Latch the due reminder but leave its clock alone: the reset happens when
        // the delivery actually starts (see startDeliveryIfDue). That way a reminder
        // bumped out of the pending slot re-latches next frame instead of being lost
        // for a whole interval.
        guard pendingReminder == nil else { return }
        if waterTimer <= 0 {
            pendingReminder = .water
        } else if moveTimer <= 0 {
            pendingReminder = .move
        }
    }

    private mutating func startDeliveryIfDue(_ events: inout [GooseEvent]) {
        // Only interrupt ordinary on-screen wandering; a normal trip off screen
        // finishes first, then the delivery begins.
        guard let kind = pendingReminder, state == .idle || state == .walking else { return }
        pendingReminder = nil
        activeReminder = kind
        // Restart this reminder's clock now that it is genuinely being delivered,
        // not merely when it was latched.
        switch kind {
        case .water: waterTimer = config.waterInterval
        case .move: moveTimer = config.moveInterval
        }
        beginDeliveryExit()
        events.append(.startedMoving)
    }

    // MARK: - Movement

    private mutating func advance(deltaTime: TimeInterval, events: inout [GooseEvent]) {
        let dx = target.x - position.x
        let dy = target.y - position.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let step = config.speed * speedMultiplier * CGFloat(deltaTime)

        if distance <= step || distance == 0 {
            move(dx: dx, dy: dy, events: &events)
            arrive(&events)
            return
        }

        move(dx: dx / distance * step, dy: dy / distance * step, events: &events)
    }

    private mutating func move(dx: CGFloat, dy: CGFloat, events: inout [GooseEvent]) {
        guard dx != 0 || dy != 0 else { return }
        // Backward-dragging flips the facing: the goose looks toward the meme it
        // hauls, which is on the side it is moving away from.
        if abs(dx) > 0.01 { facingLeft = facesBackward ? dx > 0 : dx < 0 }

        let travelled = (dx * dx + dy * dy).squareRoot()
        let start = position
        position.x += dx
        position.y += dy

        // Footprints land on exact stride multiples along the segment travelled
        // this frame, not wherever the frame happened to end. Otherwise the gap
        // between prints inherits the frame rate.
        let unitX = dx / travelled
        let unitY = dy / travelled
        var distanceIntoSegment = config.stepDistance - distanceSinceStep

        while distanceIntoSegment <= travelled {
            defer { distanceIntoSegment += config.stepDistance }
            guard isVisible else { continue }

            let muddy = muddyStepsRemaining > 0
            if muddy { muddyStepsRemaining -= 1 }
            events.append(.footprint(
                position: CGPoint(
                    x: start.x + unitX * distanceIntoSegment,
                    y: start.y + unitY * distanceIntoSegment
                ),
                muddy: muddy
            ))
        }

        distanceSinceStep = travelled - (distanceIntoSegment - config.stepDistance)
    }

    // MARK: - Transitions

    private mutating func arrive(_ events: inout [GooseEvent]) {
        switch state {
        case .walking:
            if Double.random(in: 0...1, using: &rng) < config.honkChance {
                events.append(.honk)
            }

            walksRemaining -= 1
            if walksRemaining <= 0 {
                beginExit()
            } else {
                beginIdle()
            }

        case .leaving:
            isVisible = false
            state = .offscreen
            timer = TimeInterval.random(in: config.offscreenDuration, using: &rng)
            events.append(.visibilityChanged(isVisible: false))

        case .returning:
            walksRemaining = Int.random(in: config.walksBeforeExit, using: &rng)
            beginIdle()

        case .deliveringExit:
            // Off screen now; come straight back in from a side edge.
            beginDeliveryEntry()

        case .deliveringEntry:
            // Reached the centre; stand and show the reminder.
            beginPresenting(&events)

        case .idle, .offscreen, .presenting:
            break
        }
    }

    private mutating func beginIdle() {
        // A loiter occasionally deepens into a long, still ponder, so the goose is
        // not always back on the move after the same short beat.
        let pondering = Double.random(in: 0...1, using: &rng) < config.ponderChance
        let range = pondering ? config.ponderDuration : config.idleDuration
        let duration = TimeInterval.random(in: range, using: &rng)
        beginIdle(duration: duration)
    }

    private mutating func beginIdle(duration: TimeInterval) {
        state = .idle
        timer = duration
    }

    private mutating func beginWalk() {
        target = interiorPoint()
        // Some walks break into a dash, so the goose's pace stops being a constant
        // you can read. A stroll is just a dash with a multiplier of 1.
        let dashing = Double.random(in: 0...1, using: &rng) < config.dashChance
        speedMultiplier = dashing ? config.dashSpeedMultiplier : 1
        facesBackward = false
        state = .walking
    }

    private mutating func beginExit() {
        target = exteriorPoint()
        speedMultiplier = 1
        facesBackward = false
        state = .leaving
    }

    // MARK: - Reminder delivery

    private mutating func beginDeliveryExit() {
        target = exteriorPoint()
        speedMultiplier = 1
        facesBackward = false
        muddyStepsRemaining = 0
        state = .deliveringExit
    }

    private mutating func beginDeliveryEntry() {
        // Reappear off a side edge at mid-height and head for the centre, so the
        // approach is horizontal — the direction the dragged meme will come from.
        let overshoot: CGFloat = 140
        let fromLeft = Bool.random(using: &rng)
        let startX = fromLeft ? bounds.minX - overshoot : bounds.maxX + overshoot
        position = CGPoint(x: startX, y: bounds.midY)
        target = CGPoint(x: bounds.midX, y: bounds.midY)
        distanceSinceStep = 0
        // Haul it in slowly — a deliberate trudge, not a sprint.
        speedMultiplier = config.dragSpeedMultiplier
        // Drag it in backward, meme trailing on the edge it came from.
        dragFromLeft = fromLeft
        facesBackward = true
        state = .deliveringEntry
    }

    private mutating func beginPresenting(_ events: inout [GooseEvent]) {
        state = .presenting
        timer = TimeInterval.random(in: config.reminderHoldDuration, using: &rng)
        events.append(.showReminder(kind: activeReminder ?? .water, position: position))
    }

    private mutating func beginReturn(_ events: inout [GooseEvent]) {
        // Reappear at an edge, feet sometimes caked in whatever it found out there
        // and sometimes clean, so the return is never quite the same twice.
        position = exteriorPoint()
        target = interiorPoint()
        let broughtMud = Double.random(in: 0...1, using: &rng) < config.muddyReturnChance
        muddyStepsRemaining = broughtMud ? config.muddyStepCount : 0
        distanceSinceStep = 0
        isVisible = true
        speedMultiplier = 1
        facesBackward = false
        state = .returning
        events.append(.visibilityChanged(isVisible: true))

        // The greeting honk is a coin toss now, not a guarantee.
        if Double.random(in: 0...1, using: &rng) < config.returnHonkChance {
            events.append(.honk)
        }
    }

    // MARK: - Target picking

    // Each `randomValue` call mutates the generator, so they are sequenced into
    // separate statements rather than nested in one expression.
    private mutating func interiorPoint() -> CGPoint {
        let x = randomValue(from: bounds.minX, to: bounds.maxX, inset: config.margin)
        let y = randomValue(from: bounds.minY, to: bounds.maxY, inset: config.margin)
        return CGPoint(x: x, y: y)
    }

    private mutating func exteriorPoint() -> CGPoint {
        let overshoot: CGFloat = 140
        let left = bounds.minX
        let right = bounds.maxX
        let bottom = bounds.minY
        let top = bounds.maxY

        let edge = Int.random(in: 0..<4, using: &rng)

        switch edge {
        case 0:
            let y = randomValue(from: bottom, to: top, inset: 0)
            return CGPoint(x: left - overshoot, y: y)
        case 1:
            let y = randomValue(from: bottom, to: top, inset: 0)
            return CGPoint(x: right + overshoot, y: y)
        case 2:
            let x = randomValue(from: left, to: right, inset: 0)
            return CGPoint(x: x, y: bottom - overshoot)
        default:
            let x = randomValue(from: left, to: right, inset: 0)
            return CGPoint(x: x, y: top + overshoot)
        }
    }

    /// Picks a value inside `low...high`, shrunk by `inset` on both sides when the
    /// range is wide enough to survive it.
    private mutating func randomValue(from low: CGFloat, to high: CGFloat, inset: CGFloat) -> CGFloat {
        let usableInset = (high - low) > inset * 3 ? inset : 0
        let lower = low + usableInset
        let upper = high - usableInset
        guard upper > lower else { return (low + high) / 2 }
        return CGFloat.random(in: lower...upper, using: &rng)
    }
}
