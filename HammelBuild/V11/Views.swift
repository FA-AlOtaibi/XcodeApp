import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private enum T {
    static let olive = Color(red: 0.28, green: 0.34, blue: 0.18)
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView(model: model)
                .tabItem { Label("تحميل", systemImage: "arrow.down.circle.fill") }
                .tag(0)
            LibraryView(model: model)
                .tabItem { Label("المكتبة", systemImage: "folder.fill") }
                .tag(1)
            DownloadsView(model: model)
                .tabItem { Label("التنزيلات", systemImage: "list.bullet.rectangle") }
                .tag(2)
            SettingsView(model: model)
                .tabItem { Label("الإعدادات", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(T.olive)
        .overlay(alignment: .top) {
            if let notice = model.notice {
                NoticeBanner(notice: notice)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.notice?.id)
    }
}

struct NoticeBanner: View {
    let notice: Notice
    var icon: String {
        switch notice.style {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
    var body: some View {
        Label(notice.text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(radius: 8, y: 3)
    }
}

struct HomeView: View {
    @ObservedObject var model: AppModel
    @State private var showDetails = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    HStack {
                        Text("مُحمّل").font(.system(size: 40, weight: .bold, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.down")
                            .font(.title2.bold())
                            .foregroundStyle(T.olive)
                            .frame(width: 52, height: 52)
                            .background(T.olive.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
                    }
                    .padding(.top, 12)

                    VStack(spacing: 8) {
                        Text("جاهز للتحميل").font(.title.bold())
                        Text("الصق الرابط فقط").foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("رابط الفيديو أو المنشور", text: $model.input)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Image(systemName: "link").foregroundStyle(.secondary)
                        }
                        .padding(17)
                        .background(T.olive.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))

                        Button {
                            model.input = UIPasteboard.general.string ?? ""
                        } label: {
                            Label("لصق من الحافظة", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        }

                        Button {
                            Task {
                                await model.resolve()
                                if !model.results.isEmpty { showDetails = true }
                            }
                        } label: {
                            HStack {
                                if model.isResolving { ProgressView().tint(.white) }
                                Text(model.isResolving ? "جاري التحليل" : "متابعة").font(.headline)
                                Image(systemName: "arrow.left")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(.white)
                            .background(T.olive, in: RoundedRectangle(cornerRadius: 22))
                        }
                        .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isResolving)
                    }

                    PlatformStrip()

                    if !model.library.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("الأخيرة").font(.headline)
                                Spacer()
                                Text("\(model.library.count) ملف").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(model.library.prefix(3)) { item in
                                CompactMediaRow(item: item, model: model)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationDestination(isPresented: $showDetails) {
                ResolveDetailsView(model: model)
            }
        }
    }
}

struct PlatformStrip: View {
    var body: some View {
        HStack(spacing: 22) {
            ForEach([("play.rectangle.fill", "YouTube"), ("music.note", "TikTok"), ("camera.fill", "Instagram"), ("xmark", "X")], id: \.1) { item in
                VStack(spacing: 7) {
                    Image(systemName: item.0)
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .background(.thinMaterial, in: Circle())
                    Text(item.1).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ResolveDetailsView: View {
    @ObservedObject var model: AppModel
    @State private var selected: DownloadMedia?
    @State private var name = ""
    @State private var save: SaveTarget = .app

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let first = model.results.first {
                    PreviewRemote(item: first)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(first.filename).font(.headline).lineLimit(2)
                        Text("\(first.platform.rawValue) • \(model.results.count > 1 ? "\(model.results.count) عناصر" : first.type)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if model.results.first?.platform == .youtube {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("الجودة").font(.headline)
                        ForEach(model.results) { media in
                            Button {
                                selected = media
                                name = (media.filename as NSString).deletingPathExtension
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(media.quality).fontWeight(.semibold)
                                        if let size = media.estimatedSize {
                                            Text(model.formattedBytes(size)).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selected?.id == media.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(T.olive)
                                    }
                                }
                                .padding(13)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if model.results.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.results) { media in
                                Button {
                                    selected = media
                                    name = (media.filename as NSString).deletingPathExtension
                                } label: {
                                    VStack {
                                        PreviewRemote(item: media)
                                            .frame(width: 92, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                        Text(media.quality).font(.caption2)
                                    }
                                    .padding(6)
                                    .background(selected?.id == media.id ? T.olive.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
                    TextField("اسم الملف", text: $name)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    Picker("الحفظ", selection: $save) {
                        Text("داخل التطبيق").tag(SaveTarget.app)
                        Text("الصور").tag(SaveTarget.photos)
                    }
                    .pickerStyle(.segmented)
                }

                Button {
                    guard let item = selected ?? model.results.first else { return }
                    Task { await model.enqueue(item, filename: name.isEmpty ? nil : name, target: save) }
                } label: {
                    Label("بدء التحميل", systemImage: "arrow.down.to.line")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(T.olive, in: RoundedRectangle(cornerRadius: 20))
                }
                .disabled(model.results.isEmpty)

                if model.results.count > 1 && model.results.first?.platform != .youtube {
                    Button {
                        Task {
                            for (index, media) in model.results.enumerated() {
                                await model.enqueue(media, filename: "media-\(index + 1)", target: save)
                            }
                        }
                    } label: {
                        Text("تحميل الكل")
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("التفاصيل")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selected = model.results.first
            name = model.results.first.map { ($0.filename as NSString).deletingPathExtension } ?? ""
            save = model.saveTarget == .ask ? .app : model.saveTarget
        }
    }
}

struct PreviewRemote: View {
    let item: DownloadMedia
    var body: some View {
        ZStack {
            Color.black
            if let thumb = item.thumb {
                AsyncImage(url: thumb) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ProgressView().tint(.white)
                    }
                }
            } else {
                Image(systemName: item.type == "photo" ? "photo.fill" : "play.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

struct DownloadsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if model.jobs.isEmpty {
                        ContentUnavailableView("لا توجد تنزيلات", systemImage: "arrow.down.circle", description: Text("التنزيلات الجديدة تظهر هنا"))
                    } else {
                        ForEach(model.jobs) { job in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(job.item.filename).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text(job.state.rawValue).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: job.state == .done ? "checkmark.circle.fill" : job.state == .failed ? "exclamationmark.circle.fill" : "arrow.down.circle")
                                        .foregroundStyle(job.state == .done ? T.olive : job.state == .failed ? .red : .secondary)
                                }
                                ProgressView(value: job.progress).tint(T.olive)
                                if let error = job.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                            }
                            .padding(14)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("التنزيلات")
        }
    }
}

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""
    @State private var filter: MediaFilter = .all
    @State private var sort: SortMode = .newest
    @State private var grid = true
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var importingFile = false

    var filtered: [LocalMedia] {
        var items = model.library.filter { search.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(search) }
        switch filter {
        case .all: break
        case .image: items = items.filter { $0.isImage }
        case .video: items = items.filter { $0.isVideo }
        case .audio: items = items.filter { $0.isAudio }
        case .document: items = items.filter { !$0.isImage && !$0.isVideo && !$0.isAudio }
        }
        switch sort {
        case .newest: items.sort { $0.createdAt > $1.createdAt }
        case .oldest: items.sort { $0.createdAt < $1.createdAt }
        case .name: items.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }
        case .size: items.sort { $0.size > $1.size }
        }
        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        TextField("بحث", text: $search)
                            .padding(13)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        Menu {
                            ForEach(SortMode.allCases) { mode in Button(mode.rawValue) { sort = mode } }
                            Button(grid ? "عرض قائمة" : "عرض شبكة") { grid.toggle() }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .frame(width: 44, height: 44)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(MediaFilter.allCases) { f in
                                Button(f.rawValue) { filter = f }
                                    .buttonStyle(.borderedProminent)
                                    .tint(filter == f ? T.olive : Color.gray.opacity(0.22))
                                    .foregroundStyle(filter == f ? .white : .primary)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                            Label("استيراد من الصور", systemImage: "photo.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(T.olive)

                        Button { importingFile = true } label: {
                            Label("ملف", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                    }

                    if filtered.isEmpty {
                        ContentUnavailableView("المكتبة فارغة", systemImage: "folder", description: Text("استورد أو نزّل محتوى ليظهر هنا"))
                    } else if grid {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(filtered) { media in
                                NavigationLink {
                                    MediaDetailView(model: model, item: media)
                                } label: {
                                    MediaGridCard(item: media, model: model)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { media in
                                NavigationLink {
                                    MediaDetailView(model: model, item: media)
                                } label: {
                                    CompactMediaRow(item: media, model: model)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("المكتبة")
            .onAppear { model.refreshStorage() }
            .onChange(of: pickerItems) { _, newItems in
                Task {
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            model.importImageData(data, ext: "jpg")
                        }
                    }
                    pickerItems = []
                }
            }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.movie, .image, .audio, .pdf, .data], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { urls.forEach(model.importFile) }
            }
        }
    }
}

struct MediaGridCard: View {
    let item: LocalMedia
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalThumb(item: item).frame(height: 125).clipShape(RoundedRectangle(cornerRadius: 17))
            Text(item.url.deletingPathExtension().lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(model.formattedBytes(item.size)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct CompactMediaRow: View {
    let item: LocalMedia
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            LocalThumb(item: item).frame(width: 62, height: 55).clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(model.formattedBytes(item.size)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.left").foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section("المظهر") {
                    Picker("الوضع", selection: Binding(get: { model.appearance }, set: model.setAppearance)) {
                        ForEach(AppearanceMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("الحفظ") {
                    Picker("المكان الافتراضي", selection: Binding(get: { model.saveTarget }, set: model.setSaveTarget)) {
                        ForEach(SaveTarget.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                Section("المساحة") {
                    LabeledContent("المكتبة", value: model.formattedBytes(model.libraryBytes))
                    LabeledContent("الكاش", value: model.formattedBytes(model.cacheBytes))
                    Button("حذف الكاش") { model.clearCache() }
                    Button("حذف الملفات الأقدم من 30 يومًا") { model.deleteOlderThan30Days() }
                    Button("حذف الملفات المكررة") { model.removeDuplicates() }
                    Button("حذف جميع ملفات التطبيق", role: .destructive) { confirmAll = true }
                }

                Section { Text("مُحمّل 1.1").foregroundStyle(.secondary) }
            }
            .navigationTitle("الإعدادات")
            .onAppear { model.refreshStorage() }
            .confirmationDialog("حذف جميع الملفات؟", isPresented: $confirmAll) {
                Button("حذف الكل", role: .destructive) { model.deleteAllAppFiles() }
            }
        }
    }
}
