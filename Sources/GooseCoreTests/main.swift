import CoreGraphics
import Foundation
import GooseCore

// MARK: - Fixtures

let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

func makeBrain(seed: UInt64 = 42, config: GooseConfig = GooseConfig()) -> GooseBrain<SeededRandom> {
    GooseBrain(bounds: screen, config: config, rng: SeededRandom(seed: seed))
}

@discardableResult
func run(
    _ brain: inout GooseBrain<SeededRandom>,
    seconds: TimeInterval,
    onStep: ((GooseBrain<SeededRandom>) -> Void)? = nil
) -> [GooseEvent] {
    let step = 1.0 / 60.0
    var events: [GooseEvent] = []
    var elapsed: TimeInterval = 0

    while elapsed < seconds {
        events.append(contentsOf: brain.update(deltaTime: step))
        onStep?(brain)
        elapsed += step
    }
    return events
}

/// Same as `run`, but keeps the clock alongside each event so tests can assert on
/// how long the goose waited, not just what it did.
func runTimed(_ brain: inout GooseBrain<SeededRandom>, seconds: TimeInterval) -> [(time: TimeInterval, event: GooseEvent)] {
    let step = 1.0 / 60.0
    var timeline: [(time: TimeInterval, event: GooseEvent)] = []
    var elapsed: TimeInterval = 0

    while elapsed < seconds {
        for event in brain.update(deltaTime: step) {
            timeline.append((elapsed, event))
        }
        elapsed += step
    }
    return timeline
}

func footprints(in events: [GooseEvent]) -> [(position: CGPoint, muddy: Bool)] {
    events.compactMap {
        if case let .footprint(position, muddy) = $0 { return (position, muddy) }
        return nil
    }
}

/// A goose that never wanders off screen, so walking can be tested in isolation.
let neverLeaves = GooseConfig(walksBeforeExit: 10_000...10_000)

// MARK: - Suite

let t = TestRunner()
print("GooseCore")

t.test("starts idle and eventually walks") {
    var brain = makeBrain(config: neverLeaves)
    t.expectEqual(brain.state, .idle, "initial state")

    let events = run(&brain, seconds: 10)
    t.expect(!footprints(in: events).isEmpty, "expected footprints within 10 seconds")
}

t.test("footprints are never further apart than one stride") {
    let config = GooseConfig(stepDistance: 36, walksBeforeExit: 10_000...10_000)
    var brain = makeBrain(config: config)
    let positions = footprints(in: run(&brain, seconds: 20)).map(\.position)

    t.expect(positions.count > 5, "need several footprints to measure spacing, got \(positions.count)")
    for (a, b) in zip(positions, positions.dropFirst()) {
        let gap = hypot(b.x - a.x, b.y - a.y)
        t.expect(gap <= config.stepDistance + 1, "stride of \(gap) exceeds \(config.stepDistance)")
    }
}

t.test("a walking goose stays on screen") {
    var brain = makeBrain(config: neverLeaves)
    let tolerated = screen.insetBy(dx: -1, dy: -1)

    run(&brain, seconds: 30) { brain in
        guard brain.state == .walking else { return }
        t.expect(tolerated.contains(brain.position), "walked off screen to \(brain.position)")
    }
}

t.test("a goose that never left tracks no mud") {
    var brain = makeBrain(config: neverLeaves)
    let prints = footprints(in: run(&brain, seconds: 30))

    t.expect(!prints.isEmpty, "expected footprints")
    t.expect(prints.allSatisfy { !$0.muddy }, "clean feet should stay clean")
}

