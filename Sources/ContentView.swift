import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var lightPosition = CGPoint(x: 0.74, y: 0.50)
    @State private var intensity = 0.88
    @State private var radius = 0.44
    @State private var depthStrength = 0.92
    @State private var lightColor: Color = Color(red: 1.0, green: 0.82, blue: 0.60)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                header
                preview
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .onAppear {
            camera.requestAndStart()
            pushSettings()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DepthLight V5")
                    .font(.headline.bold())
                Text(camera.modelReady ? "Depth-field relighting + occlusion" : camera.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: camera.switchCamera) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .foregroundStyle(.white)
        }
        .padding(.top, 6)
    }

    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.04))

                if let image = camera.renderedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(camera.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        lightPosition = CGPoint(
                            x: min(max(value.location.x / max(geo.size.width, 1), 0.02), 0.98),
                            y: min(max(value.location.y / max(geo.size.height, 1), 0.02), 0.98)
                        )
                        camera.updateLight(position: lightPosition)
                    }
            )
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    badge(camera.modelReady ? "DEPTH" : "RGB", active: camera.modelReady)
                    badge("\(Int(camera.fps.rounded())) FPS", active: camera.isRunning)
                }
                .padding(10)
            }
        }
        .frame(maxHeight: .infinity)
        .frame(minHeight: 430)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("القوة", systemImage: "sun.max.fill")
                        .font(.caption.bold())
                    Slider(value: $intensity, in: 0.05...1.0)
                        .onChange(of: intensity) { value in
                            camera.updateLight(intensity: Float(value))
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("الحجم", systemImage: "circle.dotted")
                        .font(.caption.bold())
                    Slider(value: $radius, in: 0.18...0.72)
                        .onChange(of: radius) { value in
                            camera.updateLight(radius: Float(value))
                        }
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("الظل / الحجب", systemImage: "circle.lefthalf.filled")
                        .font(.caption.bold())
                    Slider(value: $depthStrength, in: 0...1)
                        .onChange(of: depthStrength) { value in
                            camera.updateLight(depthStrength: Float(value))
                        }
                }

                ColorPicker("لون", selection: $lightColor, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: lightColor) { value in
                        camera.updateLight(color: rgb(value))
                    }
            }

            Button(action: camera.capture) {
                Label("حفظ الصورة", systemImage: "camera.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
    }

    private func badge(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(active ? .white : .secondary)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func pushSettings() {
        camera.updateLight(
            position: lightPosition,
            intensity: Float(intensity),
            radius: Float(radius),
            depthStrength: Float(depthStrength),
            color: rgb(lightColor)
        )
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
