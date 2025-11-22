import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

#if os(iOS)
    static let groupedBackground = Color(UIColor.systemGroupedBackground)
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)
#else
    static let groupedBackground = Color(NSColor.controlBackgroundColor)
    static let cardBackground = Color(NSColor.textBackgroundColor)
#endif

    static let creamBackground = Color(hex: 0xFBF8EF)
    static let primaryBlue = Color(hex: 0x2F80ED)
    static let successGreen = Color(hex: 0x27AE60)
    static let warningYellow = Color(hex: 0xEBC344)
    static let dangerRed = Color(hex: 0xE74C3C)
    static let mutedGray = Color(hex: 0x8C8C8C)
}
