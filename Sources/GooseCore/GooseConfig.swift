import CoreGraphics
import Foundation

/// Tuning knobs for the goose's behaviour. All durations are in seconds and all
/// distances are in screen points.
public struct GooseConfig: Sendable {
    /// Walking speed, in points per second.
    public var speed: CGFloat
    /// How far the goose travels between two footprints.
    public var stepDistance: CGFloat
    /// How many footprints stay muddy after coming back from off screen.
    public var muddyStepCount: Int
    /// How long the goose stands still between walks.
    public var idleDuration: ClosedRange<TimeInterval>
    /// How long it stands admiring a meme it just delivered. Longer than a normal
    /// idle, so the thing it brought can actually be read.
    public var memePauseDuration: ClosedRange<TimeInterval>
    /// How long the goose stays out of sight.
    public var offscreenDuration: ClosedRange<TimeInterval>
    /// How many walks it completes before wandering off screen again.
    public var walksBeforeExit: ClosedRange<Int>
    /// Probability of honking at the end of a walk.
    public var honkChance: Double
    /// Probability of dropping a meme at the end of a walk. Defaults to 0: memes now
    /// arrive through scheduled reminders, not at random.
    public var memeChance: Double
    /// Keeps walk targets away from the very edge of the screen.
    public var margin: CGFloat
    /// Probability a return trip brings mud back on the feet. Below 1 so the goose
    /// sometimes reappears clean and the return stops being a fixed beat.
    public var muddyReturnChance: Double
    /// Probability the goose honks as it reappears, instead of every single time.
    public var returnHonkChance: Double
    /// Probability a walk breaks into a fast dash rather than an even stroll.
    public var dashChance: Double
    /// How much faster a dashing goose moves, as a multiple of `speed`.
    public var dashSpeedMultiplier: CGFloat
    /// Probability a loiter deepens into a long, motionless ponder.
    public var ponderChance: Double
    /// How long a ponder lasts — well past an ordinary idle.
    public var ponderDuration: ClosedRange<TimeInterval>
    /// Desk time between water-break reminders. Counts active time, not wall time:
    /// the frame delta is clamped by the caller, so a sleeping Mac barely advances it.
    public var waterInterval: TimeInterval
    /// Desk time between stand-up-and-move reminders.
    public var moveInterval: TimeInterval
    /// How long the goose stands at the centre with a reminder on screen.
    public var reminderHoldDuration: ClosedRange<TimeInterval>
    /// Speed multiplier while dragging a meme in — below 1 so the haul is a slow,
    /// deliberate trudge instead of a normal walk.
    public var dragSpeedMultiplier: CGFloat

    public init(
        speed: CGFloat = 150,
        stepDistance: CGFloat = 36,
        muddyStepCount: Int = 24,
        idleDuration: ClosedRange<TimeInterval> = 0.4...3.5,
        memePauseDuration: ClosedRange<TimeInterval> = 4.0...6.0,
        offscreenDuration: ClosedRange<TimeInterval> = 1.5...7.0,
        walksBeforeExit: ClosedRange<Int> = 2...9,
        honkChance: Double = 0.25,
        memeChance: Double = 0,
        margin: CGFloat = 60,
        muddyReturnChance: Double = 0.7,
        returnHonkChance: Double = 0.6,
        dashChance: Double = 0.2,
        dashSpeedMultiplier: CGFloat = 2.2,
        ponderChance: Double = 0.15,
        ponderDuration: ClosedRange<TimeInterval> = 3.0...6.0,
        waterInterval: TimeInterval = 45 * 60,
        moveInterval: TimeInterval = 30 * 60,
        reminderHoldDuration: ClosedRange<TimeInterval> = 5.0...7.0,
        dragSpeedMultiplier: CGFloat = 0.45
    ) {
        self.speed = speed
        self.stepDistance = stepDistance
        self.muddyStepCount = muddyStepCount
        self.idleDuration = idleDuration
        self.memePauseDuration = memePauseDuration
        self.offscreenDuration = offscreenDuration
        self.walksBeforeExit = walksBeforeExit
        self.honkChance = honkChance
        self.memeChance = memeChance
        self.margin = margin
        self.muddyReturnChance = muddyReturnChance
        self.returnHonkChance = returnHonkChance
        self.dashChance = dashChance
        self.dashSpeedMultiplier = dashSpeedMultiplier
        self.ponderChance = ponderChance
        self.ponderDuration = ponderDuration
        self.waterInterval = waterInterval
        self.moveInterval = moveInterval
        self.reminderHoldDuration = reminderHoldDuration
        self.dragSpeedMultiplier = dragSpeedMultiplier
    }
}
