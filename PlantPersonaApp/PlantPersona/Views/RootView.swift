import SwiftUI
import UIKit
import PhotosUI

struct RootView: View {
    @EnvironmentObject private var app: AppState

    @State private var mode: AYNMode = .see
    @State private var showCamera = false
    @State private var showProfiles = false
    @State private var showOBD = false
    @State private var showSettings = false

    @State private var photoItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var compareItems: [PhotosPickerItem] = []
    @State private var compareImages: [Data] = []
    @State private var isLoadingMedia = false

    @State private var question = ""
    @State private var technicianText = ""
    @State private var newProfileName = ""
    @State private var useCurrentContext = true

    var body: some View {
        NavigationStack {
            ZStack {
                warmBackground
                ScrollView {
                    VStack(spacing: 14) {
                        header
                        modeContent

                        if isLoadingMedia || app.isAnalyzing { loadingPill }
                        if let error = app.errorMessage { errorCard(error) }
                        if let answer = app.assistantAnswer { answerCard(answer) }
                        if let step = app.guidedStep, !step.isEmpty { guidedCard(step) }
                        if let compare = app.compareResult { noteCard(title: "المقارنة", icon: "arrow.left.arrow.right", text: compare) }
                        if let result = app.analysis { resultCard(result) }
                    }
                    .padding(.horizontal, 17)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomDock }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onImage: handleImage).ignoresSafeArea()
        }
        .sheet(isPresented: $showProfiles) { profilesSheet }
        .sheet(isPresented: $showOBD) { NavigationStack { OBDView() } }
        .sheet(isPresented: $showSettings) { SettingsView(embedInNavigation: false) }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            Task { await loadVideo(item) }
        }
        .onChange(of: compareItems) { _, items in Task { await loadCompare(items) } }
    }

    private var warmBackground: some View {
        ZStack {
            Color.aynGraphite.ignoresSafeArea()
            LinearGradient(
                colors: [Color.aynGraphite2.opacity(0.8), Color.aynGraphite, Color.black.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            Circle()
                .fill(Color.aynLime.opacity(0.065))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: 170, y: -280)
                .allowsHitTesting(false)
            Circle()
                .fill(Color.aynClay.opacity(0.055))
                .frame(width: 420, height: 420)
                .blur(radius: 100)
                .offset(x: -190, y: 340)
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AYNMark(size: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text("عَيْن")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Color.aynIvory)
                Text(selectedProfile?.name ?? modeSubtitle)
                    .font(.caption)
                    .foregroundStyle(Color.aynIvory.opacity(0.52))
                    .lineLimit(1)
            }
            Spacer()
            headerIcon("tray.full.fill") { showProfiles = true }
            headerIcon("gearshape.fill") { showSettings = true }
        }
        .padding(.vertical, 3)
    }

    private func headerIcon(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 0.7))
                .foregroundStyle(Color.aynIvory)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var bottomDock: some View {
        HStack(spacing: 5) {
            ForEach(AYNMode.allCases) { item in
                Button {
                    app.clearTransientResults()
                    withAnimation(.easeInOut(duration: 0.18)) { mode = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icon(for: item))
                            .font(.system(size: 16, weight: .semibold))
                        Text(item.rawValue)
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 55)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AYNPressStyle(selected: mode == item))
            }
        }
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.11), lineWidth: 0.7) }
        .padding(.horizontal, 16)
        .padding(.bottom, 5)
        .shadow(color: .black.opacity(0.30), radius: 24, y: 12)
    }

    @ViewBuilder private var modeContent: some View {
        switch mode {
        case .see: seeMode
        case .inspect: inspectMode
        case .car: carMode
        case .ask: askMode
        }
    }

    private var seeMode: some View {
        VStack(spacing: 11) {
            mediaHero
            mediaButtons
        }
    }

    private var inspectMode: some View {
        VStack(spacing: 11) {
            titleLine("افحص", detail: "قبل وبعد أو لقطة إضافية")
            mediaButtons

            PhotosPicker(selection: $compareItems, maxSelectionCount: 6, matching: .images) {
                rowAction(
                    title: "مقارنة صور",
                    value: compareImages.count >= 2 ? "\(compareImages.count) جاهزة" : "قبل / بعد",
                    icon: "rectangle.2.swap"
                )
            }
            .buttonStyle(.plain)

            if compareImages.count >= 2 {
                Button {
                    Task { await app.compare(images: compareImages, prompt: "قارن الصور بالترتيب. اذكر التغيرات المهمة فقط وهل يوجد تحسن أو تدهور.") }
                } label: { solidAction("ابدأ المقارنة", icon: "arrow.triangle.2.circlepath") }
                .buttonStyle(.plain)
            }

            Button {
                Task { await app.nextGuidedStep(mode: "فحص عام") }
            } label: {
                rowAction(title: "لقطة أدق", value: app.analysis == nil ? "بعد أول تحليل" : "وش أصوّر بعد؟", icon: "camera.viewfinder")
            }
            .buttonStyle(.plain)
            .disabled(app.analysis == nil || app.isAnalyzing)
        }
    }

    private var carMode: some View {
        VStack(spacing: 11) {
            titleLine("السيارة", detail: "صورة، صوت، وبيانات OBD")
            mediaButtons

            HStack(spacing: 9) {
                Button { showOBD = true } label: { smallAction("OBD", icon: "cable.connector") }
                    .buttonStyle(.plain)
                PhotosPicker(selection: $videoItem, matching: .videos) {
                    smallAction("صوت / فيديو", icon: "waveform")
                }
                .buttonStyle(.plain)
            }

            AYNPanel {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("وش قال الفني؟", text: $technicianText, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color.aynIvory)
                    if !technicianText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            Task { await app.reviewTechnician(technicianText) }
                        } label: { solidAction("راجع كلامه", icon: "checkmark.seal") }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var askMode: some View {
        VStack(spacing: 11) {
            titleLine("اسأل", detail: "سؤال عادي أو عن آخر تحليل")
            AYNPanel {
                VStack(spacing: 12) {
                    TextField("اكتب أي سؤال…", text: $question, axis: .vertical)
                        .lineLimit(3...8)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundStyle(Color.aynIvory)
                    HStack {
                        if app.analysis != nil || app.obd.lastResult != nil {
                            Toggle("استخدم السياق", isOn: $useCurrentContext)
                                .font(.caption)
                                .tint(Color.aynLime)
                        }
                        Spacer()
                        Button {
                            let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !q.isEmpty else { return }
                            question = ""
                            Task { await app.ask(q, useCurrentContext: useCurrentContext) }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .black))
                                .frame(width: 42, height: 42)
                                .background(Color.aynLime, in: Circle())
                                .foregroundStyle(Color.aynGraphite)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.isAnalyzing)
                    }
                }
            }

            if app.analysis != nil {
                HStack(spacing: 7) {
                    quickAsk("اشرح أبسط")
                    quickAsk("وش أفحص؟")
                    quickAsk("هل طبيعي؟")
                }
            }
        }
    }

    private var mediaHero: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let data = app.selectedImageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.aynGraphite2
                        VStack(spacing: 12) {
                            Image(systemName: "camera.aperture")
                                .font(.system(size: 46, weight: .light))
                                .foregroundStyle(Color.aynLime)
                            Text("صوّر شيء")
                                .font(.headline)
                                .foregroundStyle(Color.aynIvory)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 285)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 27).stroke(.white.opacity(0.12), lineWidth: 0.8) }

            if app.selectedImageData != nil {
                Button {
                    app.reset()
                } label: {
                    Label("مسح", systemImage: "xmark")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(.regularMaterial, in: Capsule())
                        .foregroundStyle(Color.aynIvory)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
    }

    private var mediaButtons: some View {
        HStack(spacing: 8) {
            Button { showCamera = true } label: { mediaButton("كاميرا", "camera.fill", accent: true) }
                .buttonStyle(.plain)
            PhotosPicker(selection: $photoItem, matching: .images) { mediaButton("صورة", "photo.fill", accent: false) }
                .buttonStyle(.plain)
            PhotosPicker(selection: $videoItem, matching: .videos) { mediaButton("فيديو", "video.fill", accent: false) }
                .buttonStyle(.plain)
        }
    }

    private func mediaButton(_ title: String, _ icon: String, accent: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(accent ? Color.aynIvory : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 17))
            .foregroundStyle(accent ? Color.aynGraphite : Color.aynIvory)
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(accent ? 0.22 : 0.10), lineWidth: 0.7) }
            .contentShape(Rectangle())
    }

    private var loadingPill: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Color.aynLime)
            Text(isLoadingMedia ? "جاري تجهيز الوسائط" : "جاري التحليل")
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(Color.aynIvory)
        .padding(.horizontal, 15)
        .frame(height: 48)
        .background(.ultraThinMaterial, in: Capsule())
        .allowsHitTesting(false)
    }

    private func resultCard(_ result: VisualAnalysis) -> some View {
        AYNPanel(padding: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.aynLime)
                        Text(result.title)
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.aynIvory)
                        Text(result.summary)
                            .font(.body)
                            .foregroundStyle(Color.aynIvory.opacity(0.76))
                            .lineSpacing(3)
                    }
                    Spacer(minLength: 12)
                    VStack(spacing: 1) {
                        Text("\(result.confidence)%").font(.headline.monospacedDigit())
                        Text("ثقة").font(.caption2)
                    }
                    .foregroundStyle(Color.aynGraphite)
                    .frame(width: 58, height: 58)
                    .background(Color.aynLime, in: Circle())
                }

                if let geo = result.geo, geo.confidence > 0 { geoRow(geo) }
                if let auto = result.automotive, auto.isVehicleRelated { automotiveRow(auto) }
                if !result.keyFacts.isEmpty { cleanList(Array(result.keyFacts.prefix(4))) }
                if !result.cautions.isEmpty { warningList(Array(result.cautions.prefix(3))) }
                if let uncertainty = result.uncertainty, !uncertainty.isEmpty {
                    Text(uncertainty)
                        .font(.caption)
                        .foregroundStyle(Color.aynIvory.opacity(0.45))
                }
            }
        }
    }

    private func geoRow(_ geo: GeoEstimate) -> some View {
        let place = [geo.landmark, geo.area, geo.city, geo.country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "، ")
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: "location.fill").foregroundStyle(Color.aynClay)
            VStack(alignment: .leading, spacing: 3) {
                Text(place.isEmpty ? "مكان محتمل" : place).font(.subheadline.bold())
                if !geo.evidence.isEmpty {
                    Text(geo.evidence.prefix(2).joined(separator: " • ")).font(.caption).foregroundStyle(Color.aynIvory.opacity(0.48))
                }
            }
            Spacer()
            Text("\(geo.confidence)%").font(.caption.bold().monospacedDigit()).foregroundStyle(Color.aynClay)
        }
        .foregroundStyle(Color.aynIvory)
        .padding(13)
        .background(Color.aynClay.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }

    private func automotiveRow(_ a: AutomotiveDiagnostic) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "car.fill").foregroundStyle(Color.aynLime)
            VStack(alignment: .leading, spacing: 4) {
                Text(a.probableSystem ?? "تشخيص السيارة").font(.subheadline.bold())
                if let cause = a.likelyCauses.first { Text("الأرجح: \(cause.cause) · \(cause.probability)%").font(.caption).foregroundStyle(Color.aynIvory.opacity(0.56)) }
                if let check = a.checks.first { Text("ابدأ بـ: \(check)").font(.caption).foregroundStyle(Color.aynIvory.opacity(0.56)) }
            }
            Spacer()
            if let drive = a.canDrive { Text(drive).font(.caption.bold()).foregroundStyle(drive == "لا" ? Color.aynClay : Color.aynLime) }
        }
        .foregroundStyle(Color.aynIvory)
        .padding(13)
        .background(Color.aynLime.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func cleanList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 9) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.aynLime).frame(width: 5, height: 5).padding(.top, 7)
                    Text(item).font(.subheadline).foregroundStyle(Color.aynIvory.opacity(0.78))
                }
            }
        }
    }

    private func warningList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.circle.fill").font(.caption).foregroundStyle(Color.aynClay).padding(.top, 2)
                    Text(item).font(.subheadline).foregroundStyle(Color.aynIvory.opacity(0.76))
                }
            }
        }
    }

    private func answerCard(_ text: String) -> some View {
        noteCard(title: "عَيْن", icon: "bubble.left.fill", text: text)
    }

    private func guidedCard(_ text: String) -> some View {
        AYNPanel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "camera.viewfinder").foregroundStyle(Color.aynLime)
                VStack(alignment: .leading, spacing: 8) {
                    Text(text).foregroundStyle(Color.aynIvory)
                    Button { showCamera = true } label: { Text("افتح الكاميرا").font(.caption.bold()).foregroundStyle(Color.aynGraphite).padding(.horizontal, 12).frame(height: 34).background(Color.aynLime, in: Capsule()) }
                        .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private func noteCard(title: String, icon: String, text: String) -> some View {
        AYNPanel {
            VStack(alignment: .leading, spacing: 9) {
                Label(title, systemImage: icon).font(.headline).foregroundStyle(Color.aynLime)
                Text(text).foregroundStyle(Color.aynIvory.opacity(0.82)).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.aynClay)
            Text(message).font(.subheadline).foregroundStyle(Color.aynIvory.opacity(0.8))
            Spacer()
        }
        .padding(15)
        .background(Color.aynClay.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }

    private func titleLine(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.bold()).foregroundStyle(Color.aynIvory)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(Color.aynIvory.opacity(0.42))
        }
    }

    private func rowAction(title: String, value: String, icon: String) -> some View {
        AYNPanel {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Color.aynLime).frame(width: 32)
                Text(title).font(.headline).foregroundStyle(Color.aynIvory)
                Spacer()
                Text(value).font(.caption).foregroundStyle(Color.aynIvory.opacity(0.46))
                Image(systemName: "chevron.left").font(.caption).foregroundStyle(Color.aynIvory.opacity(0.35))
            }
            .contentShape(Rectangle())
        }
    }

    private func smallAction(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(Color.aynIvory)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.10), lineWidth: 0.7) }
            .contentShape(Rectangle())
    }

    private func solidAction(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.aynLime, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(Color.aynGraphite)
            .contentShape(Rectangle())
    }

    private func quickAsk(_ text: String) -> some View {
        Button { Task { await app.ask(text, useCurrentContext: true) } } label: {
            Text(text)
                .font(.caption.bold())
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(Color.aynIvory)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(app.isAnalyzing)
    }

    private var modeSubtitle: String {
        switch mode {
        case .see: return "شوف اللي قدامك"
        case .inspect: return "قارن وافحص"
        case .car: return "تشخيص السيارة"
        case .ask: return "اسأل أي شيء"
        }
    }

    private func icon(for mode: AYNMode) -> String {
        switch mode {
        case .see: return "viewfinder"
        case .inspect: return "scope"
        case .car: return "car.fill"
        case .ask: return "bubble.left.fill"
        }
    }

    private var selectedProfile: AYNProfile? {
        guard let id = app.selectedProfileID else { return nil }
        return app.workspace.profiles.first { $0.id == id }
    }

    private var profilesSheet: some View {
        NavigationStack {
            List {
                if !app.workspace.profiles.isEmpty {
                    Section("الملفات") {
                        ForEach(app.workspace.profiles) { profile in
                            Button {
                                app.selectedProfileID = profile.id
                                showProfiles = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(profile.name)
                                        Text(profile.kind).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if app.selectedProfileID == profile.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.aynLime) }
                                }
                            }
                        }
                    }
                }
                Section("ملف جديد") {
                    TextField("مثال: يوكن 2013", text: $newProfileName)
                    Button("إضافة") {
                        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let p = app.workspace.addProfile(name: name, kind: mode == .car ? "سيارة" : "عام")
                        app.selectedProfileID = p.id
                        newProfileName = ""
                        showProfiles = false
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if app.selectedProfileID != nil {
                    Section { Button("بدون ملف") { app.selectedProfileID = nil; showProfiles = false } }
                }
            }
            .navigationTitle("الملفات")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("تم") { showProfiles = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor private func loadPhoto(_ item: PhotosPickerItem) async {
        guard !isLoadingMedia else { return }
        isLoadingMedia = true
        defer { isLoadingMedia = false; photoItem = nil }
        do {
            guard let rawData = try await item.loadTransferable(type: Data.self), let image = UIImage(data: rawData), let data = ImageCompressor.jpegData(from: image) else {
                app.errorMessage = "تعذر فتح الصورة."
                return
            }
            app.selectedImageData = data
            await app.analyze(imageData: data)
        } catch { app.errorMessage = "تعذر فتح الصورة: \(error.localizedDescription)" }
    }

    @MainActor private func loadVideo(_ item: PhotosPickerItem) async {
        guard !isLoadingMedia else { return }
        isLoadingMedia = true
        defer { isLoadingMedia = false; videoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { app.errorMessage = "تعذر فتح الفيديو."; return }
            await app.analyzeVideo(data: data)
        } catch { app.errorMessage = "تعذر فتح الفيديو: \(error.localizedDescription)" }
    }

    @MainActor private func loadCompare(_ items: [PhotosPickerItem]) async {
        guard !isLoadingMedia else { return }
        isLoadingMedia = true
        compareImages = []
        defer { isLoadingMedia = false }
        for item in items.prefix(6) {
            guard let raw = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: raw), let data = ImageCompressor.jpegData(from: image) else { continue }
            compareImages.append(data)
        }
    }

    private func handleImage(_ image: UIImage) {
        guard let data = ImageCompressor.jpegData(from: image) else { app.errorMessage = "تعذر تجهيز الصورة."; return }
        app.selectedImageData = data
        Task { await app.analyze(imageData: data) }
    }
}
