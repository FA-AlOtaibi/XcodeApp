import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = VideoModel()
    @StateObject private var library = LibraryStore()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ConverterScreen(model: model, library: library) {
                selectedTab = 1
            }
            .tabItem { Label("Convert", systemImage: "wand.and.stars") }
            .tag(0)

            LibraryScreen(library: library)
                .tabItem { Label("Library", systemImage: "rectangle.stack.fill") }
                .tag(1)
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }
}

private struct ConverterScreen: View {
    @ObservedObject var model: VideoModel
    @ObservedObject var library: LibraryStore
    let openLibrary: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var shareURL: URL?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    hero
                    importPanel
                    if let info = model.input {
                        sourceSummary(info)
                        frameRatePanel
                        qualityPanel
                        enginePanel
                        motionPanel
                    }
                    if let notice = model.noticeText { noticePanel(notice) }
                    if let out = model.output { resultPanel(out) }
                    Color.clear.frame(height: model.input == nil ? 24 : 112)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
            }

            if model.isProcessing { processingOverlay }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.input != nil && !model.isProcessing {
                convertBar
            }
        }
        .sheet(item: Binding(get: {
            shareURL.map { ShareURL(id: $0.absoluteString, url: $0) }
        }, set: { value in
            shareURL = value?.url
        })) { item in
            ShareSheet(items: [item.url])
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.movie, .video], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let original = urls.first else { return }
                let accessed = original.startAccessingSecurityScopedResource()
                defer { if accessed { original.stopAccessingSecurityScopedResource() } }
                let ext = original.pathExtension.isEmpty ? "mov" : original.pathExtension
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("import_\(UUID().uuidString).\(ext)")
                do {
                    try? FileManager.default.removeItem(at: copy)
                    try FileManager.default.copyItem(at: original, to: copy)
                    Task { await model.setInput(url: copy) }
                } catch {
                    model.errorText = "The selected file could not be imported."
                }
            case .failure:
                model.errorText = "The selected file could not be imported."
            }
        }
        .alert("Saved to Photos", isPresented: $model.showSaved) {
            Button("OK", role: .cancel) { }
        }
        .alert("Couldn’t convert", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.errorText ?? "Unknown error")
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let movie = try? await item.loadTransferable(type: MovieTransferable.self) {
                    await model.setInput(url: movie.url)
                } else {
                    model.errorText = "This video could not be imported from Photos."
                }
            }
        }
    }

    private var horizontalPadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 28 : 16
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white)
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text("ScreenFlow")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("FPS + AI video enhancer")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.52))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importPanel: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.input == nil ? "Add a video" : "Replace source")
                        .font(.title3.bold())
                    Text("Photos or Files · MP4 / MOV and most iPhone codecs")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $pickerItem, matching: .videos) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button { showFileImporter = true } label: {
                    Label("Files", systemImage: "folder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.08))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .panelStyle()
    }

    private func sourceSummary(_ info: VideoModel.Info) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "film.stack.fill")
                .font(.system(size: 23, weight: .semibold))
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.075))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(info.name).font(.headline).lineLimit(1)
                Text("\(info.resolutionText) · \(info.fpsText)")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.58))
                Text("\(info.durationText) · \(info.sizeText)")
                    .font(.caption).foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .panelStyle()
    }

    private var frameRatePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Frame rate", "Choose the final motion rate")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(model.fpsOptions, id: \.self) { fps in
                    Button {
                        model.targetFPS = fps
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(fps)")
                                .font(.system(size: 21, weight: .bold, design: .rounded))
                            Text("FPS")
                                .font(.caption2.weight(.bold))
                                .opacity(0.5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(model.targetFPS == fps ? .white : .white.opacity(0.055))
                        .foregroundStyle(model.targetFPS == fps ? .black : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panelStyle()
    }

    private var qualityPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Resolution", "Output size without cropping")
            HStack(spacing: 8) {
                ForEach(VideoModel.Quality.allCases) { quality in
                    Button {
                        model.quality = quality
                    } label: {
                        VStack(spacing: 3) {
                            Text(quality.rawValue).font(.headline)
                            Text(quality == .enhanced ? "Native" : (quality == .twoK ? "2560px" : "3840px"))
                                .font(.caption2).opacity(0.5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(model.quality == quality ? .white : .white.opacity(0.055))
                        .foregroundStyle(model.quality == quality ? .black : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panelStyle()
    }

    private var enginePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Upscaling engine", "AI automatically falls back if a clip is unsupported")
            HStack(spacing: 10) {
                engineButton(.standard, icon: "square.resize.up", subtitle: "Lanczos")
                engineButton(.ai, icon: "brain.head.profile", subtitle: "Core ML")
            }
        }
        .panelStyle()
    }

    private func engineButton(_ engine: VideoModel.UpscaleEngine, icon: String, subtitle: String) -> some View {
        Button {
            model.upscaleEngine = engine
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine == .ai ? "AI Super Resolution" : "Standard")
                        .font(.subheadline.weight(.bold)).lineLimit(1)
                    Text(subtitle).font(.caption).opacity(0.5)
                }
                Spacer(minLength: 0)
                Image(systemName: model.upscaleEngine == engine ? "checkmark.circle.fill" : "circle")
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(.white.opacity(model.upscaleEngine == engine ? 0.12 : 0.045))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var motionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Motion", model.mode == .smooth ? "Motion-compensated frame interpolation" : "Fast frame duplication / dropping")
            HStack(spacing: 8) {
                ForEach(VideoModel.Mode.allCases) { mode in
                    Button {
                        model.mode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: mode == .smooth ? "waveform.path" : "bolt.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(model.mode == mode ? .white : .white.opacity(0.055))
                            .foregroundStyle(model.mode == mode ? .black : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panelStyle()
    }

    private func noticePanel(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(.yellow)
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.72))
            Spacer(minLength: 0)
        }
        .panelStyle()
    }

    private func resultPanel(_ out: VideoModel.Info) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Saved in ScreenFlow").font(.headline)
                Spacer()
                Button("Library") { openLibrary() }
                    .font(.subheadline.bold())
            }
            Text("\(out.resolutionText) · \(out.fpsText) · \(out.sizeText)")
                .font(.subheadline).foregroundStyle(.white.opacity(0.58))
            HStack(spacing: 10) {
                Button { model.saveToPhotos() } label: {
                    Label("Photos", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)

                Button { shareURL = out.url } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                }
                .buttonStyle(.bordered).tint(.white)
            }
        }
        .panelStyle()
    }

    private var convertBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(.white.opacity(0.08))
            Button {
                Task { await model.convert(library: library) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.upscaleEngine == .ai ? "brain.head.profile" : "wand.and.stars")
                    Text("Convert · \(model.targetFPS) FPS · \(model.quality.rawValue)")
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(.black.opacity(0.96))
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.98).ignoresSafeArea()
            VStack(spacing: 28) {
                ZStack {
                    Circle().stroke(.white.opacity(0.10), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: max(0.015, model.progress))
                        .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(model.progress * 100))%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                }
                .frame(width: 142, height: 142)

                VStack(spacing: 8) {
                    Text(model.stageText)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("Keep ScreenFlow open while the video is being processed.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.46))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
            }
        }
    }

    private func sectionTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.46))
        }
    }
}

