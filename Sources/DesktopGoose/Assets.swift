import AppKit

/// Finds the `Assets` folder both inside the bundled `.app` and when running
/// straight from the package directory with `swift run`.
enum Assets {
    static var directory: URL? {
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("Assets", isDirectory: true)
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }

        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Assets", isDirectory: true)
        if FileManager.default.fileExists(atPath: local.path) { return local }

        return nil
    }

    /// Where a baked or hand-made sprite sheet lives. `nil` when there is no
    /// Assets folder at all.
    static var spritesDirectory: URL? {
        directory?.appendingPathComponent("Sprites", isDirectory: true)
    }

    static func soundURLs() -> [URL] {
        files(in: "Sounds", extensions: ["wav", "aiff", "aif", "mp3", "m4a", "caf"])
    }

    static func memeURLs() -> [URL] {
        files(in: "Memes", extensions: ["png", "jpg", "jpeg", "gif", "heic", "webp"])
    }

    static func randomMeme() -> NSImage? {
        memeURLs().randomElement().flatMap { NSImage(contentsOf: $0) }
    }

    private static func files(in subdirectory: String, extensions: [String]) -> [URL] {
        guard let directory = directory?.appendingPathComponent(subdirectory, isDirectory: true),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              )
        else { return [] }

        return contents.filter { extensions.contains($0.pathExtension.lowercased()) }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }
}
