import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var intensity = 0.8
    @State private var radius = 0.32
    @State private var depthStrength = 1.0
    @State private var lightColor: Color = .blue
    @State private var lightPosition = CGPoint(x: 0.74, y: 0.58)

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
                .padding(.bottom, 26)
            }
        }
        .onAppear {
            camera.requestAndStart()
            pushSettings()
        }
    }

    private var header: some View {
        VStack(spacing: 5) {
            Text("إضاءة العمق")
                .font(.system(size: 28, weight: .bold))
            Text("Core ML Depth Anything V2 + Metal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.05))

                if let image = camera.renderedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text(camera.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: 34, height: 34)
                    .shadow(color: lightColor.opacity(0.95), radius: 28)
                    .shadow(color: lightColor.opacity(0.85), radius: 12)
                    .position(x: lightPosition.x * geo.size.width,
                              y: lightPosition.y * geo.size.height)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let nx = min(max(value.location.x / max(geo.size.width, 1), 0.02), 0.98)
                                let ny = min(max(value.location.y / max(geo.size.height, 1), 0.02), 0.98)
                                lightPosition = CGPoint(x: nx, y: ny)
                                camera.updateLight(position: lightPosition)
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
                        Label(camera.modelReady ? "AI Depth" : "RGB fallback",
                              systemImage: camera.modelReady ? "cube.transparent.fill" : "camera")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }
                }
                .padding(14)
            }
        }
        .frame(height: 500)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            controlCard(title: "شدة الإضاءة", icon: "sun.max.fill") {
                HStack {
                    Slider(value: $intensity, in: 0...1)
                        .onChange(of: intensity) { value in
                            camera.updateLight(intensity: Float(value))
                        }
                    Text("\(Int(intensity * 100))%")
                        .monospacedDigit()
                        .frame(width: 48)
                }
            }

            controlCard(title: "نطاق الإضاءة", icon: "circle.dashed") {
                Slider(value: $radius, in: 0.12...0.60)
                    .onChange(of: radius) { value in
                        camera.updateLight(radius: Float(value))
                    }
            }

            controlCard(title: "تأثير العمق", icon: "cube.transparent") {
                HStack {
                    Slider(value: $depthStrength, in: 0...1)
                        .onChange(of: depthStrength) { value in
                            camera.updateLight(depthStrength: Float(value))
                        }
                    Text("\(Int(depthStrength * 100))%")
                        .monospacedDigit()
                        .frame(width: 48)
                }
            }

            controlCard(title: "لون الإضاءة", icon: "paintpalette.fill") {
                HStack(spacing: 15) {
                    ForEach([Color.blue, .cyan, .purple, .pink, .orange, .yellow, .green], id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(.white.opacity(lightColor == color ? 1 : 0), lineWidth: 2))
                            .onTapGesture {
                                lightColor = color
                                camera.updateLight(color: rgb(color))
                            }
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
                techItem("Depth V2", "Core ML")
                Divider().frame(height: 44)
                techItem("Metal", "GPU shader")
                Divider().frame(height: 44)
                techItem("\(Int(camera.fps.rounded())) FPS", "فعلي")
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

    private func pushSettings() {
        camera.updateLight(position: lightPosition,
                           intensity: Float(intensity),
                           radius: Float(radius),
                           depthStrength: Float(depthStrength),
                           color: rgb(lightColor))
    }

    private func rgb(_ color: Color) -> SIMD3<Float> {
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3<Float>(Float(r), Float(g), Float(b))
    }
}
