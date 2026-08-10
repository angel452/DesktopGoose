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

    /// The area the goose considers "the screen". Update it when the screen resizes.
    public var bounds: CGRect
    public let config: GooseConfig

    private var rng: RNG
    private var target: CGPoint
    private var timer: TimeInterval = 0
    private var distanceSinceStep: CGFloat = 0
    private var walksRemaining: Int = 0

    public init(bounds: CGRect, config: GooseConfig = GooseConfig(), rng: RNG) {
        self.bounds = bounds
        self.config = config
        self.rng = rng
        self.position = CGPoint(x: bounds.midX, y: bounds.midY)
        self.target = self.position

        self.walksRemaining = Int.random(in: config.walksBeforeExit, using: &self.rng)
        self.timer = TimeInterval.random(in: config.idleDuration, using: &self.rng)
    }

    /// Advances the goose by `deltaTime` seconds and returns everything that happened.
    public mutating func update(deltaTime: TimeInterval) -> [GooseEvent] {
        var events: [GooseEvent] = []

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
        case .walking, .leaving, .returning:
            advance(deltaTime: deltaTime, events: &events)
        }

        return events
    }

    // MARK: - Movement

    private mutating func advance(deltaTime: TimeInterval, events: inout [GooseEvent]) {
        let dx = target.x - position.x
        let dy = target.y - position.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let step = config.speed * CGFloat(deltaTime)

        if distance <= step || distance == 0 {
            move(dx: dx, dy: dy, events: &events)
            arrive(&events)
            return
        }

        move(dx: dx / distance * step, dy: dy / distance * step, events: &events)
    }

    private mutating func move(dx: CGFloat, dy: CGFloat, events: inout [GooseEvent]) {
        guard dx != 0 || dy != 0 else { return }
        if abs(dx) > 0.01 { facingLeft = dx < 0 }

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

            let droppedMeme = Double.random(in: 0...1, using: &rng) < config.memeChance
            if droppedMeme {
                events.append(.droppedMeme(position: position))
            }

            walksRemaining -= 1

            if droppedMeme {
                // Stand and wait by the delivery. Wandering off immediately would
                // pull the speech bubble away before it could be read.
                let pause = TimeInterval.random(in: config.memePauseDuration, using: &rng)
                beginIdle(duration: pause)
            } else if walksRemaining <= 0 {
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

        case .idle, .offscreen:
            break
        }
    }

    private mutating func beginIdle() {
        let duration = TimeInterval.random(in: config.idleDuration, using: &rng)
        beginIdle(duration: duration)
    }

    private mutating func beginIdle(duration: TimeInterval) {
        state = .idle
        timer = duration
    }

    private mutating func beginWalk() {
        target = interiorPoint()
        state = .walking
    }

    private mutating func beginExit() {
        target = exteriorPoint()
        state = .leaving
    }

    private mutating func beginReturn(_ events: inout [GooseEvent]) {
        // Reappear at an edge, feet caked in whatever it found out there.
        position = exteriorPoint()
        target = interiorPoint()
        muddyStepsRemaining = config.muddyStepCount
        distanceSinceStep = 0
        isVisible = true
        state = .returning
        events.append(.visibilityChanged(isVisible: true))
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
