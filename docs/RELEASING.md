# Releasing

Desktop Goose has two kinds of user:

- **Devs** clone the repo and run `./Scripts/bundle.sh` — they always get the
  latest code.
- **Non-devs** download a prebuilt `.app` from **GitHub Releases**. They only get a
  change once someone cuts a new Release.

> **Remember: after any change non-dev users should have, publish a new Release.**
> A merged fix or feature does nothing for the download-and-run crowd until the
> Release zip is refreshed. Treat "cut a Release" as part of finishing user-facing
> work, the same way re-baking sprites is part of finishing an artwork change.

## What ships

`Scripts/release.sh` produces `build/DesktopGoose-<version>.zip`, a **universal**
(`arm64` + `x86_64`) app that runs on both Apple Silicon and Intel. The build uses
only the Command Line Tools — each architecture is compiled on its own and merged
with `lipo`, because the combined `--arch a --arch b` form needs full Xcode.

The app is **ad-hoc signed** (no Apple Developer ID, no notarisation). That is free,
but Gatekeeper blocks it on first launch, so users approve it once via **System
Settings → Privacy & Security → Open Anyway** (macOS 15 removed the old right-click →
Open shortcut). Paying for a Developer ID + notarisation is the only way to remove
that step; it is a nice-to-have, not a requirement.

## Cutting a Release

**The common case is three lines** — bump the version, commit and push, run the
script. Everything, in order:

1. **Tests pass:** `swift run GooseCoreTests` (exit 0).

2. **Only if you changed the goose's drawing** (`Sources/GooseArt/PixelArtwork.swift`):
   re-bake, or the Release ships the *old* goose. `release.sh` refreshes the icon on
   its own but does **not** re-bake the sprite sheet — that is a committed source you
   update by hand.

   ```sh
   swift run BakeSprites       # updates Assets/Sprites/goose.{png,json}
   ./Scripts/make-icon.sh      # updates Support/AppIcon.icns
   ```

3. **Bump the version** in `Support/Info.plist` → `CFBundleShortVersionString`
   (e.g. `0.1.0` → `0.2.0`; small fix bumps the last digit, a bigger change the
   middle one).

4. **Commit and push** everything (never `CLAUDE.md` — it is local-only), so the tag
   the Release creates points at code that is actually on GitHub.

5. **Build, zip, and publish** — one command. The tag must match the version you set
   in step 3:

   ```sh
   ./Scripts/release.sh v0.2.0
   ```

`release.sh v<tag>` refreshes the icon, builds the universal `.app`, zips it, runs
`gh release create`, uploads the zip, and writes the first-launch instructions into
the Release notes. It needs the `gh` CLI authenticated against this repo
(`gh auth status`).

**Dry run** — build and zip into `build/` but publish nothing. Use it to confirm it
compiles before you tag:

```sh
./Scripts/release.sh
```

## The instructions users get

Baked into the Release notes:

> Download `DesktopGoose-<version>.zip`, unzip, and drag the app to `/Applications`.
> First launch: double-click it, then approve it once in **System Settings → Privacy
> & Security → Open Anyway** (ad-hoc signed, so Gatekeeper needs a one-time bypass).
> After that, double-click as usual. The goose lives in the menu bar as 🪿 — quit it
> from there.
