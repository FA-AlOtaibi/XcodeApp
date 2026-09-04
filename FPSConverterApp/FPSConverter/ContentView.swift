import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = VideoModel()
    @StateObject private var library = LibraryStore()
    @State private var section: AppSection = .convert

    enum AppSection { case convert, library }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.035, green: 0.035, blue: 0.045)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                sectionPicker

                Group {
                    if section == .convert {
                        ConverterScreen(model: model, library: library) {
                            withAnimation(.easeInOut(duration: 0.2)) { section = .library }
                        }
                    } else {
                        LibraryScreen(library: library)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if model.isProcessing {
                ProcessingOverlay(model: model)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.white)
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text("ScreenFlow")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("Native FPS + AI Video Enhancer")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 8)

            Text("NATIVE")
                .font(.caption2.weight(.black))
                .tracking(1.2)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            sectionButton(.convert, title: "Convert", icon: "wand.and.stars")
            sectionButton(.library, title: "Library", icon: "rectangle.stack.fill")
        }
        .padding(5)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private func sectionButton(_ value: AppSection, title: String, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { section = value }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(section == value ? .white : .clear)
                .foregroundStyle(section == value ? .black : .white.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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
        GeometryReader { proxy in
            let side = proxy.size.width >= 430 ? 22.0 : 16.0

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if let input = model.input {
                        previewCard(input)
                        frameRateCard
                        resolutionCard
                        engineCard
                        motionCard
                        if let notice = model.noticeText { noticeCard(notice) }
                        if let output = model.output { resultCard(output) }
                    } else {
                        emptyState
                        featureStrip
                    }
                    Color.clear.frame(height: model.input == nil ? 20 : 100)
                }
                .padding(.horizontal, side)
                .padding(.top, 4)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.input != nil && !model.isProcessing {
                    convertButton
                        .padding(.horizontal, side)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .background(.black.opacity(0.94))
                }
            }
        }
        .sheet(item: Binding(get: {
            shareURL.map { ShareTarget(id: $0.absoluteString, url: $0) }
        }, set: { shareURL = $0?.url })) { target in
            ShareSheet(items: [target.url])
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.movie, .video], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let original = urls.first else { return }
                let accessed = original.startAccessingSecurityScopedResource()
                defer { if accessed { original.stopAccessingSecurityScopedResource() } }
                let ext = original.pathExtension.isEmpty ? "mov" : original.pathExtension
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("picked_\(UUID().uuidString).\(ext)")
                do {
                    try? FileManager.default.removeItem(at: copy)
                    try FileManager.default.copyItem(at: original, to: copy)
                    Task { await model.setInput(url: copy) }
                } catch {
                    model.errorText = "The selected video could not be imported."
                }
            case .failure:
                model.errorText = "The selected video could not be imported."
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

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Make motion smoother.\nKeep the quality.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.8)
                Text("Convert frame rate, upscale to 2K or 4K, and keep every result inside your ScreenFlow library.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.52))
                    .lineSpacing(3)
            }

            VStack(spacing: 11) {
                PhotosPicker(selection: $pickerItem, matching: .videos) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(.plain)

                Button { showFileImporter = true } label: {
                    Label("Choose from Files", systemImage: "folder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white.opacity(0.075))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(panelBackground)
    }

    private var featureStrip: some View {
        HStack(spacing: 8) {
            feature("120 FPS", "waveform.path")
            feature("4K", "4k.tv")
            feature("On-device", "iphone")
        }
    }

    private func feature(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
            Text(title).font(.caption.weight(.bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func previewCard(_ info: VideoModel.Info) -> some View {
        VStack(spacing: 0) {
            VideoPlayer(player: AVPlayer(url: info.url))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(info.resolutionText) · \(info.fpsText) · \(info.durationText) · \(info.sizeText)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 8)
                Menu {
                    PhotosPicker(selection: $pickerItem, matching: .videos) { Text("Photos") }
                    Button("Files") { showFileImporter = true }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.08))
                        .clipShape(Circle())
                }
            }
            .padding(.top, 13)
        }
        .padding(14)
        .background(panelBackground)
    }

    private var frameRateCard: some View {
        settingCard(title: "Frame rate", subtitle: "Choose the output motion rate") {
            HStack(spacing: 8) {
                ForEach(model.fpsOptions, id: \.self) { fps in
                    optionButton(selected: model.targetFPS == fps) {
                        model.targetFPS = fps
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(fps)").font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("FPS").font(.caption2.weight(.bold)).opacity(0.5)
                        }
                    }
                }
            }
        }
    }

    private var resolutionCard: some View {
        settingCard(title: "Resolution", subtitle: "Upscale without cropping") {
            HStack(spacing: 8) {
                ForEach(VideoModel.Quality.allCases) { q in
                    optionButton(selected: model.quality == q) {
                        model.quality = q
                    } label: {
                        VStack(spacing: 3) {
                            Text(q.rawValue).font(.headline)
                            Text(q == .enhanced ? "Native" : (q == .twoK ? "2560px" : "3840px"))
                                .font(.caption2).opacity(0.5)
                        }
                    }
                }
            }
        }
    }

    private var engineCard: some View {
        settingCard(title: "Upscaling engine", subtitle: "AI falls back automatically if a clip is unsupported") {
            VStack(spacing: 8) {
                engineRow(.standard, icon: "sparkles.rectangle.stack", subtitle: "Native Lanczos + detail recovery")
                engineRow(.ai, icon: "brain.head.profile", subtitle: "Core ML super resolution")
            }
        }
    }

    private func engineRow(_ value: VideoModel.UpscaleEngine, icon: String, subtitle: String) -> some View {
        Button {
            model.upscaleEngine = value
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(value.rawValue).font(.subheadline.weight(.bold))
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 8)
                Image(systemName: model.upscaleEngine == value ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(model.upscaleEngine == value ? .white : .white.opacity(0.22))
            }
            .padding(12)
            .background(.white.opacity(model.upscaleEngine == value ? 0.09 : 0.035))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var motionCard: some View {
        settingCard(title: "Motion", subtitle: model.mode == .smooth ? "Blends new in-between frames for smoother motion" : "Fast frame conversion for maximum stability") {
            HStack(spacing: 8) {
                ForEach(VideoModel.Mode.allCases) { mode in
                    optionButton(selected: model.mode == mode) {
                        model.mode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: mode == .smooth ? "waveform.path" : "bolt.fill")
                            .font(.subheadline.weight(.bold))
                    }
                }
            }
        }
    }

    private func resultCard(_ out: VideoModel.Info) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Saved inside ScreenFlow")
                    .font(.headline)
                Spacer()
                Button("Library") { openLibrary() }
                    .font(.subheadline.weight(.bold))
            }
            Text("\(out.resolutionText) · \(out.fpsText) · \(out.sizeText)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.52))
            HStack(spacing: 9) {
                Button { model.saveToPhotos() } label: {
                    Label("Photos", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)

                Button { shareURL = out.url } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(16)
        .background(panelBackground)
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill").foregroundStyle(.yellow)
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.yellow.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var convertButton: some View {
        Button {
            Task { await model.convert(library: library) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                Text("Convert · \(model.targetFPS) FPS · \(model.quality.rawValue)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 6)
                Image(systemName: "arrow.right")
            }
            .font(.headline)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(.white)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func settingCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.45))
            }
            content()
        }
        .padding(15)
        .background(panelBackground)
    }

    private func optionButton<Label: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selected ? .white : .white.opacity(0.055))
                .foregroundStyle(selected ? .black : .white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.white.opacity(0.052))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.075), lineWidth: 1))
    }
}