private struct LibraryScreen: View {
    @ObservedObject var library: LibraryStore
    @State private var selectedItem: LibraryStore.Item?
    @State private var shareURL: URL?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                if library.items.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                        Text("Your video library is empty").font(.title3.bold())
                        Text("Every successful conversion is saved here automatically.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.48))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(library.items) { item in
                                Button { selectedItem = item } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 15).fill(.white.opacity(0.075))
                                            Image(systemName: "play.fill").font(.title3)
                                        }
                                        .frame(width: 66, height: 66)

                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.title).font(.headline).lineLimit(1)
                                            Text("\(item.resolutionText) · \(item.fpsText)")
                                                .font(.subheadline).foregroundStyle(.white.opacity(0.56))
                                            Text("\(item.durationText) · \(item.sizeText)")
                                                .font(.caption).foregroundStyle(.white.opacity(0.38))
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.28))
                                    }
                                    .padding(14)
                                    .background(.white.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { shareURL = library.url(for: item) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                                    Button(role: .destructive) { library.delete(item) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
        .sheet(item: $selectedItem) { item in
            LibraryPlayer(item: item, url: library.url(for: item), onDelete: {
                library.delete(item)
                selectedItem = nil
            })
        }
        .sheet(item: Binding(get: { shareURL.map { ShareURL(id: $0.absoluteString, url: $0) } }, set: { shareURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
    }
}

private struct LibraryPlayer: View {
    let item: LibraryStore.Item
    let url: URL
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var share = false

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                VideoPlayer(player: AVPlayer(url: url))
                    .aspectRatio(CGFloat(item.width) / CGFloat(max(1, item.height)), contentMode: .fit)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline)
                        Text("\(item.resolutionText) · \(item.fpsText) · \(item.sizeText)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button { share = true } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)

                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .padding(16)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $share) { ShareSheet(items: [url]) }
    }
}

private struct ShareURL: Identifiable {
    let id: String
    let url: URL
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.052))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.075), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
