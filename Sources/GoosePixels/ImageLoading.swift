import CStbImage
import Foundation
import GooseCore

/// Turns image files into `PixelImage`s without any platform image framework.
public enum ImageDecoder {
    /// File extensions the decoder understands. GIFs load their first frame.
    public static let extensions = ["png", "jpg", "jpeg", "bmp", "gif"]

    public static func decode(_ bytes: [UInt8]) -> PixelImage? {
        guard !bytes.isEmpty, bytes.count <= Int(Int32.max) else { return nil }
        var width: Int32 = 0
        var height: Int32 = 0
        guard let decoded = goose_image_decode_rgba(bytes, Int32(bytes.count), &width, &height) else {
            return nil
        }
        defer { goose_image_free(decoded) }

        let count = Int(width) * Int(height) * 4
        let rgba = Array(UnsafeBufferPointer(start: decoded, count: count))
        return PixelImage(width: Int(width), height: Int(height), rgba: rgba)
    }

    public static func load(_ url: URL) -> PixelImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode([UInt8](data))
    }
}

/// A baked sprite sheet, decoded and sliced, ready to blit.
public struct SpriteSheet: Sendable {
    public static let manifestName = "goose.json"

    public let manifest: SpriteSheetManifest
    public let frames: [PixelImage]

    /// Returns `nil` when the folder holds no usable sheet.
    public init?(directory: URL) {
        let manifestURL = directory.appendingPathComponent(Self.manifestName)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(SpriteSheetManifest.self, from: data),
              manifest.frameWidth > 0, manifest.frameHeight > 0, !manifest.clips.isEmpty,
              let sheet = ImageDecoder.load(directory.appendingPathComponent(manifest.image)),
              case let frames = SpriteFrames.slice(sheet, manifest: manifest),
              !frames.isEmpty
        else { return nil }

        self.manifest = manifest
        self.frames = frames
    }

    public func frame(_ index: Int) -> PixelImage {
        frames.indices.contains(index) ? frames[index] : frames[0]
    }

    /// Falls back to idle, then to any frame, so a missing clip degrades instead of
    /// drawing nothing — the same rule the Mac artwork follows.
    public func clipOrFallback(named name: String) -> AnimationClip {
        manifest.clip(named: name)
            ?? manifest.clip(named: GooseClip.idle)
            ?? AnimationClip(name: name, frames: [0], framesPerSecond: 0)
    }
}
