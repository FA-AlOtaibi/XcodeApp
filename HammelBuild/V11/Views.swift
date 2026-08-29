import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private enum T { static let olive = Color(red: 0.27, green: 0.33, blue: 0.18) }

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView(model: model)
                .tabItem { Label("تحميل", systemImage: "arrow.down.circle.fill") }.tag(0)
            LibraryView(model: model)
                .tabItem { Label("المكتبة", systemImage: "folder.fill") }.tag(1)
            DownloadsView(model: model)
                .tabItem { Label("التنزيلات", systemImage: "list.bullet.rectangle") }.tag(2)
            SettingsView(model: model)
                .tabItem { Label("الإعدادات", systemImage: "gearshape.fill") }.tag(3)
        }
        .tint(T.olive)
        .overlay(alignment: .top) {
            if let n = model.notice {
                NoticeBanner(notice: n)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.notice?.id)
        .onAppear { model.purgeExpiredTrash() }
    }
}

struct NoticeBanner: View {
    let notice: Notice
    private var icon: String {
        notice.style == .success ? "checkmark.circle.fill" : notice.style == .error ? "exclamationmark.circle.fill" : "info.circle.fill"
    }
    var body: some View {
        Label(notice.text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 11)
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
                VStack(spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("مُحمّل").font(.system(size: 39, weight: .bold, design: .rounded))
                            Text("نزّل. رتّب. استخدم.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.down")
                            .font(.title2.bold()).foregroundStyle(T.olive)
                            .frame(width: 52, height: 52)
                            .background(T.olive.opacity(0.11), in: RoundedRectangle(cornerRadius: 17))
                    }.padding(.top, 10)

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("ألصق رابطًا", text: $model.input)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Image(systemName: "link").foregroundStyle(.secondary)
                        }
                        .padding(17)
                        .background(T.olive.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))

                        HStack(spacing: 10) {
                            Button { model.input = UIPasteboard.general.string ?? "" } label: {
                                Label("لصق", systemImage: "doc.on.clipboard")
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                            }
                            Button {
                                Task {
                                    await model.resolve()
                                    if !model.results.isEmpty { showDetails = true }
                                }
                            } label: {
                                HStack {
                                    if model.isResolving { ProgressView().tint(.white) }
                                    Text(model.isResolving ? "تحليل…" : "متابعة").fontWeight(.semibold)
                                    Image(systemName: "arrow.left")
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(T.olive, in: RoundedRectangle(cornerRadius: 18))
                            }
                            .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isResolving)
                        }
                    }

                    PlatformStrip()

                    if !model.library.isEmpty {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Text("الأخيرة").font(.headline)
                                Spacer()
                                Text("\(model.library.count) ملف").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(model.library.prefix(3)) { item in
                                NavigationLink { MediaDetailView(model: model, item: item) } label: {
                                    CompactMediaRow(item: item, model: model)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationDestination(isPresented: $showDetails) { ResolveDetailsView(model: model) }
        }
    }
}

