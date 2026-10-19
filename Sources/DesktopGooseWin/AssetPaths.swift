import Foundation
import GoosePixels
import WinSDK

/// Finds the `Assets` folder next to the executable — where the release zip puts
/// it — or in the working directory, so `swift run DesktopGooseWin` picks up new
/// memes and sounds from the checkout without a rebuild.
enum AssetPaths {
    static let directory: URL? = {
        var candidates: [URL] = []
        if let executable = executableDirectory() {
            candidates.append(executable.appendingPathComponent("Assets", isDirectory: true))
        }
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Assets", isDirectory: true)
        )
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }()

    static var spritesDirectory: URL? {
        directory?.appendingPathComponent("Sprites", isDirectory: true)
    }

    /// `PlaySound` only plays WAV files.
    static func soundURLs() -> [URL] {
        files(in: "Sounds", extensions: ["wav"])
    }

    static func memeURLs() -> [URL] {
        files(in: "Memes", extensions: ImageDecoder.extensions)
    }

    private static func files(in subdirectory: String, extensions: [String]) -> [URL] {
        guard let folder = directory?.appendingPathComponent(subdirectory, isDirectory: true),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: folder,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              )
        else { return [] }

        // Dot-files are skipped by name too: on Windows `.skipsHiddenFiles` only
        // sees the hidden attribute, and macOS `._*` twins have none.
        return contents
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func executableDirectory() -> URL? {
        var buffer = [WCHAR](repeating: 0, count: 32_768)
        let length = GetModuleFileNameW(nil, &buffer, DWORD(buffer.count))
        guard length > 0 else { return nil }
        let path = String(decoding: buffer[0..<Int(length)], as: UTF16.self)
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    }
}

/// A path Win32 understands. `URL.path` can come back as `/C:/...` on Windows; the
/// file-system representation is the drive-letter form the C APIs expect.
func nativePath(_ url: URL) -> String {
    url.withUnsafeFileSystemRepresentation { pointer in
        pointer.map { String(cString: $0) } ?? url.path
    }
}

/// Plays honks from `Assets/Sounds`. With no sound file the goose stays quiet: the
/// system beep is the Windows error sound, which reads as an alarm, not a honk.
final class SoundBank {
    private let honks: [[WCHAR]]
    private var nextIndex = 0

    init() {
        honks = AssetPaths.soundURLs().map { wide(nativePath($0)) }
    }

    func honk() {
        guard !honks.isEmpty else { return }
        let sound = honks[nextIndex % honks.count]
        nextIndex += 1
        // Async, so a honk never stalls the goose; a new one cuts the last short.
        PlaySoundW(sound, nil, sndFilename | sndAsync | sndNoDefault)
    }
}
