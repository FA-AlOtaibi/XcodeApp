import SwiftUI

struct AYNMark: View {
    var size: CGFloat = 48
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                .fill(Color.aynIvory)
            AYNMarkShape()
                .stroke(Color.aynGraphite, style: StrokeStyle(lineWidth: max(2, size * 0.052), lineCap: .round, lineJoin: .round))
                .padding(size * 0.22)
            Circle()
                .fill(Color.aynLime)
                .frame(width: size * 0.17, height: size * 0.17)
                .overlay(Circle().stroke(Color.aynGraphite.opacity(0.8), lineWidth: max(1, size * 0.018)))
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
    }
}

struct AYNMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        p.move(to: CGPoint(x: rect.minX, y: midY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: midY), control1: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY), control2: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.minX, y: midY), control1: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.maxY), control2: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY))
        return p
    }
}

struct AYNPanel<Content: View>: View {
    private let content: Content
    var padding: CGFloat = 16
    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .background(Color.aynIvory.opacity(0.035), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.035), .aynLime.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            }
    }
}

struct AYNPressStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(selected ? Color.aynIvory : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(selected ? Color.aynGraphite : Color.aynIvory)
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(selected ? 0.30 : 0.10), lineWidth: 0.7) }
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

extension Color {
    static let aynGraphite = Color(red: 0.075, green: 0.075, blue: 0.066)
    static let aynGraphite2 = Color(red: 0.115, green: 0.11, blue: 0.095)
    static let aynIvory = Color(red: 0.95, green: 0.925, blue: 0.86)
    static let aynLime = Color(red: 0.76, green: 0.88, blue: 0.30)
    static let aynClay = Color(red: 0.82, green: 0.43, blue: 0.31)
    static let aynSage = Color(red: 0.42, green: 0.53, blue: 0.42)
}
