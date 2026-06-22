import SwiftUI

extension Color {
    /// Selah brand purple (#7B61FF).
    static let selahAccent = Color(red: 0x7B / 255.0, green: 0x61 / 255.0, blue: 0xFF / 255.0)
    /// Soft accent fill for badges / pills on a card.
    static let selahAccentSoft = Color.selahAccent.opacity(0.14)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// Gradients mirror AppTheme: notes=brandPurple, prayers=brandBlue, songs=orange.
enum WidgetGradients {
    static let note = LinearGradient(
        colors: [Color(hex: 0x7B61FF), Color(hex: 0x5B3FD9)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let prayer = LinearGradient(
        colors: [Color(hex: 0x2D6CDF), Color(hex: 0x1A4FA8)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let songs = LinearGradient(
        colors: [Color(hex: 0xFF9F43), Color(hex: 0xE67E22)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}
