import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var lightPosition = CGPoint(x: 0.72, y: 0.48)
    @State private var intensity = 0.58
    @State private var radius = 0.30
    @State private var depthStrength = 0.62
    @State private var lightColor: Color = Color(red: 1.0, green: 0.82, blue: 0.60)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                header
                preview
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .onAppear {
            camera.requestAndStart()
            pushSettings()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DepthLight V7")
                    .font(.headline.bold())
                Text(camera.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: camera.switchCamera) {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .foregroundStyle(.white)
        }
        .padding(.top, 6)
    }

    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                if let image = camera.renderedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text(camera.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        lightPosition = CGPoint(
                            x: min(max(value.location.x / max(geo.size.width, 1), 0.03), 0.97),
                            y: min(max(value.location.y / max(geo.size.height, 1), 0.03), 0.97)
                        )
                        camera.updateLight(position: lightPosition)
                    }
            )
            .overlay(alignment: .topLeading) {
                HStack(spacing: 7) {
                    badge(camera.depthMode, active: camera.modelReady)
                    badge("\(Int(camera.fps.rounded())) FPS", active: camera.isRunning)
                }
                .padding(10)
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .frame(maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                control(title: "القوة", icon: "sun.max.fill") {
                    Slider(value: $intensity, in: 0.08...0.85)
                        .onChange(of: intensity) { value in camera.updateLight(intensity: Float(value)) }
                }
                control(title: "الحجم", icon: "circle.dotted") {
                    Slider(value: $radius, in: 0.12...0.55)
                        .onChange(of: radius) { value in camera.updateLight(radius: Float(value)) }
                }
            }

            HStack(spacing: 12) {
                control(title: "الظل / الحجب", icon: "circle.lefthalf.filled") {
                    Slider(value: $depthStrength, in: 0...0.85)
                        .onChange(of: depthStrength) { value in camera.updateLight(depthStrength: Float(value)) }
                }
                ColorPicker("لون", selection: $lightColor, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: lightColor) { value in camera.updateLight(color: rgb(value)) }
                    .frame(width: 48)
            }

            HStack(spacing: 10) {
                preset("طبيعي", intensity: 0.46, radius: 0.34, shadow: 0.48)
                preset("واقعي", intensity: 0.58, radius: 0.30, shadow: 0.62)
                preset("درامي", intensity: 0.72, radius: 0.24, shadow: 0.78)
            }

            Button(action: camera.capture) {
                Label("حفظ الصورة", systemImage: "camera.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 19))
    }

    private func control<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption.bold())
            content()
        }
        .frame(maxWidth: .infinity)
    }

    private func preset(_ title: String, intensity: Double, radius: Double, shadow: Double) -> some View {
        Button(title) {
            self.intensity = intensity
            self.radius = radius
            self.depthStrength = shadow
            camera.updateLight(intensity: Float(intensity), radius: Float(radius), depthStrength: Float(shadow))
        }
        .font(.caption.bold())
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.07), in: Capsule())
        .buttonStyle(.plain)
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
        camera.updateLight(position: lightPosition,
                           intensity: Float(intensity),
                           radius: Float(radius),
                           depthStrength: Float(depthStrength),
                           color: rgb(lightColor))
    }

    private func rgb(_ color: Color) -> SIMD3<Float> {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3<Float>(Float(r), Float(g), Float(b))
    }
}