t.test("comes back muddy after going off screen") {
    let config = GooseConfig(muddyStepCount: 10, walksBeforeExit: 1...1, muddyReturnChance: 1)
    var brain = makeBrain(config: config)
    let events = run(&brain, seconds: 60)

    guard let returned = events.firstIndex(of: .visibilityChanged(isVisible: true)) else {
        return t.fail("the goose never came back")
    }

    let afterReturn = footprints(in: Array(events[(returned + 1)...]))
    t.expect(afterReturn.count >= config.muddyStepCount, "expected at least \(config.muddyStepCount) prints after returning")
    t.expect(afterReturn.prefix(config.muddyStepCount).allSatisfy(\.muddy),
             "the first \(config.muddyStepCount) prints after returning should be muddy")
}

t.test("mud wears off after the configured number of steps") {
    let config = GooseConfig(muddyStepCount: 10, walksBeforeExit: 1...1, muddyReturnChance: 1)
    var brain = makeBrain(config: config)
    let events = run(&brain, seconds: 60)

    guard let returned = events.firstIndex(of: .visibilityChanged(isVisible: true)) else {
        return t.fail("the goose never came back")
    }

    // Only this visit counts; a later trip outside would refill the mud.
    let rest = Array(events[(returned + 1)...])
    let nextExit = rest.firstIndex(of: .visibilityChanged(isVisible: false)) ?? rest.endIndex
    let visit = footprints(in: Array(rest[..<nextExit]))

    t.expectEqual(visit.filter(\.muddy).count, config.muddyStepCount, "muddy prints in one visit")
    t.expect(!(visit.last?.muddy ?? true), "mud should run out before the visit ends")
}

t.test("visibility alternates: out, then back") {
    var brain = makeBrain(config: GooseConfig(walksBeforeExit: 1...1))
    let events = run(&brain, seconds: 60)

    let visibility = events.compactMap { event -> Bool? in
        if case let .visibilityChanged(isVisible) = event { return isVisible }
        return nil
    }

    t.expect(visibility.count >= 2, "expected a full trip out and back, got \(visibility.count) changes")
    t.expectEqual(visibility.first ?? true, false, "first visibility change")
    for (a, b) in zip(visibility, visibility.dropFirst()) {
        t.expect(a != b, "visibility events must alternate")
    }
}

// MARK: - Idling

t.test("the goose reports when it sets off again") {
    var brain = makeBrain(config: neverLeaves)
    let events = run(&brain, seconds: 20)

    t.expect(events.contains(.startedMoving), "expected at least one startedMoving")
}

/// Measures the longest unbroken stretch the goose spends standing still.
///
/// The gap between two departures is no good for this: it contains a whole walk,
/// which can take ten seconds to cross the screen.
func longestIdle(_ brain: inout GooseBrain<SeededRandom>, seconds: TimeInterval) -> TimeInterval {
    let step = 1.0 / 60.0
    var current: TimeInterval = 0
    var longest: TimeInterval = 0
    var elapsed: TimeInterval = 0

    while elapsed < seconds {
        _ = brain.update(deltaTime: step)
        current = brain.state == .idle ? current + step : 0
        longest = max(longest, current)
        elapsed += step
    }
    return longest
}

t.test("an ordinary idle stays short") {
    let config = GooseConfig(
        idleDuration: 0.5...0.5,
        walksBeforeExit: 10_000...10_000,
        ponderChance: 0
    )
    var brain = makeBrain(config: config)
    let idle = longestIdle(&brain, seconds: 30)

    t.expect(idle > 0, "the goose never stood still at all")
    t.expect(idle < 1, "a 0.5s idle stretched to \(idle)s")
}

// MARK: - Variety

t.test("a dash covers more ground than a stroll") {
    // Identical seed and config but for the dash: the dash roll is always spent,
    // so both geese draw the same targets and only the pace differs.
    let stroll = GooseConfig(
        idleDuration: 0.4...0.4,
        walksBeforeExit: 10_000...10_000,
        dashChance: 0,
        ponderChance: 0
    )
    let sprint = GooseConfig(
        idleDuration: 0.4...0.4,
        walksBeforeExit: 10_000...10_000,
        dashChance: 1,
        ponderChance: 0
    )
    var slow = makeBrain(seed: 5, config: stroll)
    var fast = makeBrain(seed: 5, config: sprint)

    let slowPrints = footprints(in: run(&slow, seconds: 20)).count
    let fastPrints = footprints(in: run(&fast, seconds: 20)).count
    t.expect(fastPrints > slowPrints, "dashing (\(fastPrints)) should out-cover strolling (\(slowPrints))")
}

