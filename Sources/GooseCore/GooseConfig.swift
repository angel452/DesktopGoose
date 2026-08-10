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
    /// Probability of dropping a meme at the end of a walk.
    public var memeChance: Double
    /// Keeps walk targets away from the very edge of the screen.
    public var margin: CGFloat

    public init(
        speed: CGFloat = 150,
        stepDistance: CGFloat = 36,
        muddyStepCount: Int = 24,
        idleDuration: ClosedRange<TimeInterval> = 0.5...2.5,
        memePauseDuration: ClosedRange<TimeInterval> = 4.0...6.0,
        offscreenDuration: ClosedRange<TimeInterval> = 2.0...5.0,
        walksBeforeExit: ClosedRange<Int> = 3...6,
        honkChance: Double = 0.25,
        memeChance: Double = 0.2,
        margin: CGFloat = 60
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
    }
}
