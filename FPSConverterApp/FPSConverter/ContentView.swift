import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var model = VideoModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showShare = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    sourceCard
                    if model.input != nil {
                        fpsCard
                        qualityCard
                        engineCard
                        motionCard
                    }
                    if let out = model.output { resultCard(out) }
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }

            if model.input != nil && !model.isProcessing {
                VStack {
                    Spacer()
                    convertButton
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.94)], startPoint: .top, endPoint: .bottom).frame(height: 125), alignment: .bottom)
            }

            if model.isProcessing { processingOverlay }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showShare) { if let url = model.output?.url { ShareSheet(items: [url]) } }
        .alert("Saved", isPresented: $model.showSaved) { Button("OK", role: .cancel) {} }
        .alert("Couldn’t convert", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorText ?? "") }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let movie = try? await item.loadTransferable(type: MovieTransferable.self) {
                    await model.setInput(url: movie.url)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ScreenFlow")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text("FPS + AI quality converter")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.08))
                .clipShape(Circle())
        }
        .padding(.top, 4)
    }

    private var sourceCard: some View {
        PhotosPicker(selection: $pickerItem, matching: .videos) {
            if let info = model.input {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.08))
                        Image(systemName: "play.rectangle.fill").font(.title2)
                    }
                    .frame(width: 66, height: 66)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(info.name).font(.headline).lineLimit(1)
                        Text("\(info.resolutionText)  •  \(info.fpsText)")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.58))
                        Text("\(info.durationText)  •  \(info.sizeText)")
                            .font(.caption).foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.headline).foregroundStyle(.white.opacity(0.7))
                }
                .padding(16)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 23, weight: .bold))
                        .frame(width: 52, height: 52)
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(Circle())
                    Text("Choose a video").font(.headline)
                    Text("Select a clip from Photos to begin")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.48))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
            }
        }
        .buttonStyle(.plain)
        .background(cardBackground)
    }

    private var fpsCard: some View {
        settingCard(title: "Frame Rate", subtitle: "Choose the output FPS") {
            HStack(spacing: 8) {
                ForEach(model.fpsOptions, id: \.self) { fps in
                    Button {
                        model.targetFPS = fps
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(fps)").font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("FPS").font(.caption2.weight(.semibold)).opacity(0.55)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(model.targetFPS == fps ? .white : .white.opacity(0.06))
                        .foregroundStyle(model.targetFPS == fps ? .black : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var qualityCard: some View {
        settingCard(title: "Output Quality", subtitle: qualityDescription) {
            Picker("Quality", selection: $model.quality) {
                ForEach(VideoModel.Quality.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var engineCard: some View {
        settingCard(title: "Upscaling Engine", subtitle: engineDescription) {
            VStack(spacing: 9) {
                ForEach(VideoModel.UpscaleEngine.allCases) { engine in
                    Button {
                        model.upscaleEngine = engine
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: engine == .ai ? "brain.head.profile" : "square.resize.up")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(engine.rawValue).font(.subheadline.weight(.semibold))
                                Text(engine == .ai ? "Neural Engine • PiperSR 2×" : "Lanczos high-quality scaling")
                                    .font(.caption).foregroundStyle(.white.opacity(0.48))
                            }
                            Spacer()
                            Image(systemName: model.upscaleEngine == engine ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.upscaleEngine == engine ? .white : .white.opacity(0.25))
                        }
                        .padding(12)
                        .background(.white.opacity(model.upscaleEngine == engine ? 0.09 : 0.035))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var motionCard: some View {
        settingCard(title: "Motion", subtitle: model.mode == .smooth ? "Creates real in-between frames for smoother motion" : "Fast frame conversion with lower processing time") {
            Picker("Motion", selection: $model.mode) {
                ForEach(VideoModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func resultCard(_ out: VideoModel.Info) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Ready").font(.headline)
                Spacer()
                Text("\(out.fpsText)").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
            }
            Text("\(out.resolutionText)  •  \(out.sizeText)")
                .font(.subheadline).foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 10) {
                Button { model.saveToPhotos() } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)

                Button { showShare = true } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                }
                .buttonStyle(.bordered).tint(.white)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var convertButton: some View {
        Button {
            Task { await model.convert() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: model.upscaleEngine == .ai ? "brain.head.profile" : "sparkles")
                Text("Convert to \(model.targetFPS) FPS · \(model.quality.rawValue)")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(.white)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: max(0.02, model.progress))
                        .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(model.progress * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
                .frame(width: 126, height: 126)

                VStack(spacing: 8) {
                    Text(model.stageText)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    Text(model.upscaleEngine == .ai ? "AI Super Resolution is running on-device with the Apple Neural Engine." : "High-quality video processing is running on-device.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(Color.white.opacity(0.055))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private func settingCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.45))
            }
            content()
        }
        .padding(16)
        .background(cardBackground)
    }

    private var qualityDescription: String {
        switch model.quality {
        case .enhanced: return "Keep original dimensions and enhance detail"
        case .twoK: return "Upscale toward a 2560px long edge"
        case .fourK: return "Upscale toward a 3840px long edge"
        }
    }

    private var engineDescription: String {
        model.upscaleEngine == .ai
            ? "Neural super resolution before final scaling"
            : "Traditional high-quality resize and light sharpening"
    }
}
