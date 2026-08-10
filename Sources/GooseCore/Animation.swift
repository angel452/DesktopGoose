import Foundation

/// One named animation: which frames to show, how fast, and whether it repeats.
///
/// Frames are indices into a sprite sheet, so a clip carries no images and stays
/// in the pure layer.
public struct AnimationClip: Equatable, Sendable, Codable {
    public let name: String
    public let frames: [Int]
    public let framesPerSecond: Double
    public let loops: Bool

    public init(name: String, frames: [Int], framesPerSecond: Double, loops: Bool = true) {
        self.name = name
        self.frames = frames
        self.framesPerSecond = framesPerSecond
        self.loops = loops
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        frames = try container.decode([Int].self, forKey: .frames)
        framesPerSecond = try container.decodeIfPresent(Double.self, forKey: .framesPerSecond) ?? 12
        loops = try container.decodeIfPresent(Bool.self, forKey: .loops) ?? true
    }

    /// How long one full pass through the clip takes. Zero when it cannot advance.
    public var duration: TimeInterval {
        guard framesPerSecond > 0, !frames.isEmpty else { return 0 }
        return Double(frames.count) / framesPerSecond
    }
}

/// Advances a clip over time and reports which frame to draw.
///
/// It holds no images and no timer — the render loop feeds it `deltaTime`, exactly
/// like `GooseBrain`.
public struct AnimationPlayer: Sendable {
    public private(set) var clip: AnimationClip
    private var elapsed: TimeInterval = 0

    public init(clip: AnimationClip) {
        self.clip = clip
    }

    /// Switches to another clip and restarts it. Re-playing the clip that is
    /// already running is a no-op, so calling this every frame is safe.
    public mutating func play(_ clip: AnimationClip) {
        guard clip.name != self.clip.name else { return }
        self.clip = clip
        elapsed = 0
    }

    public mutating func advance(by deltaTime: TimeInterval) {
        guard deltaTime > 0 else { return }
        elapsed += deltaTime

        // Wrapping keeps `elapsed` small no matter how long the app runs.
        let duration = clip.duration
        if clip.loops, duration > 0 {
            elapsed = elapsed.truncatingRemainder(dividingBy: duration)
        }
    }

    /// The sprite sheet frame index to draw right now.
    public var frame: Int {
        guard let first = clip.frames.first else { return 0 }
        guard clip.framesPerSecond > 0 else { return first }

        let position = Int(elapsed * clip.framesPerSecond)
        guard clip.loops else { return clip.frames[min(position, clip.frames.count - 1)] }
        return clip.frames[position % clip.frames.count]
    }

    /// True once a non-looping clip has shown its last frame.
    public var isFinished: Bool {
        guard !clip.loops, clip.duration > 0 else { return false }
        return elapsed >= clip.duration
    }
}
