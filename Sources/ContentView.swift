import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var intensity = 0.75
    @State private var radius = 125.0
    @State private var lightColor: Color = .blue
    @State private var lightPosition = CGPoint(x: 280, y: 300)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    preview
                    controls
                    technicalCard
                    shutter
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .onAppear { camera.requestAndStart() }
    }

    private var header: some View {
        VStack(spacing: 5) {
            Text("إضاءة العمق")
                .font(.system(size: 28, weight: .bold))
            Text("Realtime depth-aware light on iPhone")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                RadialGradient(
                    colors: [
                        lightColor.opacity(0.52 * intensity),
                        lightColor.opacity(0.18 * intensity),
                        .clear
                    ],
                    center: UnitPoint(x: min(max(lightPosition.x / max(geo.size.width, 1), 0), 1),
                                      y: min(max(lightPosition.y / max(geo.size.height, 1), 0), 1)),
                    startRadius: 4,
                    endRadius: radius
                )
                .blendMode(.screen)
                .allowsHitTesting(false)

                Circle()
                    .fill(Color.white)
                    .frame(width: 34, height: 34)
                    .shadow(color: lightColor.opacity(0.95), radius: 28)
                    .shadow(color: lightColor.opacity(0.85), radius: 12)
                    .position(lightPosition)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                lightPosition = CGPoint(
                                    x: min(max(value.location.x, 18), geo.size.width - 18),
                                    y: min(max(value.location.y, 18), geo.size.height - 18)
                                )
                            }
                    )

                VStack {
                    HStack {
                        Label(camera.isRunning ? "LIVE" : "WAIT", systemImage: "circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(camera.isRunning ? .green : .orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())

                        Spacer()

                        Button(action: camera.switchCamera) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .foregroundStyle(.white)
                    }
                    Spacer()
                    HStack {
                        Label(camera.depthCapable ? "Depth available" : "Depth fallback", systemImage: "cube.transparent")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }
                }
                .padding(14)
            }
            .contentShape(Rectangle())
            .onAppear {
                lightPosition = CGPoint(x: geo.size.width * 0.76, y: geo.size.height * 0.58)
            }
        }
        .frame(height: 500)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            controlCard(title: "شدة الإضاءة", icon: "sun.max.fill") {
                HStack {
                    Slider(value: $intensity, in: 0...1)
                    Text("\(Int(intensity * 100))%")
                        .monospacedDigit()
                        .frame(width: 48)
                }
            }

            controlCard(title: "حجم الإضاءة", icon: "circle.dashed") {
                Slider(value: $radius, in: 70...250)
            }

            controlCard(title: "لون الإضاءة", icon: "paintpalette.fill") {
                HStack(spacing: 16) {
                    ForEach([Color.blue, .cyan, .purple, .pink, .orange, .yellow, .green], id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(.white.opacity(lightColor == color ? 1 : 0), lineWidth: 2))
                            .onTapGesture { lightColor = color }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var technicalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("معلومات تقنية", systemImage: "info.circle")
                .font(.headline)

            HStack {
                techItem(camera.depthCapable ? "TrueDepth/LiDAR" : "RGB", "مصدر العمق")
                Divider().frame(height: 44)
                techItem("Realtime", "المعاينة")
                Divider().frame(height: 44)
                techItem("On-device", "المعالجة")
            }

            Text(camera.status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var shutter: some View {
        Button(action: camera.capture) {
            ZStack {
                Circle().stroke(Color.blue, lineWidth: 6).frame(width: 84, height: 84)
                Circle().fill(Color.white).frame(width: 66, height: 66)
            }
        }
        .padding(.top, 4)
        .accessibilityLabel("التقاط صورة")
    }

    private func controlCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func techItem(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.bold()).minimumScaleFactor(0.7).lineLimit(1)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
