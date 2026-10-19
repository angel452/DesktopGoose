import Foundation
import GooseCore
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
///
/// `PlaySound` has no volume, so each honk is kept in memory already scaled to the
/// chosen level (see `WaveFile`) — only the goose gets quieter, never the system.
/// The level is saved under `%APPDATA%\DesktopGoose` and outlives a restart.
final class SoundBank {
    private let recordings: [[UInt8]]
    private var honks: [WaveBuffer] = []
    private var nextIndex = 0

    var level: SoundLevel {
        didSet {
            prepareHonks()
            SoundBank.save(level)
        }
    }

    init() {
        recordings = AssetPaths.soundURLs().compactMap { url in
            (try? Data(contentsOf: url)).map { [UInt8]($0) }
        }
        level = SoundBank.load()
        prepareHonks()
    }

    func honk() {
        guard level != .mute, !honks.isEmpty else { return }
        let sound = honks[nextIndex % honks.count]
        nextIndex += 1
        // Async, so a honk never stalls the goose; a new one cuts the last short.
        PlaySoundW(sound.name, nil, sndMemory | sndAsync | sndNoDefault)
    }

    private func prepareHonks() {
        // An async honk reads straight from its buffer: stop it before freeing one.
        PlaySoundW(nil, nil, 0)
        // A wave the scaler cannot read (not 16-bit PCM) still plays, as recorded.
        honks = recordings.map { WaveBuffer(WaveFile.scaled($0, gain: level.gain) ?? $0) }
    }

    // MARK: Saved level

    private static var settingsFile: URL? {
        ProcessInfo.processInfo.environment["APPDATA"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent("DesktopGoose", isDirectory: true)
                .appendingPathComponent("sound-level.txt")
        }
    }

    private static func load() -> SoundLevel {
        let saved = settingsFile.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        return SoundLevel(storedValue: saved?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func save(_ level: SoundLevel) {
        guard let file = settingsFile else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? level.storedValue.write(to: file, atomically: true, encoding: .utf8)
    }
}

/// A wave file in memory that `PlaySound` can read with `SND_MEMORY`. Its bytes have
/// a fixed address for as long as it lives, which a Swift array does not promise.
private final class WaveBuffer {
    private let bytes: UnsafeMutableRawBufferPointer

    init(_ wave: [UInt8]) {
        bytes = .allocate(byteCount: wave.count, alignment: 2)
        bytes.copyBytes(from: wave)
    }

    deinit { bytes.deallocate() }

    /// With `SND_MEMORY` the "name" parameter is the wave itself.
    var name: UnsafePointer<WCHAR>? {
        bytes.baseAddress.map { UnsafePointer($0.assumingMemoryBound(to: WCHAR.self)) }
    }
}