t.test("a clean return leaves no mud") {
    let config = GooseConfig(walksBeforeExit: 1...1, muddyReturnChance: 0)
    var brain = makeBrain(config: config)
    let prints = footprints(in: run(&brain, seconds: 60))

    t.expect(!prints.isEmpty, "expected footprints from walking")
    t.expect(prints.allSatisfy { !$0.muddy }, "a clean return should track no mud")
}

t.test("a return honk fires when it is certain") {
    let config = GooseConfig(walksBeforeExit: 1...1, honkChance: 0, returnHonkChance: 1)
    var brain = makeBrain(config: config)
    let events = run(&brain, seconds: 30)

    t.expect(events.contains(.visibilityChanged(isVisible: true)), "the goose should have returned")
    t.expect(events.contains(.honk), "a certain return honk should sound")
}

t.test("a silent return stays silent") {
    let config = GooseConfig(walksBeforeExit: 1...1, honkChance: 0, returnHonkChance: 0)
    var brain = makeBrain(config: config)
    let events = run(&brain, seconds: 30)

    t.expect(events.contains(.visibilityChanged(isVisible: true)), "the goose should have returned")
    t.expect(!events.contains(.honk), "no honk should sound when every honk chance is zero")
}

t.test("a ponder stands still far longer than an ordinary idle") {
    let config = GooseConfig(
        idleDuration: 0.5...0.5,
        walksBeforeExit: 10_000...10_000,
        honkChance: 0,
        ponderChance: 1,
        ponderDuration: 4...4
    )
    var brain = makeBrain(config: config)
    let idle = longestIdle(&brain, seconds: 40)

    t.expect(idle >= 4, "a ponder should reach its full length, longest stop was \(idle)s")
}

// MARK: - Reminders

func reminders(in timeline: [(time: TimeInterval, event: GooseEvent)]) -> [(time: TimeInterval, position: CGPoint)] {
    timeline.compactMap {
        if case let .showReminder(position) = $0.event { return ($0.time, position) }
        return nil
    }
}

t.test("a due reminder is delivered at the centre") {
    // The single reminder clock is due in 2s.
    let config = GooseConfig(walksBeforeExit: 10_000...10_000, reminderInterval: 2)
    var brain = makeBrain(config: config)
    let timeline = runTimed(&brain, seconds: 30)

    guard let first = reminders(in: timeline).first else {
        return t.fail("no reminder was ever delivered")
    }
    t.expect(abs(first.position.x - screen.midX) < 1, "reminder should sit at centre x, got \(first.position.x)")
    t.expect(abs(first.position.y - screen.midY) < 1, "reminder should sit at centre y, got \(first.position.y)")
}

t.test("the goose stands with the reminder, then moves on") {
    let hold: TimeInterval = 4
    let config = GooseConfig(
        walksBeforeExit: 10_000...10_000,
        reminderInterval: 2,
        reminderHoldDuration: hold...hold
    )
    var brain = makeBrain(config: config)
    let timeline = runTimed(&brain, seconds: 40)

    guard let shown = timeline.firstIndex(where: {
        if case .showReminder = $0.event { return true }
        return false
    }) else {
        return t.fail("no reminder was shown")
    }
    guard let resumed = timeline[(shown + 1)...].first(where: { $0.event == .startedMoving }) else {
        return t.fail("the goose never went back to wandering")
    }

    let waited = resumed.time - timeline[shown].time
    t.expect(waited >= hold - 1.0 / 60.0, "expected a \(hold)s hold, waited \(waited)s")
}

