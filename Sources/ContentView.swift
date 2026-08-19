import SwiftUI

struct ContentView: View {
    @StateObject private var relight = RelightState()
    @State private var lightPosition = CGPoint(x: 0.72, y: 0.42)
    @State private var intensity = 0.88
    @State private var warmth = 0.48
    @State private var shadowSoftness = 0.58
    @State private var ambient = 0.20

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    preview
                    statusBar
                    controls
                    captureButton
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 26)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("DepthLight V4")
                .font(.system(size: 27, weight: .bold, design: .rounded))
            Text("TrueDepth Face Mesh • Dynamic Light • Hand Occlusion")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                RealisticRelightView(
                    state: relight,
                    lightPosition: lightPosition,
                    intensity: intensity,
                    warmth: warmth,
                    shadowSoftness: shadowSoftness,
                    ambient: ambient
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                Circle()
                    .fill(.white)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
                    .shadow(color: orbColor.opacity(0.95), radius: relight.handBlocking ? 8 : 28)
                    .shadow(color: orbColor.opacity(0.75), radius: relight.handBlocking ? 3 : 12)
                    .opacity(relight.handBlocking ? 0.32 : 1)
                    .position(
                        x: lightPosition.x * geo.size.width,
                        y: lightPosition.y * geo.size.height
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                lightPosition = CGPoint(
                                    x: min(max(value.location.x / max(geo.size.width, 1), 0.03), 0.97),
                                    y: min(max(value.location.y / max(geo.size.height, 1), 0.03), 0.97)
                                )
                            }
                    )

                VStack {
                    HStack(spacing: 8) {
                        badge(
                            relight.faceTracked ? "FACE 3D" : "SEARCHING",
                            icon: relight.faceTracked ? "face.smiling" : "viewfinder",
                            active: relight.faceTracked
                        )
                        badge(
                            relight.handDetected ? (relight.handBlocking ? "BLOCKING" : "HAND") : "NO HAND",
                            icon: "hand.raised.fill",
                            active: relight.handDetected
                        )
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .frame(height: 510)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Image(systemName: relight.handBlocking ? "circle.lefthalf.filled" : "sun.max.fill")
                .foregroundStyle(relight.handBlocking ? .orange : .yellow)
            Text(relight.status)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Text("\(Int(relight.fps.rounded())) FPS")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(13)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            controlCard(title: "شدة الضوء", icon: "sun.max.fill") {
                HStack {
                    Slider(value: $intensity, in: 0.05...1)
                    Text("\(Int(intensity * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44)
                }
            }

            controlCard(title: "حرارة اللون", icon: "thermometer.medium") {
                HStack(spacing: 10) {
                    Image(systemName: "sun.haze.fill").foregroundStyle(.orange)
                    Slider(value: $warmth, in: 0...1)
                    Image(systemName: "snowflake").foregroundStyle(.blue)
                }
            }

            controlCard(title: "نعومة الظل", icon: "circle.bottomhalf.filled") {
                Slider(value: $shadowSoftness, in: 0...1)
            }

            controlCard(title: "Ambient Fill", icon: "circle.dotted") {
                HStack {
                    Slider(value: $ambient, in: 0...0.65)
                    Text("\(Int(ambient * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44)
                }
            }
        }
    }

    private var captureButton: some View {
        Button {
            relight.captureToken += 1
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(.white, lineWidth: 3).frame(width: 54, height: 54)
                    Circle().fill(.white).frame(width: 42, height: 42)
                }
                Text("التقاط النتيجة")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func badge(_ title: String, icon: String, active: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(active ? .white : .secondary)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func controlCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
            content()
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var orbColor: Color {
        if warmth < 0.34 { return .orange }
        if warmth > 0.68 { return .cyan }
        return .white
    }
}
