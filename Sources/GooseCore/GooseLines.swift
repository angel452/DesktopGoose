/// Everything the goose can say, shared by every platform so the Mac and Windows
/// builds never drift apart. Add as many lines as you like; one is picked at random
/// each time.
public enum GooseLines {
    /// Said when a reminder is delivered. One clock drives every reminder, so the
    /// water and move nudges share a single bank.
    public static let reminders = [
        "¡Tomá agua! 💧",
        "Hidratate, campeón.",
        "Un vaso de agua, dale.",
        "Tu cuerpo pide agua. 🚰",
        "¡Pará y caminá! 🦶",
        "Estirá esas patas.",
        "Levantate un toque.",
        "Movete, que oxida. 🚶",
    ]

    /// A gloat for a landed peck on the cursor.
    public static let onCatch = [
        "¡JAJA noob!",
        "¡A casa! 🏠",
        "¿Qué mirás, bobo?",
        "Te agarré. 😤",
        "Más lento imposible.",
    ]

    /// A parting threat for a chase the goose lost.
    public static let onGiveUp = [
        "Te estaré vigilando. 👀",
        "Tenés suerte que tengo cosas que hacer.",
        "Esta me la guardo.",
        "Corré, corré...",
    ]

    /// What the goose says when a bank is somehow empty.
    public static let fallback = "honk!"
}