t.test("a reminder can be requested on demand") {
    // The clock is parked far out, so the only reminder that can appear is the
    // one requested by hand.
    let config = GooseConfig(walksBeforeExit: 10_000...10_000, reminderInterval: 10_000)
    var brain = makeBrain(config: config)

    _ = brain.update(deltaTime: 0.1)
    brain.requestReminder()
    let timeline = runTimed(&brain, seconds: 30)

    guard let first = reminders(in: timeline).first else {
        return t.fail("the requested reminder was never delivered")
    }
    t.expect(abs(first.position.x - screen.midX) < 1, "requested reminder should sit at centre x, got \(first.position.x)")
}

t.test("the goose faces backward while dragging a reminder in") {
    let config = GooseConfig(walksBeforeExit: 10_000...10_000, reminderInterval: 2)
    var brain = makeBrain(config: config)

    var sawEntry = false
    var sawBackward = false
    run(&brain, seconds: 30) { brain in
        guard brain.state == .deliveringEntry else { return }
        sawEntry = true
        // Moving toward the centre; dx > 0 means moving right. Facing left while
        // moving right (and vice versa) is the backward drag.
        let dx = screen.midX - brain.position.x
        if abs(dx) > 2, brain.facingLeft == (dx > 0) { sawBackward = true }
    }

    t.expect(sawEntry, "the goose never entered the dragging state")
    t.expect(sawBackward, "the goose never faced backward while dragging")
}

// MARK: - Cursor

func pecked(in events: [GooseEvent]) -> Bool {
    events.contains {
        if case .pecked = $0 { return true }
        return false
    }
}

func gaveUp(in events: [GooseEvent]) -> Bool {
    events.contains {
        if case .gaveUpChase = $0 { return true }
        return false
    }
}

t.test("a cursor in the goose's space gets pecked") {
    var brain = makeBrain(config: neverLeaves)
    _ = brain.update(deltaTime: 0.1)

    brain.aimCursor(at: brain.position) // cursor sitting right on the goose
    let events = run(&brain, seconds: 3)

    t.expect(pecked(in: events), "a cursor on the goose should get pecked")
}

t.test("a distant cursor is left alone") {
    var brain = makeBrain(config: neverLeaves)
    brain.aimCursor(at: CGPoint(x: -500, y: -500)) // far off any wander path
    let events = run(&brain, seconds: 5)

    t.expect(!pecked(in: events), "the goose should ignore a cursor far from its space")
}

t.test("a motionless cursor is pecked once, not in a loop") {
    // A huge react radius keeps the cursor "in range" forever, so the goose can
    // only re-arm if it leaves — which it never does. The old cooldown-only guard
    // re-pecked on a loop here.
    let config = GooseConfig(walksBeforeExit: 10_000...10_000, cursorReactRadius: 2000, cursorCooldown: 1)
    var brain = makeBrain(config: config)
    _ = brain.update(deltaTime: 0.1)
    brain.aimCursor(at: brain.position)

    var pecks = 0
    var elapsed: TimeInterval = 0
    let step = 1.0 / 60.0
    while elapsed < 6 {
        for event in brain.update(deltaTime: step) {
            if case .pecked = event { pecks += 1 }
        }
        elapsed += step
    }

    t.expectEqual(pecks, 1, "a still cursor should be pecked once, not in a loop")
}

t.test("a cursor on another screen is ignored") {
    var brain = makeBrain(config: neverLeaves)
    _ = brain.update(deltaTime: 0.1)
    // Mapped just past the right edge, as a neighbouring monitor would be.
    brain.aimCursor(at: CGPoint(x: screen.maxX + 40, y: brain.position.y))

    let tolerated = screen.insetBy(dx: -1, dy: -1)
    let events = run(&brain, seconds: 3) { brain in
        t.expect(tolerated.contains(brain.position), "goose left its screen chasing an off-screen cursor: \(brain.position)")
    }

    t.expect(!pecked(in: events), "an off-screen cursor should not be pecked")
}

