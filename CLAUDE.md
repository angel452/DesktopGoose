# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Desktop Goose for macOS: a goose that wanders your screen, walks off the edge, comes
back with muddy feet, tracks prints, drops memes and honks. Swift + AppKit, built
**without Xcode** — the Command Line Tools are enough. AppKit ships with macOS and the
goose is drawn in code, so there are no external dependencies to fetch.

## Commands

```sh
swift run DesktopGoose        # run without bundling — logs to terminal, Ctrl+C stops it
swift run GooseCoreTests      # run the whole test suite (exit 0 pass / 1 fail)
swift build                   # compile everything without running
./Scripts/bundle.sh           # assemble build/DesktopGoose.app (release by default)
./Scripts/bundle.sh debug     # same, debug configuration
open build/DesktopGoose.app   # launch the bundled app
swift run BakeSprites         # regenerate Assets/Sprites from PixelArtwork
swift run Preview             # render the artwork to build/ for inspection
```

- **`swift run DesktopGoose` is the dev inner loop.** It reads `Assets/` from the
  working directory, so new memes and sounds appear without rebundling. `bundle.sh`
  is only for producing the real `.app`.
- **No single-test runner.** `GooseCoreTests` is a plain executable with a hand-rolled
  runner (`Sources/GooseCoreTests/TestRunner.swift`) — XCTest and swift-testing both
  require a full Xcode install. There is no filter flag; to run one test, temporarily
  comment out the others in `Sources/GooseCoreTests/main.swift`.
- **Quitting the running app:** it has no Dock icon and no window — it lives in the
  menu bar as 🪿 (Clean the Screen / Shoo the Memes / Quit). If stuck: `pkill -f DesktopGoose`.
- **After editing the goose's drawing** (`Sources/GooseArt/PixelArtwork.swift`) you must
  re-bake or you keep seeing the old sprite: `swift run BakeSprites && ./Scripts/bundle.sh`.

## Architecture

The governing rule: **a pure, testable core knows nothing about screens, windows, audio,
or the clock; the AppKit layer is a thin adapter that feeds it time and performs what it
reports.** Understanding the boundary below is the fastest way to be productive here.

### The pure/presentation seam (`GooseCore` → `DesktopGoose`)

`GooseBrain` (`Sources/GooseCore/GooseBrain.swift`) is a `struct` state machine with no
timer, no view, no window. You call `update(deltaTime:)` and it returns `[GooseEvent]` —
footprints, honks, dropped memes, `startedMoving`, `visibilityChanged`. The brain only
*reports*; it never draws or plays anything. `AppDelegate.tick()` runs a 60 Hz `Timer`,
computes the real elapsed delta (clamped to 0.1 s so waking from sleep doesn't teleport
the goose), feeds it to the brain, and switches over the returned events to perform side
effects. This is what makes behaviour testable without ever opening a window.

- **States:** `idle → walking → (idle | leaving) → offscreen → returning → idle`
  (`GooseEvent.swift`). Muddy footprints only appear during `returning`, decremented per
  print from `muddyStepCount`.
- **Everything time-driven is a struct fed `deltaTime`:** `GooseBrain` and
  `AnimationPlayer` (`Animation.swift`) share the identical shape. No object owns a clock
  except `AppDelegate`.
- **Determinism:** `GooseBrain` is generic over `RandomNumberGenerator`. The app uses
  `SystemRandomNumberGenerator`; tests inject `SeededRandom` (`SeededRandom.swift`) so a
  seed reproduces an exact run. Tuning lives in `GooseConfig` (speeds, probabilities,
  duration ranges) — change behaviour there, not with magic numbers in the brain.
- **Coordinate spaces:** the brain thinks in screen-local coordinates starting at origin
  `.zero`; `AppDelegate` translates to global desktop coordinates via `screenOrigin`, so
  the brain never needs to know where its screen sits in a multi-monitor arrangement.
- **Footprints are placed at exact stride multiples** along the segment travelled each
  frame (not wherever the frame ended), so print spacing does not inherit the frame rate.

### Two windows, on purpose (`DesktopGoose`)

- `MudWindow` — screen-sized, holds footprints, almost never repaints.
- `GooseWindow` — a window just big enough for one animation frame, *moved* to follow the
  goose, redrawing only when the frame index or facing direction actually changes.

The split is a measured performance decision: repainting a screen-sized surface at 60 Hz
cost the WindowServer heavily; moving a small window is cheap. Both windows are borderless,
transparent, click-through (`ignoresMouseEvents`), and join all Spaces. The goose sits one
level above the mud so prints stay under the bird. Window origins are rounded to whole
points — a pixel-art sprite on a fractional origin resamples and appears to vibrate.

### The artwork seam (`GooseArt`)

`GooseArtwork` (protocol in `GooseArtwork.swift`) is the seam that lets real art replace
the placeholder without the app noticing. Two implementations:

- `SpriteSheetArtwork` — loads a baked sheet (`Assets/Sprites/goose.png` + `goose.json`).
- `ProceduralArtwork` — draws the goose in vector code as a fallback.

`AppDelegate` prefers the sheet and falls back to procedural, **so the app never fails to
draw a goose because an asset is missing** (it prints which loaded). The baked sheet is a
render of the same vector goose, so both look identical on screen.

- **Baking pipeline:** `PixelArtwork.swift` is the source of truth for the drawing →
  `BakeSprites` renders it via `SpriteSheetBaker` into `Assets/Sprites` → the app loads
  the baked sheet. Editing the drawing without re-baking shows the stale sprite.
- **`GooseClip.name(for:state)`** maps brain states to animation clip names (`idle` /
  `walk`); `clipOrFallback` degrades gracefully when a sheet lacks a requested clip.
- **`ArtStyle`** (`ArtStyle.swift`) carries whether the medium is a pixel grid and how big
  one artwork pixel is in screen points, so anything drawn *live* next to the goose
  (footprints, speech bubbles) can `snap` to the same grid — mixing crisp and smooth on
  one screen reads as a bug.

### Asset resolution (`Assets.swift`)

`Assets` resolves the `Assets/` folder both inside the bundled `.app`
(`Bundle.main.resourceURL`) **and** from the current working directory when running via
`swift run`. That dual lookup is why the dev loop can hot-add memes/sounds without a rebuild.

## Package layout & Swift modes

`Package.swift` defines: `GooseCore` (pure library), `GooseArt` (drawing library,
depends on core — a library not app code because `BakeSprites` needs it too), and four
executables: `DesktopGoose` (the app), `BakeSprites`, `Preview`, `GooseCoreTests`.

- **`GooseCore` compiles in Swift 6 language mode; every other target is pinned to Swift 5
  mode** (`swiftLanguageMode(.v5)`). Keep the core strictly-concurrency-clean.
- `bundle.sh` copies the binary + `Support/Info.plist` + `Assets/` into a hand-assembled
  `.app` and applies an **ad-hoc** signature (runs locally; distribution needs a Developer ID).
