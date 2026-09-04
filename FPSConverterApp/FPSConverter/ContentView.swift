import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = VideoModel()
    @StateObject private var library = LibraryStore()
    @State private var section: Section = .studio

    enum Section { case studio, library }

    var body: some View {
        ZStack {
            UltraTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if section == .studio {
                    StudioView(model: model, library: library) { section = .library }
                } else {
                    UltraLibraryView(library: library) { section = .studio }
                }
            }
            if model.isProcessing {
                UltraProcessingView(model: model)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.18), value: section)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.white)
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 1) {
                Text("ScreenFlow Ultra")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(section == .studio ? "AI video enhancer" : "Your exports")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(UltraTheme.muted)
            }
            Spacer()
            HStack(spacing: 5) {
                navButton(.studio, icon: "wand.and.stars")
                navButton(.library, icon: "rectangle.stack.fill")
            }
            .padding(4)
            .background(.white.opacity(0.055))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func navButton(_ target: Section, icon: String) -> some View {
        Button { section = target } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 34)
                .background(section == target ? .white : .clear)
                .foregroundStyle(section == target ? .black : .white.opacity(0.6))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct StudioView: View {
    @ObservedObject var model: VideoModel
    @ObservedObject var library: LibraryStore
    let openLibrary: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var shareURL: URL?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        if let input = model.input {
                            heroPreview(input, height: previewHeight(for: geo.size))
                            quickControls
                            enhancementCard
                            motionCard
                            if let notice = model.noticeText { noticeCard(notice) }
                            if let out = model.output { resultCard(out) }
                        } else {
                            uploadHero(height: min(430, max(330, geo.size.height * 0.54)))
                            capabilityRow
                        }
                        Color.clear.frame(height: model.input == nil ? 20 : 110)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                if model.input != nil && !model.isProcessing { convertBar }
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie, .video], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let source = urls.first else {
                model.errorText = "Could not import this file."
                return
            }
            let got = source.startAccessingSecurityScopedResource()
            defer { if got { source.stopAccessingSecurityScopedResource() } }
            let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("screenflow_\(UUID().uuidString).\(ext)")
            do {
                try? FileManager.default.removeItem(at: copy)
                try FileManager.default.copyItem(at: source, to: copy)
                Task { await model.setInput(url: copy) }
            } catch {
                model.errorText = "Could not copy this video into ScreenFlow."
            }
        }
        .sheet(item: Binding(get: {
            shareURL.map { ShareTarget(id: $0.absoluteString, url: $0) }
        }, set: { shareURL = $0?.url })) { target in
            ShareSheet(items: [target.url])
        }
        .alert("Saved", isPresented: $model.showSaved) { Button("OK", role: .cancel) {} }
        .alert("Couldn’t finish", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorText ?? "") }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let movie = try? await item.loadTransferable(type: MovieTransferable.self) {
                    await model.setInput(url: movie.url)
                } else {
                    model.errorText = "Could not import this video from Photos."
                }
            }
        }
    }

    private func previewHeight(for size: CGSize) -> CGFloat {
        if size.height > 850 { return 360 }
        if size.height > 720 { return 310 }
        return 265
    }

    private func uploadHero(height: CGFloat) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)
            ZStack {
                Circle().fill(.white.opacity(0.06)).frame(width: 112, height: 112)
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 7) {
                Text("Turn any clip into Ultra")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("AI detail recovery, smoother motion, and high-bitrate 2K / 4K export — on your iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(UltraTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 20)
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $pickerItem, matching: .videos) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                Button { showFiles = true } label: {
                    Label("Files", systemImage: "folder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white.opacity(0.08))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .padding(.horizontal, 16)
        .ultraCard(radius: 28)
    }

    private var capabilityRow: some View {
        HStack(spacing: 9) {
            capability("AI SR", "brain.head.profile")
            capability("120 FPS", "waveform.path")
            capability("4K Ultra", "4k.tv.fill")
        }
    }

    private func capability(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func heroPreview(_ info: VideoModel.Info, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            VideoPlayer(player: AVPlayer(url: info.url))
                .frame(height: height)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(info.name).font(.headline).lineLimit(1)
                    Text("\(info.resolutionText)  •  \(info.fpsText)  •  \(info.durationText)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Menu {
                    PhotosPicker(selection: $pickerItem, matching: .videos) { Text("Choose from Photos") }
                    Button("Choose from Files") { showFiles = true }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            .padding(16)
        }
    }

    private var quickControls: some View {
        VStack(spacing: 14) {
            controlHeader("Output", subtitle: "Choose FPS and final resolution")
            HStack(spacing: 8) {
                ForEach(model.fpsOptions, id: \.self) { fps in
                    chip("\(fps)", detail: "FPS", selected: model.targetFPS == fps) { model.targetFPS = fps }
                }
            }
            HStack(spacing: 8) {
                qualityChip(.enhanced, subtitle: "Native+")
                qualityChip(.twoK, subtitle: "2560")
                qualityChip(.fourK, subtitle: "3840")
            }
        }
        .padding(16)
        .ultraCard()
    }

    private func qualityChip(_ quality: VideoModel.Quality, subtitle: String) -> some View {
        chip(quality == .fourK ? "4K Ultra" : quality.rawValue, detail: subtitle, selected: model.quality == quality) {
            model.quality = quality
        }
    }

    private func chip(_ title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
                Text(detail).font(.caption2.weight(.bold)).opacity(0.48)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? .white : .white.opacity(0.05))
            .foregroundStyle(selected ? .black : .white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var enhancementCard: some View {
        VStack(spacing: 14) {
            controlHeader("Enhancement", subtitle: "AI is recommended for maximum detail")
            HStack(spacing: 9) {
                engineButton(.ai, title: "AI Ultra", subtitle: "Core ML detail recovery", icon: "brain.head.profile")
                engineButton(.standard, title: "Standard", subtitle: "Fast native upscale", icon: "bolt.fill")
            }
        }
        .padding(16)
        .ultraCard()
    }

    private func engineButton(_ engine: VideoModel.UpscaleEngine, title: String, subtitle: String, icon: String) -> some View {
        Button { model.upscaleEngine = engine } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon).font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: model.upscaleEngine == engine ? "checkmark.circle.fill" : "circle")
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(model.upscaleEngine == engine ? .black.opacity(0.55) : UltraTheme.muted)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 116)
            .background(model.upscaleEngine == engine ? .white : .white.opacity(0.045))
            .foregroundStyle(model.upscaleEngine == engine ? .black : .white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var motionCard: some View {
        VStack(spacing: 14) {
            controlHeader("Motion", subtitle: "Smooth synthesizes intermediate frames")
            HStack(spacing: 9) {
                modeButton(.smooth, title: "Smooth", icon: "waveform.path")
                modeButton(.simple, title: "Fast", icon: "bolt.fill")
            }
        }
        .padding(16)
        .ultraCard()
    }

    private func modeButton(_ mode: VideoModel.Mode, title: String, icon: String) -> some View {
        Button { model.mode = mode } label: {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(model.mode == mode ? .white : .white.opacity(0.05))
                .foregroundStyle(model.mode == mode ? .black : .white)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func controlHeader(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(UltraTheme.muted)
            }
            Spacer()
        }
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(.yellow)
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
        .padding(15)
        .ultraCard(radius: 17)
    }

    private func resultCard(_ out: VideoModel.Info) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Ultra export ready").font(.headline)
                Spacer()
                Button("Library") { openLibrary() }.font(.subheadline.bold())
            }
            Text("\(out.resolutionText) • \(out.fpsText) • \(out.sizeText)")
                .font(.subheadline).foregroundStyle(UltraTheme.muted)
            HStack(spacing: 9) {
                Button { model.saveToPhotos() } label: {
                    Label("Save", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                Button { shareURL = out.url } label: {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.bordered).tint(.white)
            }
        }
        .padding(16)
        .ultraCard()
    }

    private var convertBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(.white.opacity(0.08))
            Button {
                Task { await model.convert(library: library) }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: model.upscaleEngine == .ai ? "brain.head.profile" : "wand.and.stars")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.upscaleEngine == .ai ? "Enhance with AI" : "Enhance video").font(.headline)
                        Text("\(model.targetFPS) FPS • \(model.quality == .fourK ? "4K Ultra" : model.quality.rawValue)")
                            .font(.caption.weight(.semibold)).opacity(0.55)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.title3.bold())
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .background(.white)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(UltraTheme.background.opacity(0.97))
    }
}