t.test("the goose glares before it charges") {
    // A committed telegraph: the goose locks on and holds an angry stare for
    // roughly `cursorStareDuration` before it ever moves, giving the human a beat.
    let stare: TimeInterval = 1.0
    let config = GooseConfig(walksBeforeExit: 10_000...10_000, cursorReactRadius: 2000, cursorStareDuration: stare)
    var brain = makeBrain(config: config)
    _ = brain.update(deltaTime: 0.1)
    brain.aimCursor(at: CGPoint(x: brain.position.x + 60, y: brain.position.y))

    _ = brain.update(deltaTime: 1.0 / 60.0)
    t.expectEqual(brain.state, GooseState.alerting, "it should glare first, not charge instantly")

    var elapsed: TimeInterval = 0
    let step = 1.0 / 60.0
    while elapsed < stare + 0.5, brain.state == .alerting {
        _ = brain.update(deltaTime: step)
        elapsed += step
    }
    t.expect(elapsed >= stare - 2 * step, "it should hold the stare ~\(stare)s, held \(elapsed)s")
    t.expect(brain.state != .alerting, "the stare should end in a charge, not linger")
}

t.test("the goose gives up when the cursor slips away") {
    let config = GooseConfig(walksBeforeExit: 10_000...10_000, peckRadius: 8, chargeDuration: 0.4)
    var brain = makeBrain(config: config)
    _ = brain.update(deltaTime: 0.1)

    // Provoke it with a cursor beside the goose, then wait out the stare so it
    // commits to the charge.
    brain.aimCursor(at: CGPoint(x: brain.position.x + 30, y: brain.position.y))
    var elapsed: TimeInterval = 0
    let step = 1.0 / 60.0
    while elapsed < 2, brain.state != .charging {
        _ = brain.update(deltaTime: step)
        elapsed += step
    }
    let charged = brain.state == .charging

    // Then the cursor vanishes — nothing left to catch.
    brain.aimCursor(at: nil)
    var caught = false
    var relented = false
    var chaseElapsed: TimeInterval = 0
    while chaseElapsed < 2 {
        let events = brain.update(deltaTime: step)
        if pecked(in: events) { caught = true }
        if gaveUp(in: events) { relented = true }
        chaseElapsed += step
    }

    t.expect(charged, "the goose should charge a cursor beside it after the stare")
    t.expect(!caught, "it should not peck a cursor that vanished")
    t.expect(relented, "it should emit a gave-up taunt when the chase fizzles")
    t.expect(brain.state != .charging, "it should give up rather than charge forever")
}

t.test("a catch does not dismiss its own taunt") {
    // `.pecked` opens a taunt bubble; a `.startedMoving` in the same frame would
    // close it instantly. The frame that catches the cursor must not emit both.
    let config = GooseConfig(walksBeforeExit: 10_000...10_000, cursorReactRadius: 2000, peckRadius: 40)
    var brain = makeBrain(config: config)
    _ = brain.update(deltaTime: 0.1)
    brain.aimCursor(at: brain.position) // sitting on the goose → a guaranteed catch

    var foundPeck = false
    var peckFrameAlsoMoved = false
    var elapsed: TimeInterval = 0
    let step = 1.0 / 60.0
    while elapsed < 5, !foundPeck {
        let events = brain.update(deltaTime: step)
        if pecked(in: events) {
            foundPeck = true
            peckFrameAlsoMoved = events.contains(.startedMoving)
        }
        elapsed += step
    }

    t.expect(foundPeck, "the goose should peck a cursor sitting on it")
    t.expect(!peckFrameAlsoMoved, "the peck frame must not also emit startedMoving, or the taunt dies instantly")
}

// MARK: - Determinism

