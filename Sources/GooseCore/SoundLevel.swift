/// How loud the goose honks. Four fixed steps rather than a slider, so the menu is
/// the same on every platform — a slider in the Windows tray needs its own window.
public enum SoundLevel: String, CaseIterable, Sendable {
    case mute
    case quiet
    case normal
    case loud

    /// What a fresh install, or an unreadable saved value, starts with.
    public static let `default` = SoundLevel.normal

    /// The menu label.
    public var title: String {
        switch self {
        case .mute: return "Mute"
        case .quiet: return "Quiet"
        case .normal: return "Normal"
        case .loud: return "Loud"
        }
    }

    /// The honk's volume, from silence (0) to the file as recorded (1). Only the
    /// goose gets quieter; the system volume is never touched.
    public var gain: Double {
        switch self {
        case .mute: return 0
        case .quiet: return 0.25
        case .normal: return 0.55
        case .loud: return 1
        }
    }

    /// The text each platform saves between launches.
    public var storedValue: String { rawValue }

    /// The saved level, or the default when nothing — or nothing readable — was saved.
    public init(storedValue: String?) {
        self = storedValue.flatMap(SoundLevel.init(rawValue:)) ?? .default
    }
}
