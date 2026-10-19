import Foundation
import GooseCore

/// A minimal RIFF/WAVE file: a `fmt ` chunk, an optional extra chunk, then `data`.
func waveFile(
    samples: [Int16],
    format: UInt16 = 1,
    bitsPerSample: UInt16 = 16,
    extraChunk: [UInt8]? = nil
) -> [UInt8] {
    func le16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
    func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) } }
    func chunk(_ id: String, _ body: [UInt8]) -> [UInt8] {
        Array(id.utf8) + le32(UInt32(body.count)) + body + (body.count.isMultiple(of: 2) ? [] : [0])
    }

    let channels: UInt16 = 1
    let rate: UInt32 = 24_000
    let blockAlign = channels * bitsPerSample / 8
    let fmt = le16(format) + le16(channels) + le32(rate)
        + le32(rate * UInt32(blockAlign)) + le16(blockAlign) + le16(bitsPerSample)
    let data = samples.flatMap { le16(UInt16(bitPattern: $0)) }

    var body = Array("WAVE".utf8) + chunk("fmt ", fmt)
    if let extraChunk { body += chunk("LIST", extraChunk) }
    body += chunk("data", data)
    return Array("RIFF".utf8) + le32(UInt32(body.count)) + body
}

/// Reads the 16-bit samples back out of a file built by `waveFile`.
func samples(in file: [UInt8], count: Int) -> [Int16] {
    let start = file.count - count * 2
    return (0..<count).map { index in
        let low = UInt16(file[start + index * 2])
        let high = UInt16(file[start + index * 2 + 1])
        return Int16(bitPattern: low | high << 8)
    }
}

/// How loud the goose honks, and the WAV scaling Windows uses to apply it.
func runSoundTests(_ t: TestRunner) {
    // MARK: Levels

    t.test("the sound menu offers mute, quiet, normal and loud in that order") {
        t.expectEqual(SoundLevel.allCases.map(\.title), ["Mute", "Quiet", "Normal", "Loud"], "titles")
    }

    t.test("each level is louder than the one before, from silence to full volume") {
        let gains = SoundLevel.allCases.map(\.gain)
        t.expectEqual(gains.first, 0, "mute gain")
        t.expectEqual(gains.last, 1, "loud gain")
        t.expect(gains == gains.sorted() && Set(gains).count == gains.count, "gains not strictly rising: \(gains)")
    }

    t.test("a saved level comes back as itself after a restart") {
        for level in SoundLevel.allCases {
            t.expectEqual(SoundLevel(storedValue: level.storedValue), level, "round trip")
        }
    }

    t.test("nothing saved, or something unreadable, means the normal level") {
        t.expectEqual(SoundLevel(storedValue: nil), .normal, "nothing saved")
        t.expectEqual(SoundLevel(storedValue: "deafening"), .normal, "unknown value")
        t.expectEqual(SoundLevel.default, .normal, "default")
    }

    // MARK: Wave scaling

    t.test("scaling a wave multiplies every sample and keeps the header") {
        let file = waveFile(samples: [1000, -1000, 0, 32_767])
        guard let half = WaveFile.scaled(file, gain: 0.5) else { return t.fail("16-bit PCM refused") }
        t.expectEqual(half.count, file.count, "size")
        t.expectEqual(Array(half.prefix(file.count - 8)), Array(file.prefix(file.count - 8)), "header")
        t.expectEqual(samples(in: half, count: 4), [500, -500, 0, 16_384], "samples")
    }

    t.test("full gain leaves the wave untouched and zero gain silences it") {
        let file = waveFile(samples: [1234, -32_768, 32_767])
        t.expectEqual(WaveFile.scaled(file, gain: 1), file, "full gain")
        t.expectEqual(WaveFile.scaled(file, gain: 0).map { samples(in: $0, count: 3) }, [0, 0, 0], "zero gain")
    }

    t.test("a gain past the range is clamped, so samples never wrap around") {
        let file = waveFile(samples: [30_000, -30_000])
        t.expectEqual(WaveFile.scaled(file, gain: 2).map { samples(in: $0, count: 2) }, [30_000, -30_000], "above 1")
        t.expectEqual(WaveFile.scaled(file, gain: -1).map { samples(in: $0, count: 2) }, [0, 0], "below 0")
    }

    t.test("chunks before the samples are skipped, odd-sized ones with their pad byte") {
        let file = waveFile(samples: [800, -800], extraChunk: [1, 2, 3])
        t.expectEqual(WaveFile.scaled(file, gain: 0.25).map { samples(in: $0, count: 2) }, [200, -200], "samples")
    }

    t.test("a wave that is not 16-bit PCM, or not a wave at all, is refused") {
        t.expect(WaveFile.scaled(waveFile(samples: [1], format: 3), gain: 0.5) == nil, "float accepted")
        t.expect(WaveFile.scaled(waveFile(samples: [1], bitsPerSample: 8), gain: 0.5) == nil, "8-bit accepted")
        t.expect(WaveFile.scaled(Array("not a wave".utf8), gain: 0.5) == nil, "garbage accepted")
        t.expect(WaveFile.scaled([], gain: 0.5) == nil, "empty accepted")
    }

    t.test("a truncated wave is refused instead of read past its end") {
        let file = waveFile(samples: [100, 200, 300])
        t.expect(WaveFile.scaled(Array(file.prefix(30)), gain: 0.5) == nil, "truncated header accepted")
        t.expect(WaveFile.scaled(Array(file.dropLast(3)), gain: 0.5) == nil, "truncated samples accepted")
    }

    t.test("the shipped honk is a wave Windows can turn down") {
        let url = URL(fileURLWithPath: "Assets/Sounds/Goose.wav")
        guard let data = try? Data(contentsOf: url) else { return t.fail("Assets/Sounds/Goose.wav missing") }
        t.expect(WaveFile.scaled([UInt8](data), gain: 0.5) != nil, "Goose.wav is not 16-bit PCM")
    }
}