struct PlatformStrip: View {
    var body: some View {
        HStack(spacing: 21) {
            ForEach([("play.rectangle.fill","YouTube"),("music.note","TikTok"),("camera.fill","Instagram"),("xmark","X")], id: \.1) { x in
                VStack(spacing: 7) {
                    Image(systemName: x.0).font(.title3)
                        .frame(width: 48,height: 48).background(.thinMaterial,in: Circle())
                    Text(x.1).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity)
    }
}

struct ResolveDetailsView: View {
    @ObservedObject var model: AppModel
    @State private var selected: DownloadMedia?
    @State private var name = ""
    @State private var save: SaveTarget = .app

    private var current: DownloadMedia? { selected ?? model.results.first }
    private var currentJob: DownloadJob? {
        guard let current else { return nil }
        return model.jobs.first { $0.item.url == current.url }
    }
    private var isDownloading: Bool { currentJob?.state == .downloading || currentJob?.state == .waiting }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let first = model.results.first {
                    PreviewRemote(item: first).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 24))
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text((first.filename as NSString).deletingPathExtension).font(.headline).lineLimit(2)
                            Text("\(first.platform.rawValue) • \(model.results.count > 1 ? "\(model.results.count) خيارات" : first.type)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                if model.results.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(model.results.first?.platform == .youtube ? "اختر الجودة" : "اختر العنصر").font(.headline)
                            Spacer()
                            if model.results.first?.platform == .youtube {
                                Text("حتى أعلى جودة متاحة").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(model.results) { media in
                            Button {
                                guard !isDownloading else { return }
                                selected = media
                                name = (media.filename as NSString).deletingPathExtension
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(media.quality).fontWeight(.semibold)
                                        if let size = media.estimatedSize {
                                            Text(model.formattedBytes(size)).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selected?.id == media.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(T.olive) }
                                }
                                .padding(13).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }
                }

                VStack(spacing: 12) {
                    TextField("اسم الملف", text: $name)
                        .padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .disabled(isDownloading)
                    Picker("الحفظ", selection: $save) {
                        Text("المكتبة").tag(SaveTarget.app)
                        Text("الصور").tag(SaveTarget.photos)
                    }.pickerStyle(.segmented).disabled(isDownloading)
                }

                Button {
                    guard let item = current else { return }
                    Task { await model.enqueueSmart(item, filename: name.isEmpty ? nil : name, target: save) }
                } label: {
                    HStack {
                        if isDownloading { ProgressView().tint(.white) }
                        Label(isDownloading ? "جارٍ التحميل" : "بدء التحميل", systemImage: "arrow.down.to.line")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(isDownloading ? T.olive.opacity(0.65) : T.olive, in: RoundedRectangle(cornerRadius: 20))
                }.disabled(isDownloading)

                if let job = currentJob {
                    DownloadProgressCard(job: job)
                }

                if model.results.count > 1 && model.results.first?.platform != .youtube {
                    Button {
                        Task { for (i,m) in model.results.enumerated() { await model.enqueueSmart(m, filename: "media-\(i+1)", target: save) } }
                    } label: {
                        Text("تحميل الكل").frame(maxWidth: .infinity).padding(14)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }.disabled(isDownloading)
                }
            }.padding(20)
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

struct DownloadProgressCard: View {
    let job: DownloadJob
    private var pct: Int { Int(max(0, min(1, job.progress)) * 100) }
    private var text: String {
        if job.state == .done { return "اكتمل التنزيل" }
        if job.state == .failed { return job.error ?? "تعذر إكمال العملية" }
        if job.progress < 0.55 { return "تنزيل الملف…" }
        if job.progress < 0.80 { return "تجهيز الصوت…" }
        if job.progress < 0.97 { return "معالجة الملف…" }
        return "إنهاء الحفظ…"
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: job.state == .done ? "checkmark.circle.fill" : job.state == .failed ? "exclamationmark.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(job.state == .failed ? .red : T.olive)
                Text(text).font(.subheadline.weight(.semibold))
                Spacer()
                if job.state == .downloading { Text("\(pct)%").font(.subheadline.monospacedDigit()) }
            }
            ProgressView(value: job.state == .done ? 1 : job.progress).tint(T.olive)
        }
        .padding(15)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct PreviewRemote: View {
    let item: DownloadMedia
    var body: some View {
        ZStack {
            Color.black
            if let t = item.thumb {
                AsyncImage(url: t) { p in
                    if let im = p.image { im.resizable().scaledToFill() }
                    else { ProgressView().tint(.white) }
                }
            } else {
                Image(systemName: item.type == "photo" ? "photo.fill" : "play.fill")
                    .font(.system(size: 48)).foregroundStyle(.white.opacity(0.8))
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
                        ForEach(model.jobs) { j in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(j.item.filename).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text(j.state.rawValue).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: j.state == .done ? "checkmark.circle.fill" : j.state == .failed ? "exclamationmark.circle.fill" : "arrow.down.circle")
                                        .foregroundStyle(j.state == .done ? T.olive : j.state == .failed ? .red : .secondary)
                                }
                                ProgressView(value: j.progress).tint(T.olive)
                                if let e = j.error { Text(e).font(.caption).foregroundStyle(.secondary) }
                            }
                            .padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }.padding(20)
            }.navigationTitle("التنزيلات")
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
    @State private var actionItem: LocalMedia?

    private var filtered: [LocalMedia] {
        var a = model.library.filter { search.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(search) }
        switch filter {
        case .all: break
        case .image: a = a.filter { $0.isImage || $0.ext == "gif" }
        case .video: a = a.filter { $0.isVideo }
        case .audio: a = a.filter { $0.isAudio }
        case .document: a = a.filter { !$0.isImage && !$0.isVideo && !$0.isAudio && $0.ext != "gif" }
        }
        switch sort {
        case .newest: a.sort { $0.createdAt > $1.createdAt }
        case .oldest: a.sort { $0.createdAt < $1.createdAt }
        case .name: a.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }
        case .size: a.sort { $0.size > $1.size }
        }
        return a
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    HStack {
                        TextField("بحث", text: $search)
                            .padding(13).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        Menu {
                            ForEach(SortMode.allCases) { m in Button(m.rawValue) { sort = m } }
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
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .any(of: [.images,.videos])) {
                            Label("من الصور", systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(T.olive)
                        Button { importingFile = true } label: {
                            Label("من الملفات", systemImage: "folder.badge.plus")
                        }.buttonStyle(.bordered)
                    }

                    if filtered.isEmpty {
                        ContentUnavailableView("المكتبة فارغة", systemImage: "folder", description: Text("نزّل أو استورد محتوى"))
                    } else if grid {
                        LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())], spacing: 12) {
                            ForEach(filtered) { m in
                                LibraryGridItem(model: model, item: m) { actionItem = m }
                            }
                        }
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { m in
                                LibraryListItem(model: model, item: m) { actionItem = m }
                            }
                        }
                    }
                }.padding(16)
            }
            .navigationTitle("المكتبة")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { TrashView(model: model) } label: { Image(systemName: "trash") }
                }
            }
            .onAppear { model.refreshStorage(); model.purgeExpiredTrash() }
            .onChange(of: pickerItems) { _, new in
                Task {
                    for p in new {
                        if let d = try? await p.loadTransferable(type: Data.self) { model.importImageData(d, ext: "jpg") }
                    }
                    pickerItems = []
                }
            }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.movie,.image,.audio,.pdf,.data], allowsMultipleSelection: true) { r in
                if case .success(let urls) = r { urls.forEach(model.importFile) }
            }
            .sheet(item: $actionItem) { item in MediaQuickActionsSheet(model: model, item: item) }
        }
    }
}

