/// The fixed tag color palette. The server rejects any other color.
public enum TagColorPalette {
    public static let red = "#EF4444"
    public static let orange = "#F97316"
    public static let amber = "#F59E0B"
    public static let green = "#22C55E"
    public static let emerald = "#10B981"
    public static let cyan = "#06B6D4"
    public static let blue = "#3B82F6"
    public static let violet = "#8B5CF6"
    public static let purple = "#A855F7"
    public static let pink = "#EC4899"

    public static let allColors: [String] = [
        red, orange, amber, green, emerald,
        cyan, blue, violet, purple, pink
    ]

    public static func isValidColor(_ color: String) -> Bool {
        allColors.contains(color)
    }

    public static func color(at index: Int) -> String {
        allColors[index % allColors.count]
    }
}
