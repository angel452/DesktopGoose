import CoreGraphics
import Foundation

/// Describes a sprite sheet sitting next to its image file.
///
/// Every measurement is in **pixels** of the image; `scale` converts them to
/// screen points, so a sheet baked at 2x draws at the right size on a Retina
/// display without changing any code.
public struct SpriteSheetManifest: Equatable, Sendable, Codable {
    /// File name of the image, relative to the manifest.
    public var image: String
    public var frameWidth: Int
    public var frameHeight: Int
    /// Frames per row, filled left to right, top to bottom.
    public var columns: Int
    /// Pixels per point. 2 for a sheet baked at Retina resolution.
    public var scale: Double
    /// Where the goose's feet sit inside a frame, measured from the bottom-left.
    public var anchorX: Double
    public var anchorY: Double
    /// Pixel art must not be smoothed when scaled. Hand-drawn or vector art should be.
    public var pixelArt: Bool
    public var clips: [AnimationClip]

    public init(
        image: String,
        frameWidth: Int,
        frameHeight: Int,
        columns: Int,
        scale: Double = 1,
        anchorX: Double,
        anchorY: Double,
        pixelArt: Bool = false,
        clips: [AnimationClip]
    ) {
        self.image = image
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.columns = columns
        self.scale = scale
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.pixelArt = pixelArt
        self.clips = clips
    }

    /// Hand-edited JSON should not have to spell out every field.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        image = try container.decodeIfPresent(String.self, forKey: .image) ?? "goose.png"
        frameWidth = try container.decode(Int.self, forKey: .frameWidth)
        frameHeight = try container.decode(Int.self, forKey: .frameHeight)
        columns = try container.decodeIfPresent(Int.self, forKey: .columns) ?? 1
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        anchorX = try container.decodeIfPresent(Double.self, forKey: .anchorX) ?? Double(frameWidth) / 2
        anchorY = try container.decodeIfPresent(Double.self, forKey: .anchorY) ?? 0
        pixelArt = try container.decodeIfPresent(Bool.self, forKey: .pixelArt) ?? false
        clips = try container.decode([AnimationClip].self, forKey: .clips)
    }

    /// Frame size in screen points.
    public var frameSize: CGSize {
        let divisor = scale > 0 ? scale : 1
        return CGSize(width: Double(frameWidth) / divisor, height: Double(frameHeight) / divisor)
    }

    /// Anchor in screen points.
    public var anchor: CGPoint {
        let divisor = scale > 0 ? scale : 1
        return CGPoint(x: anchorX / divisor, y: anchorY / divisor)
    }

    public func clip(named name: String) -> AnimationClip? {
        clips.first { $0.name == name }
    }
}
