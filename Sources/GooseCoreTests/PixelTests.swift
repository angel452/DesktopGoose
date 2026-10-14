import GooseCore
import GoosePixels

/// The Windows drawing and layout rules, checked on every platform.
func runPixelTests(_ t: TestRunner) {
    let red = PixelColor(red: 255, green: 0, blue: 0)
    let opaqueRed: UInt32 = 0xFFFF_0000

    // MARK: Canvas

    t.test("a colour packs premultiplied in BGRA order") {
        t.expectEqual(red.premultiplied, opaqueRed, "opaque red")
        let halfWhite = PixelColor(red: 255, green: 255, blue: 255, alpha: 128)
        t.expectEqual(halfWhite.premultiplied, 0x8080_8080, "half-transparent white")
    }

    t.test("a fill paints inside its rectangle and is clipped to the canvas") {
        var canvas = PixelCanvas(width: 4, height: 4)
        canvas.fill(PixelRect(x: 2, y: 2, width: 10, height: 10), color: red)
        t.expectEqual(canvas.pixel(x: 3, y: 3), opaqueRed, "inside")
        t.expectEqual(canvas.pixel(x: 1, y: 1), 0, "outside")
        t.expectEqual(canvas.pixels.count, 16, "canvas size unchanged")
    }

    t.test("a translucent fill blends over what is underneath") {
        var canvas = PixelCanvas(width: 1, height: 1)
        canvas.fill(PixelRect(x: 0, y: 0, width: 1, height: 1), color: .white)
        canvas.fill(PixelRect(x: 0, y: 0, width: 1, height: 1), color: PixelColor(red: 0, green: 0, blue: 0, alpha: 128))
        let pixel = canvas.pixel(x: 0, y: 0)
        t.expectEqual(pixel >> 24, 255, "stays opaque")
        t.expect((pixel & 0xFF) > 100 && (pixel & 0xFF) < 140, "half grey, got \(pixel & 0xFF)")
    }

    t.test("a blit scales each source pixel into a block and can mirror") {
        // A 2×1 sprite: red on the left, transparent on the right.
        let sprite = PixelImage(width: 2, height: 1, pixels: [opaqueRed, 0])
        var canvas = PixelCanvas(width: 4, height: 2)
        canvas.blit(sprite, x: 0, y: 0, scale: 2)
        t.expectEqual(canvas.pixel(x: 1, y: 1), opaqueRed, "block covers 2×2")
        t.expectEqual(canvas.pixel(x: 2, y: 0), 0, "transparent pixels leave the canvas alone")

        var mirrored = PixelCanvas(width: 4, height: 2)
        mirrored.blit(sprite, x: 0, y: 0, scale: 2, mirrored: true)
        t.expectEqual(mirrored.pixel(x: 3, y: 0), opaqueRed, "mirrored red lands on the right")
        t.expectEqual(mirrored.pixel(x: 0, y: 0), 0, "mirrored left is empty")
    }

    t.test("decoded RGBA is premultiplied and malformed buffers are rejected") {
        let image = PixelImage(width: 1, height: 1, rgba: [255, 255, 255, 128])
        t.expectEqual(image?.pixel(x: 0, y: 0) ?? 0, 0x8080_8080, "premultiplied")
        t.expect(PixelImage(width: 2, height: 2, rgba: [0, 0, 0, 0]) == nil, "short buffer accepted")
    }

    // MARK: Sprites

    let sheetManifest = SpriteSheetManifest(
        image: "goose.png",
        frameWidth: 42,
        frameHeight: 38,
        columns: 5,
        scale: 2.0 / 3.0,
        anchorX: 18,
        anchorY: 2,
        pixelArt: true,
        clips: [AnimationClip(name: "idle", frames: [0], framesPerSecond: 1)]
    )

    t.test("a sheet slices into frames left to right, top to bottom") {
        var pixels = [UInt32](repeating: 0, count: 210 * 228)
        // Mark the top-left pixel of the second frame.
        pixels[42] = opaqueRed
        let sheet = PixelImage(width: 210, height: 228, pixels: pixels)
        let frames = SpriteFrames.slice(sheet, manifest: sheetManifest)
        t.expectEqual(frames.count, 30, "5 columns × 6 rows")
        t.expectEqual(frames[1].pixel(x: 0, y: 0), opaqueRed, "second frame starts one frame width in")
        t.expectEqual(frames[0].width, 42, "frame width")
    }

    t.test("art pixels round to whole screen pixels for the display scale") {
        t.expectEqual(PixelMetrics(manifest: sheetManifest, displayScale: 1).artPixel, 2, "100 %")
        t.expectEqual(PixelMetrics(manifest: sheetManifest, displayScale: 1.5).artPixel, 2, "150 %")
        t.expectEqual(PixelMetrics(manifest: sheetManifest, displayScale: 2).artPixel, 3, "200 %")
    }

    t.test("the goose window keeps the feet centred whichever way it faces") {
        let metrics = PixelMetrics(manifest: sheetManifest, displayScale: 1)
        t.expectEqual(metrics.halfWidth, 48, "larger side of 84 px around a 36 px anchor")
        t.expectEqual(metrics.feetInWindow.x, 48, "feet x")
        t.expectEqual(metrics.feetInWindow.y, 72, "feet y, measured down")
        t.expectEqual(metrics.frameOrigin(facingLeft: false).x, 12, "right-facing frame")
        t.expectEqual(metrics.frameOrigin(facingLeft: true).x, 0, "left-facing frame")
        t.expectEqual(metrics.gooseHeight, 72, "head height above feet")
    }

    // MARK: Footprints

    t.test("a footprint stamps the webbed foot on the pixel grid") {
        let rects = FootprintStamp.rects(x: 101, y: 57, facingLeft: false, isLeftFoot: true, pixel: 2)
        t.expectEqual(rects.count, 34, "one rect per filled pattern cell")
        t.expect(rects.allSatisfy { $0.x % 2 == 0 && $0.y % 2 == 0 }, "every cell on the 2 px grid")
    }

    t.test("left prints sit higher and mirrored prints flip") {
        let left = FootprintStamp.rects(x: 100, y: 100, facingLeft: false, isLeftFoot: true, pixel: 2)
        let right = FootprintStamp.rects(x: 100, y: 100, facingLeft: false, isLeftFoot: false, pixel: 2)
        t.expect(left.map(\.y).min()! < right.map(\.y).min()!, "left foot should be higher on screen")

        let flipped = FootprintStamp.rects(x: 100, y: 100, facingLeft: true, isLeftFoot: true, pixel: 2)
        t.expect(left.map(\.x).max()! == flipped.map(\.x).max()!, "flip stays inside the same box")
        t.expect(left != flipped, "facing left should mirror the toes")
    }

    t.test("a trail alternates feet, ages out, and respects its limit") {
        var trail = FootprintTrail(limit: 2, lifetime: 10)
        trail.add(x: 0, y: 0, facingLeft: false, now: 0)
        trail.add(x: 1, y: 0, facingLeft: false, now: 1)
        t.expect(trail.prints[0].isLeftFoot != trail.prints[1].isLeftFoot, "feet should alternate")

        trail.add(x: 2, y: 0, facingLeft: false, now: 2)
        t.expectEqual(trail.prints.count, 2, "limit")
        t.expectEqual(trail.prints.first?.x ?? -1, 1, "oldest dropped first")

        t.expect(!trail.prune(now: 5), "nothing expired yet")
        t.expect(trail.prune(now: 11.5), "first print expired")
        t.expectEqual(trail.prints.count, 1, "one left")
    }

    // MARK: Bubble

    t.test("a bubble wraps its text with border, padding and tail") {
        let size = BubbleShape.size(contentWidth: 100, contentHeight: 20, pixel: 2)
        t.expectEqual(size.width, 120, "100 + 2 × 5 art pixels")
        t.expectEqual(size.height, 54, "20 + 2 × 5 + 7 art pixels")

        let below = BubbleShape.contentRect(width: 120, height: 54, tailSide: .bottom, pixel: 2)
        t.expectEqual(below, PixelRect(x: 10, y: 10, width: 100, height: 20), "tail below")
        let above = BubbleShape.contentRect(width: 120, height: 54, tailSide: .top, pixel: 2)
        t.expectEqual(above.y, 24, "tail on top pushes the text down")
    }

    t.test("a drawn bubble has ink edges, paper inside, cut corners and a tail") {
        let size = BubbleShape.size(contentWidth: 100, contentHeight: 20, pixel: 2)
        var canvas = PixelCanvas(width: size.width, height: size.height)
        BubbleShape.draw(on: &canvas, tailSide: .bottom, tailCenterX: 60, pixel: 2)

        let ink = BubbleShape.ink.premultiplied
        let paper = BubbleShape.paper.premultiplied
        t.expectEqual(canvas.pixel(x: 0, y: 0), 0, "corner is cut")
        t.expectEqual(canvas.pixel(x: 10, y: 0), ink, "top edge is ink")
        t.expectEqual(canvas.pixel(x: 60, y: 20), paper, "inside is paper")
        t.expect(canvas.pixel(x: 60, y: 42) != 0, "tail hangs under the body")
        t.expectEqual(canvas.pixel(x: 5, y: 45), 0, "nothing under the body away from the tail")
    }

    let workArea = PixelRect(x: 0, y: 0, width: 1920, height: 1040)

    t.test("a bubble speaks upwards when there is room") {
        let placement = BubblePlacement(
            width: 120, height: 54, feetX: 500, feetY: 600,
            gooseHeight: 72, gap: 6, pixel: 2, workArea: workArea
        )
        t.expectEqual(placement.tailSide, .bottom, "tail points down at the goose")
        t.expectEqual(placement.y, 600 - 72 - 6 - 54, "sits above the head")
        t.expectEqual(placement.x, 440, "centred on the feet")
        t.expectEqual(placement.tailCenterX, 60, "tail in the middle")
    }

    t.test("a bubble drops below the goose near the top and stays on screen") {
        let placement = BubblePlacement(
            width: 120, height: 54, feetX: 10, feetY: 80,
            gooseHeight: 72, gap: 6, pixel: 2, workArea: workArea
        )
        t.expectEqual(placement.tailSide, .top, "tail flips up")
        t.expectEqual(placement.y, 86, "below the feet")
        t.expectEqual(placement.x, 0, "clamped to the left edge")
        t.expectEqual(placement.tailCenterX, BubbleShape.tailRange(width: 120, pixel: 2).lowerBound, "tail clamped onto the body")
    }

    // MARK: Screen and memes

    let mapping = ScreenMapping(originX: 0, originY: 0, pixelWidth: 2880, pixelHeight: 1620, displayScale: 1.5)

    t.test("the brain's y-up points map onto y-down pixels and back") {
        t.expectEqual(mapping.logicalWidth, 1920, "logical width")
        let bottomLeft = mapping.toScreen(x: 0, y: 0)
        t.expectEqual(bottomLeft.y, 1620, "brain origin is the bottom of the screen")
        let screen = mapping.toScreen(x: 100, y: 200)
        t.expectEqual(screen.x, 150, "x scaled")
        t.expectEqual(screen.y, 1620 - 300, "y flipped and scaled")
        let back = mapping.toBrain(x: screen.x, y: screen.y)
        t.expectEqual(back.x, 100, "round trip x")
        t.expectEqual(back.y, 200, "round trip y")
    }

    t.test("memes shrink to fit but never grow") {
        let big = MemePlacement.fitted(width: 1200, height: 600, displayScale: 1)
        t.expectEqual(big.width, 300, "long edge capped")
        t.expectEqual(big.height, 150, "aspect kept")
        let small = MemePlacement.fitted(width: 100, height: 80, displayScale: 1)
        t.expectEqual(small.width, 100, "never enlarged")
    }

    t.test("a dragged meme sits on the goose's ground line, on the trailing side") {
        let right = MemePlacement.origin(
            feetX: 500, feetY: 700, onLeft: false, gooseHalfWidth: 48, gap: 12,
            windowWidth: 300, windowHeight: 200
        )
        t.expectEqual(right.x, 560, "clears the goose on the right")
        t.expectEqual(right.y, 500, "bottom on the feet")

        let left = MemePlacement.origin(
            feetX: 500, feetY: 700, onLeft: true, gooseHalfWidth: 48, gap: 12,
            windowWidth: 300, windowHeight: 200
        )
        t.expectEqual(left.x, 140, "clears the goose on the left")
    }
}
