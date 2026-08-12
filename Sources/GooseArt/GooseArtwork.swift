import AppKit
import GooseCore

/// Everything the overlay needs in order to draw a goose, regardless of whether
/// the pixels come from a sprite sheet or are generated on the spot.
///
/// This is the seam that lets real artwork replace the placeholder without the
/// app knowing anything changed.
public protocol GooseArtwork {
    /// Size of one frame. Screen points for artwork drawn live, native pixels for
    /// artwork that exists to be baked.
    var frameSize: CGSize { get }
    /// Where the feet sit inside a frame, measured from its bottom-left corner.
    var anchor: CGPoint { get }
    /// How many distinct frames exist, across every clip.
    var frameCount: Int { get }

    /// Whether this artwork lives on a hard pixel grid. Anything drawn alongside
    /// the goose — footprints, above all — has to match, or crisp and smooth end
    /// up on screen together and both look wrong.
    var isPixelArt: Bool { get }
    /// How many screen points one artwork pixel covers. 1 when not pixel art.
    var pixelSize: CGFloat { get }

    func clip(named name: String) -> AnimationClip?
    func draw(frame: Int, at point: CGPoint, facingLeft: Bool)
}

public extension GooseArtwork {
    var isPixelArt: Bool { false }
    var pixelSize: CGFloat { 1 }
}

public extension GooseArtwork {
    /// Falls back to the idle clip, then to any clip at all, so a sheet missing an
    /// animation degrades instead of drawing nothing.
    func clipOrFallback(named name: String) -> AnimationClip {
        clip(named: name)
            ?? clip(named: GooseClip.idle)
            ?? AnimationClip(name: name, frames: [0], framesPerSecond: 0)
    }
}

/// Clip names the app asks for. A sheet is free to provide more.
public enum GooseClip {
    public static let idle = "idle"
    public static let walk = "walk"

    /// Maps what the goose is doing to the animation that shows it.
    public static func name(for state: GooseState) -> String {
        switch state {
        case .idle, .offscreen, .presenting: return idle
        case .walking, .leaving, .returning, .deliveringExit, .deliveringEntry: return walk
        }
    }
}
