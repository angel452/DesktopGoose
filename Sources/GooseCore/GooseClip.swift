/// Clip names the app asks for. A sheet is free to provide more.
public enum GooseClip {
    public static let idle = "idle"
    public static let walk = "walk"
    public static let drag = "drag"
    /// The angry stare (standing) and the angry charge (running), for the cursor hunt.
    public static let angryIdle = "angry_idle"
    public static let angryWalk = "angry_walk"

    /// Maps what the goose is doing to the animation that shows it.
    public static func name(for state: GooseState) -> String {
        switch state {
        case .idle, .offscreen, .presenting: return idle
        case .walking, .leaving, .returning, .deliveringExit: return walk
        case .deliveringEntry: return drag
        case .alerting: return angryIdle
        case .charging: return angryWalk
        }
    }
}
