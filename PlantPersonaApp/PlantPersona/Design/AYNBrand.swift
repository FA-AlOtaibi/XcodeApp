import SwiftUI

struct AYNMark: View {
    var size: CGFloat = 48
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 0.8)
                }
            AYNMarkShape()
                .stroke(
                    LinearGradient(colors: [.white, .cyan.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: max(2, size * 0.055), lineCap: .round, lineJoin: .round)
                )
                .padding(size * 0.22)
            Circle()
                .fill(.cyan)
                .frame(width: size * 0.16, height: size * 0.16)
                .shadow(color: .cyan.opacity(0.7), radius: size * 0.08)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

struct AYNMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        p.move(to: CGPoint(x: rect.minX, y: midY))
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY),
            control2: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY)
        )
        p.addCurve(
            to: CGPoint(x: rect.minX, y: midY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.maxY),
            control2: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY)
        )
        return p
    }
}

struct GlassPanel<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.06), .cyan.opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: .black.opacity(0.20), radius: 20, y: 10)
    }
}

struct GlassButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? .black : .white)
            .background(
                Group {
                    if prominent {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [.white, .cyan.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(prominent ? 0.45 : 0.18), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

extension Color {
    static let aynInk = Color(red: 0.025, green: 0.035, blue: 0.055)
    static let aynGlow = Color(red: 0.15, green: 0.86, blue: 0.95)
    static let aynViolet = Color(red: 0.48, green: 0.38, blue: 0.98)
}