struct LibraryGridItem: View {
    @ObservedObject var model: AppModel
    let item: LocalMedia
    let actions: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                NavigationLink { MediaDetailView(model: model, item: item) } label: {
                    LocalThumb(item: item).frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain)
                Button(action: actions) {
                    Image(systemName: "ellipsis").font(.headline)
                        .frame(width: 36, height: 32)
                        .background(.ultraThinMaterial, in: Capsule())
                }.padding(8)
            }
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.url.deletingPathExtension().lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(model.formattedBytes(item.size)).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 8).padding(.vertical, 9)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct LibraryListItem: View {
    @ObservedObject var model: AppModel
    let item: LocalMedia
    let actions: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            NavigationLink { MediaDetailView(model: model, item: item) } label: {
                HStack(spacing: 12) {
                    LocalThumb(item: item).frame(width: 62, height: 55).clipShape(RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.url.lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(model.formattedBytes(item.size)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.buttonStyle(.plain)
            Spacer()
            Button(action: actions) { Image(systemName: "ellipsis").frame(width: 40, height: 40) }
        }
        .padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
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
        }.padding(9).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct CompactMediaRow: View {
    let item: LocalMedia
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            LocalThumb(item: item).frame(width: 62,height: 55).clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(model.formattedBytes(item.size)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.left").foregroundStyle(.secondary)
        }.padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
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
                    }.pickerStyle(.segmented)
                }
                Section("الحفظ") {
                    Picker("المكان الافتراضي", selection: Binding(get: { model.saveTarget }, set: model.setSaveTarget)) {
                        ForEach(SaveTarget.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("المساحة") {
                    LabeledContent("المكتبة", value: model.formattedBytes(model.libraryBytes))
                    LabeledContent("الكاش", value: model.formattedBytes(model.cacheBytes))
                    NavigationLink("سلة المهملات") { TrashView(model: model) }
                    Button("حذف الكاش") { model.clearCache() }
                    Button("حذف الملفات الأقدم من 30 يومًا") { model.deleteOlderThan30Days() }
                    Button("حذف الملفات المكررة") { model.removeDuplicates() }
                    Button("حذف جميع ملفات التطبيق", role: .destructive) { confirmAll = true }
                }
                Section("حول") {
                    Text("مُحمّل 1.5 • الأدوات أصبحت مرتبطة بكل ملف مباشرة").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("الإعدادات")
            .onAppear { model.refreshStorage() }
            .confirmationDialog("حذف جميع الملفات؟", isPresented: $confirmAll) {
                Button("حذف الكل", role: .destructive) { model.deleteAllAppFiles() }
            }
        }
    }
}