t.test("the same seed replays the same goose") {
    var first = makeBrain(seed: 7)
    var second = makeBrain(seed: 7)

    t.expect(run(&first, seconds: 45) == run(&second, seconds: 45), "identical seeds diverged")
}

t.test("different seeds produce different geese") {
    var first = makeBrain(seed: 7)
    var second = makeBrain(seed: 8)

    t.expect(run(&first, seconds: 45) != run(&second, seconds: 45), "different seeds produced identical runs")
}

// MARK: - Animation

let walkClip = AnimationClip(name: "walk", frames: [0, 1, 2, 3], framesPerSecond: 10)
let blinkClip = AnimationClip(name: "blink", frames: [8, 9], framesPerSecond: 10, loops: false)

t.test("a clip advances one frame per tick") {
    var player = AnimationPlayer(clip: walkClip)
    t.expectEqual(player.frame, 0, "first frame")

    player.advance(by: 0.1)
    t.expectEqual(player.frame, 1, "after one frame duration")

    player.advance(by: 0.2)
    t.expectEqual(player.frame, 3, "after three frame durations")
}

t.test("a looping clip wraps around") {
    var player = AnimationPlayer(clip: walkClip)
    player.advance(by: 0.4) // exactly one full cycle

    t.expectEqual(player.frame, 0, "wrapped frame")
    t.expect(!player.isFinished, "a looping clip never finishes")
}

t.test("a non-looping clip holds its last frame") {
    var player = AnimationPlayer(clip: blinkClip)
    player.advance(by: 5)

    t.expectEqual(player.frame, 9, "held frame")
    t.expect(player.isFinished, "expected the clip to report finished")
}

t.test("switching clips restarts the animation") {
    var player = AnimationPlayer(clip: walkClip)
    player.advance(by: 0.2)
    t.expectEqual(player.frame, 2, "mid-walk frame")

    player.play(blinkClip)
    t.expectEqual(player.frame, 8, "first frame of the new clip")
}

t.test("re-playing the running clip does not restart it") {
    var player = AnimationPlayer(clip: walkClip)
    player.advance(by: 0.2)
    player.play(walkClip)

    t.expectEqual(player.frame, 2, "frame after a redundant play()")
}

t.test("a clip with no frame rate stays on its first frame") {
    var player = AnimationPlayer(clip: AnimationClip(name: "still", frames: [5], framesPerSecond: 0))
    player.advance(by: 10)

    t.expectEqual(player.frame, 5, "static frame")
}

// MARK: - Sprite sheet manifest

t.test("a manifest fills in the fields it omits") {
    let json = #"{"frameWidth": 48, "frameHeight": 64, "clips": [{"name": "walk", "frames": [0, 1]}]}"#

    guard let manifest = try? JSONDecoder().decode(SpriteSheetManifest.self, from: Data(json.utf8)) else {
        return t.fail("a minimal hand-written manifest should decode")
    }

    t.expectEqual(manifest.image, "goose.png", "default image name")
    t.expectEqual(manifest.scale, 1, "default scale")
    t.expectEqual(manifest.columns, 1, "default columns")
    t.expectEqual(manifest.anchorX, 24, "anchor defaults to the frame's horizontal centre")
    t.expectEqual(manifest.clips.first?.framesPerSecond ?? 0, 12, "default frame rate")
    t.expect(!manifest.pixelArt, "smoothing should be on unless the sheet says pixel art")
}

t.test("a manifest converts pixels to points using its scale") {
    let manifest = SpriteSheetManifest(
        image: "goose.png",
        frameWidth: 240,
        frameHeight: 232,
        columns: 6,
        scale: 2,
        anchorX: 104,
        anchorY: 10,
        clips: [walkClip]
    )

    t.expectEqual(manifest.frameSize.width, 120, "frame width in points")
    t.expectEqual(manifest.anchor.x, 52, "anchor x in points")
}

t.finish()