private struct LibraryScreen: View {
    @ObservedObject var library: LibraryStore
    @State private var shareURL: URL?
    @State private var previewURL: URL?

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width >= 430 ? 22.0 : 16.0
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Your library")
                                .font(.system(size: 27, weight: .bold, design: .rounded))
                            Text("Converted videos stay here until you delete them.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        Spacer()
                        Text("\(library.items.count)")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.07))
                            .clipShape(Circle())
                    }

                    if library.items.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.system(size: 38, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35))
                            Text("No converted videos yet")
                                .font(.headline)
                            Text("Finished exports will appear here automatically.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.45))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 64)
                        .background(panelBackground)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(library.items) { item in
                                libraryRow(item)
                            }
                        }
                    }
                    Color.clear.frame(height: 18)
                }
                .padding(.horizontal, side)
                .padding(.top, 4)
            }
        }
        .sheet(item: Binding(get: { previewURL.map { ShareTarget(id: "preview" + $0.absoluteString, url: $0) } }, set: { previewURL = $0?.url })) { target in
            VideoPlayer(player: AVPlayer(url: target.url))
                .ignoresSafeArea()
                .background(.black)
        }
        .sheet(item: Binding(get: { shareURL.map { ShareTarget(id: "share" + $0.absoluteString, url: $0) } }, set: { shareURL = $0?.url })) { target in
            ShareSheet(items: [target.url])
        }
        .onAppear { library.removeMissingFiles() }
    }

    private func libraryRow(_ item: LibraryStore.Item) -> some View {
        let url = library.url(for: item)
        return HStack(spacing: 13) {
            Button { previewURL = url } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.white.opacity(0.07))
                    Image(systemName: "play.fill")
                        .font(.headline)
                }
                .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(item.resolutionText) · \(item.fpsText)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                Text("\(item.durationText) · \(item.sizeText)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.36))
            }
            Spacer(minLength: 6)

            Menu {
                Button("Preview") { previewURL = url }
                Button("Share") { shareURL = url }
                Button("Delete", role: .destructive) { library.delete(item) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.055))
                    .clipShape(Circle())
            }
        }
        .padding(13)
        .background(panelBackground)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}

private struct ProcessingOverlay: View {
    @ObservedObject var model: VideoModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.93).ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: max(0.015, model.progress))
                        .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(model.progress * 100))%")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                }
                .frame(width: 138, height: 138)

                VStack(spacing: 7) {
                    Text(model.stageText.isEmpty ? "Processing video" : model.stageText)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("Keep ScreenFlow open until the export finishes.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.46))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
            }
        }
    }
}

private struct ShareTarget: Identifiable {
    let id: String
    let url: URL
}