private struct UltraProcessingView: View {
    @ObservedObject var model: VideoModel
    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 11)
                    Circle()
                        .trim(from: 0, to: max(0.015, model.progress))
                        .stroke(.white, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(model.progress * 100))%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                }
                .frame(width: 154, height: 154)
                VStack(spacing: 7) {
                    Text(model.stageText.isEmpty ? "Enhancing video" : model.stageText)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("Keep ScreenFlow open while the export is running.")
                        .font(.subheadline)
                        .foregroundStyle(UltraTheme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
        }
    }
}

private struct UltraLibraryView: View {
    @ObservedObject var library: LibraryStore
    let back: () -> Void
    @State private var playerItem: LibraryStore.Item?
    @State private var shareItem: LibraryStore.Item?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Library").font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("Every successful export stays here.").font(.subheadline).foregroundStyle(UltraTheme.muted)
                    }
                    Spacer()
                    Button("Studio") { back() }.font(.subheadline.bold())
                }
                .padding(.bottom, 4)

                if library.items.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 42)).foregroundStyle(.white.opacity(0.45))
                        Text("No exports yet").font(.title3.bold())
                        Text("Your finished videos will appear here automatically.").font(.subheadline).foregroundStyle(UltraTheme.muted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 70)
                    .ultraCard(radius: 24)
                } else {
                    ForEach(library.items) { item in
                        HStack(spacing: 13) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06))
                                Image(systemName: "play.fill").font(.headline)
                            }
                            .frame(width: 64, height: 64)
                            .onTapGesture { playerItem = item }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline).lineLimit(1)
                                Text("\(item.resolutionText) • \(item.fpsText) • \(item.sizeText)")
                                    .font(.caption).foregroundStyle(UltraTheme.muted).lineLimit(1)
                            }
                            Spacer()
                            Menu {
                                Button("Play") { playerItem = item }
                                Button("Share") { shareItem = item }
                                Button("Delete", role: .destructive) { library.delete(item) }
                            } label: {
                                Image(systemName: "ellipsis").frame(width: 40, height: 40)
                            }
                        }
                        .padding(13)
                        .ultraCard(radius: 18)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .sheet(item: $playerItem) { item in
            VideoPlayer(player: AVPlayer(url: library.url(for: item))).ignoresSafeArea()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [library.url(for: item)])
        }
    }
}

private struct ShareTarget: Identifiable {
    let id: String
    let url: URL
}
