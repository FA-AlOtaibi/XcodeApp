import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = VideoModel()
    @StateObject private var library = LibraryStore()
    @State private var selectedTab = 0
    @State private var pickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var shareURL: URL?
    @State private var previewURL: URL?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, sidePadding(geo.size.width))
                        .padding(.top, 8)
                        .padding(.bottom, 10)

                    Group {
                        if selectedTab == 0 {
                            converter(width: geo.size.width)
                        } else {
                            libraryView(width: geo.size.width)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    customTabBar
                }

                if model.isProcessing { processingOverlay }
            }
        }
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.movie, .video], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                model.errorText = "The selected file could not be imported."
                return
            }
            let access = url.startAccessingSecurityScopedResource()
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("import_\(UUID().uuidString).\(ext)")
            do {
                try? FileManager.default.removeItem(at: copy)
                try FileManager.default.copyItem(at: url, to: copy)
                Task { await model.setInput(url: copy) }
            } catch {
                model.errorText = "The selected file could not be imported."
            }
            if access { url.stopAccessingSecurityScopedResource() }
        }
        .sheet(item: Binding(get: { shareURL.map(URLItem.init) }, set: { _ in shareURL = nil })) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(item: Binding(get: { previewURL.map(URLItem.init) }, set: { _ in previewURL = nil })) { item in
            NavigationStack {
                VideoPlayer(player: AVPlayer(url: item.url))
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Preview")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert("Couldn’t convert", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.errorText ?? "")
        }
        .alert("Saved to Photos", isPresented: $model.showSaved) {
            Button("OK", role: .cancel) { }
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

    private func sidePadding(_ width: CGFloat) -> CGFloat {
        width < 360 ? 12 : (width < 430 ? 16 : 20)
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .frame(width: 42, height: 42)
                .overlay(Image(systemName: "waveform.path.ecg.rectangle.fill").foregroundStyle(.black).font(.system(size: 18, weight: .bold)))

            VStack(alignment: .leading, spacing: 1) {
                Text("ScreenFlow").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("FPS + AI Video Enhancer").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !library.items.isEmpty {
                Text("\(library.items.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.08))
                    .clipShape(Capsule())
            }
        }
    }

    private func converter(width: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if let info = model.input {
                    sourceCard(info)
                    fpsCard
                    qualityCard
                    engineCard
                    motionCard
                    if let notice = model.noticeText { noticeCard(notice) }
                    convertButton
                    if let out = model.output { resultCard(out) }
                } else {
                    emptyState(width: width)
                }
                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, sidePadding(width))
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }

    private func emptyState(width: CGFloat) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 10)
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: width < 380 ? 104 : 124, height: width < 380 ? 104 : 124)
                .overlay(Image(systemName: "video.badge.plus").font(.system(size: width < 380 ? 42 : 52, weight: .medium)))

            VStack(spacing: 8) {
                Text("Add a video")
                    .font(.system(size: width < 380 ? 30 : 36, weight: .bold, design: .rounded))
                Text("Increase FPS, improve quality, and keep every finished export inside ScreenFlow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .videos) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                Button { showFileImporter = true } label: {
                    Label("Files", systemImage: "folder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 520)

            HStack(spacing: 10) {
                capability("120 FPS", "gauge.with.dots.needle.100percent")
                capability("4K", "4k.tv")
                capability("AI", "brain.head.profile")
            }
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: width < 380 ? 430 : 500)
    }

    private func capability(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private func sourceCard(_ info: VideoModel.Info) -> some View {
        HStack(spacing: 14) {
            Button { previewURL = info.url } label: {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.07))
                    .frame(width: 68, height: 68)
                    .overlay(Image(systemName: "play.fill").font(.title3))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(info.name).font(.headline).lineLimit(1)
                Text("\(info.resolutionText) · \(info.fpsText)").font(.subheadline).foregroundStyle(.secondary)
                Text("\(info.durationText) · \(info.sizeText)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.clearInput() } label: {
                Image(systemName: "xmark").frame(width: 38, height: 38).background(.white.opacity(0.06)).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(panel)
    }

    private var fpsCard: some View {
        section("Frame rate", "Choose the final motion rate") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(model.fpsOptions, id: \.self) { fps in
                    Button { model.targetFPS = fps } label: {
                        VStack(spacing: 2) {
                            Text("\(fps)").font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("FPS").font(.caption2.bold()).opacity(0.5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(model.targetFPS == fps ? .white : .white.opacity(0.055))
                        .foregroundStyle(model.targetFPS == fps ? .black : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var qualityCard: some View {
        section("Resolution", "Preserves aspect ratio") {
            HStack(spacing: 8) {
                ForEach(VideoModel.Quality.allCases) { q in
                    Button { model.quality = q } label: {
                        VStack(spacing: 3) {
                            Text(q.rawValue).font(.headline)
                            Text(q == .enhanced ? "Native" : (q == .twoK ? "2560px" : "3840px")).font(.caption2).opacity(0.5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(model.quality == q ? .white : .white.opacity(0.055))
                        .foregroundStyle(model.quality == q ? .black : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var engineCard: some View {
        section("Upscaling", "AI falls back automatically if unsupported") {
            HStack(spacing: 10) {
                engineButton(.standard, title: "Standard", subtitle: "Fast & stable", icon: "sparkles")
                engineButton(.ai, title: "AI Super Resolution", subtitle: "Core ML", icon: "brain.head.profile")
            }
        }
    }

    private func engineButton(_ engine: VideoModel.UpscaleEngine, title: String, subtitle: String, icon: String) -> some View {
        Button { model.upscaleEngine = engine } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                    Spacer()
                    Image(systemName: model.upscaleEngine == engine ? "checkmark.circle.fill" : "circle")
                }
                Text(title).font(.subheadline.bold()).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(.white.opacity(model.upscaleEngine == engine ? 0.10 : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }

    private var motionCard: some View {
        section("Motion", "Smooth creates in-between frames") {
            HStack(spacing: 8) {
                ForEach(VideoModel.Mode.allCases) { m in
                    Button { model.mode = m } label: {
                        Label(m.rawValue, systemImage: m == .smooth ? "waveform.path" : "bolt.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(model.mode == m ? .white : .white.opacity(0.055))
                            .foregroundStyle(model.mode == m ? .black : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(.yellow)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(panel)
    }

    private var convertButton: some View {
        Button { Task { await model.convert(library: library) } } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("Convert · \(model.targetFPS) FPS · \(model.quality.rawValue)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(.headline)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(.white)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
    }

    private func resultCard(_ out: VideoModel.Info) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Saved in ScreenFlow").font(.headline)
                Spacer()
                Button("Library") { selectedTab = 1 }.font(.subheadline.bold())
            }
            Text("\(out.resolutionText) · \(out.fpsText) · \(out.sizeText)").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { previewURL = out.url } label: { Label("Preview", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 11) }
                Button { model.saveToPhotos() } label: { Label("Photos", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity).padding(.vertical, 11) }
                Button { shareURL = out.url } label: { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 11) }
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding(14)
        .background(panel)
    }

    @ViewBuilder
    private func libraryView(width: CGFloat) -> some View {
        if library.items.isEmpty {
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "tray.full").font(.system(size: 54)).foregroundStyle(.secondary)
                Text("No exports yet").font(.title2.bold())
                Text("Every successful conversion is saved here automatically.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(library.items) { item in
                        HStack(spacing: 12) {
                            Button { previewURL = library.url(for: item) } label: {
                                RoundedRectangle(cornerRadius: 13)
                                    .fill(.white.opacity(0.07))
                                    .frame(width: 62, height: 62)
                                    .overlay(Image(systemName: "play.fill"))
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline).lineLimit(1)
                                Text("\(item.resolutionText) · \(item.fpsText)").font(.subheadline).foregroundStyle(.secondary)
                                Text("\(item.durationText) · \(item.sizeText)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button { previewURL = library.url(for: item) } label: { Label("Preview", systemImage: "play") }
                                Button { shareURL = library.url(for: item) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                                Button { model.saveURLToPhotos(library.url(for: item)) } label: { Label("Save to Photos", systemImage: "photo") }
                                Button(role: .destructive) { library.delete(item) } label: { Label("Delete", systemImage: "trash") }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.title3)
                            }
                        }
                        .padding(13)
                        .background(panel)
                    }
                }
                .padding(.horizontal, sidePadding(width))
                .padding(.top, 2)
                .padding(.bottom, 12)
            }
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 8) {
            tabButton(0, "Convert", "wand.and.stars")
            tabButton(1, "Library", "tray.full")
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(.white.opacity(0.08)).frame(height: 1), alignment: .top)
    }

    private func tabButton(_ index: Int, _ title: String, _ icon: String) -> some View {
        Button { selectedTab = index } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(selectedTab == index ? .white.opacity(0.10) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    Circle().stroke(.white.opacity(0.10), lineWidth: 10)
                    Circle().trim(from: 0, to: max(0.015, model.progress)).stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(Int(model.progress * 100))%").font(.system(size: 34, weight: .bold, design: .rounded))
                }
                .frame(width: 148, height: 148)
                VStack(spacing: 8) {
                    Text(model.stageText).font(.title2.bold()).multilineTextAlignment(.center)
                    Text("Keep ScreenFlow open. Finished videos are saved to Library automatically.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func section<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(14)
        .background(panel)
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.white.opacity(0.045))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.075)))
    }
}

private struct URLItem: Identifiable {
    let id = UUID()
    let url: URL
}
