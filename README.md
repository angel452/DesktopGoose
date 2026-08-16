# Desktop Goose (macOS)

A goose that lives on your screen. It wanders around, occasionally walks off the
edge, comes back with muddy feet, tracks prints across everything you are doing,
drops memes and honks.

Built with Swift + AppKit. **No Xcode required** — the Command Line Tools are enough.

## Get the goose (no build needed)

Grab the latest **[Release](https://github.com/angel452/DesktopGoose/releases)**,
unzip it, and drag **Desktop Goose.app** to your Applications folder. First launch:
**right-click the app → Open** — it is ad-hoc signed, so macOS asks for confirmation
once. After that, double-click like any app.

It runs with no terminal open. There is no Dock icon or window; it lives in the menu
bar as 🪿, and you quit it from there. The download is a universal build, so it works
on both Apple Silicon and Intel Macs.

Prefer to build it yourself? Read on.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools — `xcode-select --install`

That is the whole list. AppKit ships with macOS, and the goose is drawn in code, so
there is nothing else to install and no dependency to fetch.

## Every command you need

```sh
git clone <this-repo> && cd DesktopGoose

./Scripts/bundle.sh              # build DesktopGoose.app (this Mac's arch) into build/
open build/DesktopGoose.app      # launch it
swift run GooseCoreTests         # run the test suite
swift run BakeSprites            # regenerate Assets/Sprites from PixelArtwork
swift run Preview                # render the artwork to build/ so you can look at it
swift run DesktopGoose           # run without bundling — logs go to your terminal
swift build                      # compile everything without running it

./Scripts/make-icon.sh           # regenerate Support/AppIcon.icns from the goose
./Scripts/bundle.sh release universal  # both arches — needs no Xcode, just CLT
./Scripts/release.sh             # build + zip a universal .app for a Release
```

**Quitting it.** The app has no Dock icon and no window to close. It lives in the
menu bar as 🪿, with **Take a Break Now**, **Shoo the Memes** and **Quit Desktop
Goose**. If it ever gets stuck: `pkill -f DesktopGoose`.

**Shipping it to non-devs.** Cutting a GitHub Release is what gets a change to people
who download rather than build. See [docs/RELEASING.md](docs/RELEASING.md).

**The loop while you work.** `swift run DesktopGoose` is the fast path — it prints
to the terminal, `Ctrl+C` stops it, and it reads `Assets/` straight from the working
directory, so new memes and sounds appear without rebundling. `./Scripts/bundle.sh`
is for producing the real `.app`.

**After changing the goose's drawing** (`Sources/GooseArt/PixelArtwork.swift`) you
must re-bake, or you will keep seeing the old sprite:

```sh
swift run BakeSprites && ./Scripts/bundle.sh
```

## Tests

```sh
swift run GooseCoreTests
```

XCTest and swift-testing both require a full Xcode install, which is why the suite
runs as a plain executable with a small hand-rolled runner in
`Sources/GooseCoreTests/TestRunner.swift`. Exit code is 0 on success, 1 on failure,
so it drops straight into CI.

It covers the goose's behaviour — stride spacing, staying on screen, the mud
lifecycle, visibility transitions, the meme pause, seed determinism — and the
animation layer: frame timing, looping, clip switching and manifest decoding.

Only `GooseCore` is tested, and deliberately so: it is the layer with no AppKit, no
windows and no clock of its own. Drawing is verified by rendering it and looking at
it (see *Working on the artwork*).

## Layout

```
Sources/
  GooseCore/          Pure behaviour and timing. No AppKit, no windows, no clock.
    GooseBrain.swift          State machine advanced by elapsed time; emits events.
    GooseEvent.swift          States and the events the shell has to perform.
    GooseConfig.swift         Speed, stride, mud duration, probabilities.
    SeededRandom.swift        Deterministic PRNG, so behaviour replays in tests.
    Animation.swift           Animation clips and the player that advances them.
    SpriteSheetManifest.swift The JSON contract for a sprite sheet.
  GooseArt/           How the goose looks. AppKit, but no app.
    GooseArtwork.swift        The seam: sprite sheet or procedural, same protocol.
    ArtStyle.swift            The medium anything drawn live has to share.
    SpeechBubble.swift        Comic bubble, stepped or smooth to match.
    PixelArtwork.swift        Pixel goose on a 42x38 grid. What ships.
    ProceduralArtwork.swift   Smooth vector goose. The zero-assets fallback.
    SpriteSheetArtwork.swift  Draws frames out of a sheet.
    SpriteSheetBaker.swift    Renders the procedural goose into a real sheet.
    MudRenderer.swift         Footprints, which are never sprites.
  DesktopGoose/       The app.
    GooseWindow.swift   One-frame-sized window that follows the goose around.
    MudWindow.swift     Screen-sized window holding only footprints.
    MemeWindow.swift    Floating meme window; click or wait to dismiss.
    SoundBank.swift     Honks from Assets/Sounds, with a system-sound fallback.
    Assets.swift        Locates Assets/ in the bundle or the working directory.
  BakeSprites/        Command that bakes the sprite sheet.
  GooseCoreTests/     Executable test suite.
Assets/
  Sprites/            goose.png + goose.json. Generated by BakeSprites.
  Memes/              Drop images here.
  Sounds/             Drop audio here.
Support/
  Info.plist          Bundle metadata. LSUIElement keeps it out of the Dock.
  AppIcon.icns        The app icon, generated from the goose by make-icon.sh.
Scripts/
  bundle.sh           Assembles and ad-hoc signs the .app (native or universal).
  make-icon.sh        Renders the goose into Support/AppIcon.icns.
  release.sh          Builds a universal .app and zips/publishes a Release.
docs/RELEASING.md     How and when to ship a build to non-dev users.
```

The split is the point. `GooseCore` decides what the goose does and is fully
testable without opening a window. `GooseArt` decides what it looks like and is
shared by the app and the baker. `DesktopGoose` only wires them together.

## Sprites

The goose is drawn from `Assets/Sprites/goose.png` plus `goose.json`. If either is
missing or unreadable, the app silently falls back to the procedural vector goose,
so it always draws something.

Regenerate the sheet from the procedural artwork at any time:

```sh
swift run BakeSprites                            # pixel art at 3x — what ships
swift run BakeSprites Assets/Sprites pixel 4     # chunkier pixel art
swift run BakeSprites Assets/Sprites smooth 0.5  # the smooth vector goose instead
```

### Two styles, and why they are not one setting

**Pixel art** (`PixelArtwork`) is drawn on a 42×38 grid with antialiasing off and
every coordinate a whole number. It is displayed at a whole-number zoom with
interpolation disabled.

**Smooth art** (`ProceduralArtwork`) is vector curves drawn large and scaled down
with interpolation on.

You cannot get the first by shrinking the second. Antialiasing turns small vector
edges into grey mush, and anything thinner than a pixel — a 1.5pt outline, a
feather crease — disappears outright. Pixel art is not a small drawing; it is a
drawing designed for the grid.

**The rule pixel art cannot break: scale by whole numbers only.** A 42px sprite
shown at 100px puts some source pixels in 2 screen pixels and others in 3, and the
sprite shimmers as it moves. So the on-screen size is *derived* from the native
size, never chosen:

```
native 42x38 px  x  zoom 3  =  126x114 device pixels
                             =  63x57 points on a 2x display
```

Two more places the grid can be lost, both already handled:

- `GooseWindow` rounds its origin to whole points. The goose's position is a float,
  and a sprite landing on a fractional origin resamples every frame.
- The manifest sets `"pixelArt": true`, which switches interpolation off at draw
  time. Without it macOS smooths the upscale and the crispness is gone.

### Replacing it with real artwork

Drop your own `goose.png` in `Assets/Sprites` and describe it in `goose.json`:

```json
{
  "image": "goose.png",
  "frameWidth": 42,
  "frameHeight": 38,
  "columns": 5,
  "scale": 0.6666666666666666,
  "anchorX": 18,
  "anchorY": 2,
  "pixelArt": true,
  "clips": [
    { "name": "walk", "frames": [0,1,2,3,4,5,6,7], "framesPerSecond": 10 },
    { "name": "idle", "frames": [8,9], "framesPerSecond": 2 }
  ]
}
```

That `scale` below 1 is not a mistake. It means the image holds *fewer* pixels than
the points it covers — the sprite is magnified. For the smooth style it is above 1
instead, because the sheet holds more pixels than points and is shrunk.

Four things that matter:

- **Every measurement is in image pixels.** `scale` converts them to screen points,
  so a sheet drawn at 2x for Retina sets `"scale": 2` and nothing else changes.
- **`anchorX` / `anchorY` are where the feet sit** inside a frame, measured from its
  bottom-left corner. Get this wrong and the goose floats or sinks into the screen.
- **Frames run left to right, top to bottom**, the way every sprite editor exports.
- **Set `"pixelArt": true` for pixel art.** It switches interpolation off; leaving it
  on turns crisp pixels to mush when the frame is scaled.

Only `frameWidth`, `frameHeight` and `clips` are required — everything else has a
sensible default. The app asks for the clips `walk` and `idle`; a sheet may define
more, and a sheet missing one falls back rather than drawing nothing.

## Working on the artwork

Unit tests will tell you the goose's behaviour is correct. They will not tell you
it looks like a seagull, that its head has come off, or that its legs merged into
one fat block at the extremes of the walk cycle. Every artwork defect in this
project was found by rendering it and looking at it.

```sh
swift run Preview          # goose + mud + speech bubble, composed → build/preview-scene.png
swift run Preview --sheet  # the sprite sheet magnified 8x  → build/preview-sheet.png
swift run Preview --sheet 12
```

`--sheet` matters more than it sounds. The whole sheet is 210×76 pixels; at 1:1 it
is unreadable, and it is drawn onto a checkerboard so transparent areas are obvious
rather than assumed. The composed scene renders at 2x, so one artwork pixel covers
the same ground it would on a Retina display — previewing at 1x flatters the result.

The loop:

```sh
# edit Sources/GooseArt/PixelArtwork.swift
swift run BakeSprites && swift run Preview --sheet
open build/preview-sheet.png
```

## Adding your own assets

- **Memes** — drop `.png` / `.jpg` / `.gif` files into `Assets/Memes`. With the
  folder empty the goose shows a placeholder card instead.
- **Sounds** — drop `.wav` / `.aiff` / `.mp3` files into `Assets/Sounds`. With the
  folder empty it falls back to the system "Pop" sound.

Re-run `./Scripts/bundle.sh` to copy new assets into the bundle.

## Tuning behaviour

Everything lives in `GooseConfig`: walking speed, distance between footprints, how
many muddy prints a return trip is worth, idle and off-screen durations, and the
odds of honking or dropping a meme. Pass a custom config where `GooseBrain` is
created in `AppDelegate`.

## Performance

A desktop pet runs all day, so its cost is a feature. Two decisions here came out
of profiling, not guesswork, and both are easy to undo by accident:

**The goose gets its own small window.** An obvious design paints everything into
one screen-sized transparent overlay. Measured, that made WindowServer recomposite
a screen-sized surface 60 times a second — about 29 points of CPU, roughly three
times what the app itself was using. The goose now lives in a window the size of a
single frame, and walking just moves that window. Its contents redraw only when the
animation frame or the facing direction changes: ~14 times a second while walking,
4 while idle. Mud keeps a screen-sized window because it has to persist wherever
the goose has been, but it repaints only when a footprint lands.

**Sprite frames are decoded once, at load.** Drawing a sub-rectangle of an
`NSImage` re-inflates the entire PNG on every draw — a `sample` profile caught
libz running inside the render loop. `SpriteSheetArtwork` now renders the sheet
into a memory bitmap at startup and slices it into one `CGImage` per frame.

To re-measure after a change:

```sh
top -l 6 -s 1 -pid $(pgrep -x WindowServer) -pid $(pgrep -n DesktopGoose) -stats pid,cpu,command
sample $(pgrep -n DesktopGoose) 8 -file /tmp/goose.sample.txt
```

Compare WindowServer against its idle baseline with the goose quit — on a busy
desktop that baseline is not zero.

## Anything drawn live must share the goose's medium

The goose comes from a sprite sheet. Footprints and speech bubbles are drawn on
the spot, in screen points — so they have to be told what medium they are joining.
`ArtStyle` carries that: whether the artwork is on a pixel grid, and how many
points one of its pixels covers (1 / manifest `scale` — 1.5 here).

Everything drawn live sizes itself in `style.pixels(n)` and snaps positions with
`style.snap(x)`. Switch back to the smooth goose and the mud and bubbles follow,
because they read the same value.

This is easy to break by halves. Changing the goose to pixel art while leaving the
mud antialiased looked like a rendering bug, and it was — a self-inflicted one.

## Known limits

- Runs on the main screen only; multi-monitor support means one overlay per screen.
- The shipped sheet is baked from `PixelArtwork`, not hand-drawn by an artist. It
  is a working placeholder, and replacing it touches no code.
- Only two clips exist: `walk` and `idle`. Honking, dropping a meme and returning
  muddy all reuse them.
- Speech bubbles point at where the goose stood when it spoke. They do not follow
  it as it walks away.
- Ad-hoc signed, so the first launch of a downloaded build needs a right-click →
  Open. Releases ship a universal (arm64 + x86_64) build; a Developer ID and
  notarisation would remove the one-time bypass but are not required to distribute.
- The overlay is click-through by design, so the goose cannot be picked up or
  interacted with. Grabbing other apps' windows would require the Accessibility
  API and its permission prompt.
