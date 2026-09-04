import SwiftUI

enum UltraTheme {
    static let background = Color(red: 0.035, green: 0.04, blue: 0.055)
    static let panel = Color.white.opacity(0.055)
    static let panelStrong = Color.white.opacity(0.095)
    static let line = Color.white.opacity(0.09)
    static let muted = Color.white.opacity(0.52)
}

extension View {
    func ultraCard(radius: CGFloat = 22) -> some View {
        self
            .background(UltraTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(UltraTheme.line, lineWidth: 1)
            )
    }
}
