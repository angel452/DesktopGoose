/// Turns a WAV file down in memory. Windows' `PlaySound` has no volume of its own,
/// so the app plays a scaled copy instead — which leaves the system volume alone.
public enum WaveFile {
    /// A copy of a 16-bit PCM wave with every sample multiplied by `gain`, clamped
    /// to 0...1. Anything else — another encoding, a truncated file, not a wave at
    /// all — returns nil, and the caller plays nothing rather than noise.
    public static func scaled(_ bytes: [UInt8], gain: Double) -> [UInt8]? {
        guard bytes.count >= 12,
              ascii(bytes, at: 0) == "RIFF",
              ascii(bytes, at: 8) == "WAVE"
        else { return nil }

        var isPCM16 = false
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = ascii(bytes, at: offset)
            let size = Int(uint32(bytes, at: offset + 4))
            let body = offset + 8
            guard size <= bytes.count - body else { return nil }

            switch id {
            case "fmt ":
                guard size >= 16 else { return nil }
                isPCM16 = uint16(bytes, at: body) == 1 && uint16(bytes, at: body + 14) == 16
            case "data":
                guard isPCM16 else { return nil }
                return scaling(bytes, samples: body..<(body + size), gain: min(max(gain, 0), 1))
            default:
                break
            }
            // Chunks are word-aligned: an odd-sized one carries a pad byte.
            offset = body + size + (size & 1)
        }
        return nil
    }

    private static func scaling(_ bytes: [UInt8], samples: Range<Int>, gain: Double) -> [UInt8] {
        var result = bytes
        var index = samples.lowerBound
        while index + 1 < samples.upperBound {
            let sample = Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
            let scaled = UInt16(bitPattern: Int16((Double(sample) * gain).rounded()))
            result[index] = UInt8(scaled & 0xFF)
            result[index + 1] = UInt8(scaled >> 8)
            index += 2
        }
        return result
    }

    private static func ascii(_ bytes: [UInt8], at offset: Int) -> String {
        String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
    }

    private static func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
}
