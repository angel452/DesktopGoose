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
but Gatekeeper blocks it on first launch, so users right-click → Open once. Paying
for a Developer ID + notarisation is the only way to remove that step; it is a
nice-to-have, not a requirement.

## Cutting a Release

1. Land the change and make sure tests pass: `swift run GooseCoreTests`.
2. Bump the version in `Support/Info.plist` (`CFBundleShortVersionString`).
3. If you changed the goose's drawing, the icon is regenerated automatically by
   `release.sh`; nothing to do by hand.
4. Build, zip, and publish in one step:

   ```sh
   ./Scripts/release.sh v0.2.0
   ```

   Without a tag it only builds and zips into `build/` (a dry run):

   ```sh
   ./Scripts/release.sh
   ```

`release.sh v<tag>` runs `gh release create`, uploads the zip, and writes the
right-click-to-Open instructions into the Release notes. It needs the `gh` CLI
authenticated against this repo.

## The instructions users get

Baked into the Release notes:

> Download `DesktopGoose-<version>.zip`, unzip, and drag the app to `/Applications`.
> First launch: **right-click the app → Open** (ad-hoc signed, so Gatekeeper needs a
> one-time bypass). After that, double-click as usual. The goose lives in the menu
> bar as 🪿 — quit it from there.
