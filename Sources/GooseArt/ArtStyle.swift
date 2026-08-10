import AppKit

/// The medium everything drawn around the goose has to share.
///
/// Footprints, speech bubbles — anything rendered live rather than blitted from
/// the sheet needs to know whether it is living on a pixel grid, and how big one
/// of those pixels is in screen points. Mixing crisp and smooth on one screen
/// reads as a bug, whichever way round it happens.
public struct ArtStyle {
    public let isPixelArt: Bool
    /// How many screen points one artwork pixel covers.
    public let pixelSize: CGFloat

    public init(artwork: any GooseArtwork) {
        isPixelArt = artwork.isPixelArt
        pixelSize = artwork.pixelSize
    }

    /// A whole number of artwork pixels, expressed in points. Falls back to plain
    /// points for smooth art, so callers can size everything in these units and
    /// stay correct in both styles.
    public func pixels(_ count: CGFloat) -> CGFloat {
        isPixelArt ? count * pixelSize : count
    }

    /// Rounds a coordinate onto the pixel grid. Without this, things drawn live
    /// land on their own sub-pixel offsets and look ragged next to the sprite.
    public func snap(_ value: CGFloat) -> CGFloat {
        guard isPixelArt, pixelSize > 0 else { return value }
        return (value / pixelSize).rounded() * pixelSize
    }
}
