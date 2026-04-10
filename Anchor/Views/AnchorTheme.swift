import SwiftUI

extension Color {
    static let anchorLinen      = Color(red: 0.980, green: 0.973, blue: 0.957)
    static let anchorSand       = Color(red: 0.949, green: 0.929, blue: 0.890)
    static let anchorTerracotta = Color(red: 0.878, green: 0.478, blue: 0.322)
    static let anchorSage       = Color(red: 0.353, green: 0.541, blue: 0.353)
    static let anchorAmber      = Color(red: 0.910, green: 0.627, blue: 0.188)
    static let anchorRed        = Color(red: 0.780, green: 0.290, blue: 0.250)
    static let anchorBorder     = Color(red: 0.894, green: 0.851, blue: 0.784)
    static let anchorText       = Color(red: 0.176, green: 0.145, blue: 0.125)
    static let anchorTextMuted  = Color(red: 0.478, green: 0.431, blue: 0.396)
    static let anchorBreakBlue  = Color(red: 0.380, green: 0.545, blue: 0.690)
}

struct SectionHeader: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.anchorTerracotta.opacity(0.6))
            .tracking(0.8)
    }
}
