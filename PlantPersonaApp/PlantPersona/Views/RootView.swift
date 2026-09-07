import SwiftUI
import UIKit
import PhotosUI

struct RootView: View {
    @EnvironmentObject private var app: AppState

    @State private var mode: AYNMode = .see
    @State private var showCamera = false
    @State private var showProfiles = false
    @State private var showOBD = false

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
                background

                ScrollView {
                    VStack(spacing: 16) {
                        header
                        modeDock
                        modeContent

                        if isLoadingMedia || app.isAnalyzing { loadingBar }
                        if let answer = app.assistantAnswer { answerCard(answer) }
                        if let step = app.guidedStep, !step.isEmpty { guidedCard(step) }
                        if let compare = app.compareResult { simpleTextCard("المقارنة", icon: "rectangle.2.swap", text: compare) }
                        if let result = app.analysis { resultCard(result) }
                        if let error = app.errorMessage { errorCard(error) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 44)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onImage: handleImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showProfiles) { profilesSheet }
        .sheet(isPresented: $showOBD) { NavigationStack { OBDView() } }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            Task { await loadVideo(item) }
        }
        .onChange(of: compareItems) { _, items in
            Task { await loadCompare(items) }
        }
    }

    private var background: some View {
        ZStack {
            Color.aynInk.ignoresSafeArea()
            RadialGradient(colors: [.cyan.opacity(0.13), .clear], center: .topTrailing, startRadius: 20, endRadius: 420)
                .ignoresSafeArea()
            RadialGradient(colors: [.aynViolet.opacity(0.10), .clear], center: .bottomLeading, startRadius: 30, endRadius: 480)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AYNMark(size: 52)
            VStack(alignment: .leading, spacing: 1) {
                Text("عَيْن")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                if let profile = selectedProfile {
                    Text(profile.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            Button { showProfiles = true } label: {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(GlassButtonStyle())
        }
    }

    private var modeDock: some View {
        HStack(spacing: 6) {
            ForEach(AYNMode.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.24)) { mode = item }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: icon(for: item))
                            .font(.system(size: 16, weight: .bold))
                        Text(item.rawValue)
                            .font(.caption2.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(mode == item ? .black : .white)
                }
                .buttonStyle(GlassButtonStyle(prominent: mode == item))
            }
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .see: seeMode
        case .inspect: inspectMode
        case .car: carMode
        case .ask: askMode
        }
    }

    private var seeMode: some View {
        VStack(spacing: 12) {
            mediaHero
            mediaButtons
        }
    }

    private var inspectMode: some View {
        VStack(spacing: 12) {
            compactTitle("فحص", icon: "scope")
            mediaButtons

            PhotosPicker(selection: $compareItems, maxSelectionCount: 6, matching: .images) {
                glassAction(
                    title: "قبل / بعد",
                    subtitle: compareImages.count >= 2 ? "\(compareImages.count) صور جاهزة" : "اختر صورتين أو أكثر",
                    icon: "rectangle.2.swap"
                )
            }
            .buttonStyle(.plain)

            if compareImages.count >= 2 {
                Button {
                    Task {
                        await app.compare(
                            images: compareImages,
                            prompt: "قارن الصور بالترتيب وحدد التغيرات المهمة فقط، وهل يوجد تحسن أو تدهور واضح."
                        )
                    }
                } label: {
                    primaryAction("ابدأ المقارنة", icon: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .disabled(app.isAnalyzing)
            }

            Button {
                Task { await app.nextGuidedStep(mode: "فحص عام") }
            } label: {
                glassAction(
                    title: "اللقطة التالية",
                    subtitle: app.analysis == nil ? "تظهر بعد أول تحليل" : "خل عَيْن يطلب لقطة واحدة مفيدة",
                    icon: "camera.metering.center.weighted"
                )
            }
            .buttonStyle(.plain)
            .disabled(app.analysis == nil || app.isAnalyzing)
        }
    }

    private var carMode: some View {
        VStack(spacing: 12) {
            compactTitle("السيارة", icon: "car.fill")

            HStack(spacing: 9) {
                Button { showOBD = true } label: {
                    compactGlassButton("OBD", icon: "cable.connector")
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $videoItem, matching: .videos) {
                    compactGlassButton("فيديو", icon: "video.fill")
                }
                .buttonStyle(.plain)
            }

            mediaButtons

            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("وش قال الفني؟", text: $technicianText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...5)

                    if !technicianText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            Task { await app.reviewTechnician(technicianText) }
                        } label: {
                            primaryAction("راجع التشخيص", icon: "checkmark.seal.fill")
                        }
                        .buttonStyle(.plain)
                        .disabled(app.isAnalyzing)
                    }
                }
            }

            Button {
                Task { await app.nextGuidedStep(mode: "تشخيص سيارة") }
            } label: {
                glassAction(
                    title: "فحص موجه",
                    subtitle: app.analysis == nil ? "حلّل صورة أو فيديو أولًا" : "خطوة واحدة لزيادة دقة التشخيص",
                    icon: "checklist"
                )
            }
            .buttonStyle(.plain)
            .disabled(app.analysis == nil || app.isAnalyzing)
        }
    }

    private var askMode: some View {
        VStack(spacing: 12) {
            compactTitle("اسأل أي شيء", icon: "sparkles")

            GlassPanel {
                VStack(spacing: 12) {
                    TextField("اكتب سؤالك…", text: $question, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...7)
                        .font(.body)

                    HStack {
                        if app.analysis != nil || app.obd.lastResult != nil {
                            Toggle("استخدم التحليل الحالي", isOn: $useCurrentContext)
                                .font(.caption)
                                .toggleStyle(.switch)
                        }
                        Spacer()
                        Button {
                            let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !q.isEmpty else { return }
                            question = ""
                            Task { await app.ask(q, useCurrentContext: useCurrentContext) }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .black))
                                .frame(width: 42, height: 42)
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.isAnalyzing)
                    }
                }
            }

            if app.analysis != nil {
                HStack(spacing: 8) {
                    quickAsk("هل هذا طبيعي؟")
                    quickAsk("وش أفحص بعد؟")
                    quickAsk("اشرحه أبسط")
                }
            }
        }
    }

    private var mediaHero: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let data = app.selectedImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [.white.opacity(0.08), .cyan.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        VStack(spacing: 14) {
                            AYNMark(size: 88)
                            Text("شوف أكثر")
                                .font(.title3.bold())
                            Text("صوّر أو اختر صورة")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 330)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.8)
            }

            if app.selectedImageData != nil {
                HStack {
                    Text(app.selectedMediaKind.isEmpty ? "جاهز" : app.selectedMediaKind)
                    Spacer()
                    Button("مسح") { app.reset() }
                        .buttonStyle(.plain)
                }
                .font(.caption.bold())
                .padding(.horizontal, 15)
                .frame(height: 46)
                .background(.ultraThinMaterial)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
            }
        }
        .shadow(color: .black.opacity(0.24), radius: 22, y: 10)
    }

    private var mediaButtons: some View {
        HStack(spacing: 9) {
            Button { showCamera = true } label: {
                mediaButton("كاميرا", icon: "camera.fill", primary: true)
            }
            .buttonStyle(.plain)

            PhotosPicker(selection: $photoItem, matching: .images) {
                mediaButton("صورة", icon: "photo.fill", primary: false)
            }
            .buttonStyle(.plain)

            PhotosPicker(selection: $videoItem, matching: .videos) {
                mediaButton("فيديو", icon: "video.fill", primary: false)
            }
            .buttonStyle(.plain)
        }
        .disabled(isLoadingMedia || app.isAnalyzing)
    }

    private func mediaButton(_ title: String, icon: String, primary: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(primary ? .black : .white)
            .background(
                primary
                ? AnyShapeStyle(LinearGradient(colors: [.white, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.8)
            }
    }

    private var loadingBar: some View {
        GlassPanel {
            HStack(spacing: 12) {
                ProgressView().tint(.cyan)
                Text(isLoadingMedia ? "جاري التجهيز…" : "جاري التحليل…")
                    .font(.subheadline.bold())
                Spacer()
            }
        }
    }

    private func resultCard(_ result: VisualAnalysis) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.category.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(.cyan)
                        Text(result.title)
                            .font(.title2.bold())
                        Text(result.summary)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    Spacer(minLength: 12)
                    Text("\(result.confidence)%")
                        .font(.caption.bold().monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.08), in: Capsule())
                }

                if let geo = result.geo, geo.confidence > 0 {
                    geoCard(geo)
                }

                if let auto = result.automotive, auto.isVehicleRelated {
                    automotiveSummary(auto)
                }

                if !result.keyFacts.isEmpty {
                    compactList("المهم", items: Array(result.keyFacts.prefix(5)))
                }

                if !result.visibleDetails.isEmpty {
                    compactList("من الصورة", items: Array(result.visibleDetails.prefix(5)))
                }

                if !result.cautions.isEmpty {
                    compactList("تنبيه", items: Array(result.cautions.prefix(4)), warning: true)
                }

                if let uncertainty = result.uncertainty, !uncertainty.isEmpty {
                    Text(uncertainty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func geoCard(_ geo: GeoEstimate) -> some View {
        let place = [geo.landmark, geo.area, geo.city, geo.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "، ")

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("المكان المحتمل", systemImage: "location.fill")
                    .font(.headline)
                Spacer()
                Text("\(geo.confidence)%")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.cyan)
            }
            if !place.isEmpty { Text(place).font(.subheadline.bold()) }
            if !geo.evidence.isEmpty {
                Text(geo.evidence.prefix(3).joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .background(.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func automotiveSummary(_ a: AutomotiveDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(a.probableSystem ?? "تشخيص السيارة", systemImage: "car.badge.gearshape.fill")
                    .font(.headline)
                Spacer()
                if let drive = a.canDrive { Text(drive).font(.caption.bold()).foregroundStyle(drive == "لا" ? .red : .orange) }
            }
            if let top = a.likelyCauses.first {
                Text("الأرجح: \(top.cause) · \(top.probability)%")
                    .font(.subheadline.bold())
            }
            if let firstCheck = a.checks.first {
                Text("ابدأ بـ: \(firstCheck)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func compactList(_ title: String, items: [String], warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(warning ? .orange : .white)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(warning ? Color.orange : Color.cyan)
                        .frame(width: 5, height: 5)
                        .padding(.top, 7)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.80))
                }
            }
        }
    }

    private func answerCard(_ text: String) -> some View {
        simpleTextCard("عَيْن", icon: "sparkles", text: text)
    }

    private func guidedCard(_ text: String) -> some View {
        GlassPanel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 8) {
                    Text(text)
                    Button { showCamera = true } label: {
                        Text("افتح الكاميرا")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                }
                Spacer()
            }
        }
    }

    private func simpleTextCard(_ title: String, icon: String, text: String) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 9) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(.cyan)
                Text(text)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorCard(_ message: String) -> some View {
        GlassPanel {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
                Spacer()
            }
        }
    }

    private func compactTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(.cyan)
            Text(title).font(.title3.bold())
            Spacer()
        }
    }

    private func glassAction(title: String, subtitle: String, icon: String) -> some View {
        GlassPanel {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.title3.bold())
                    .foregroundStyle(.cyan)
                    .frame(width: 40, height: 40)
                    .background(.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.left").foregroundStyle(.secondary)
            }
        }
    }

    private func compactGlassButton(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.16), lineWidth: 0.8) }
    }

    private func primaryAction(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(.black)
            .background(
                LinearGradient(colors: [.white, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }

    private func quickAsk(_ text: String) -> some View {
        Button {
            Task { await app.ask(text, useCurrentContext: true) }
        } label: {
            Text(text)
                .font(.caption.bold())
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(app.isAnalyzing)
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
                                    if app.selectedProfileID == profile.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan)
                                    }
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
                    Section {
                        Button("بدون ملف") {
                            app.selectedProfileID = nil
                            showProfiles = false
                        }
                    }
                }
            }
            .navigationTitle("الملفات")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("تم") { showProfiles = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingMedia = true
        defer {
            isLoadingMedia = false
            photoItem = nil
        }
        do {
            guard let rawData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: rawData),
                  let data = ImageCompressor.jpegData(from: image) else {
                app.errorMessage = "تعذر فتح الصورة."
                return
            }
            app.selectedImageData = data
            await app.analyze(imageData: data)
        } catch {
            app.errorMessage = "تعذر فتح الصورة: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadVideo(_ item: PhotosPickerItem) async {
        isLoadingMedia = true
        defer {
            isLoadingMedia = false
            videoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                app.errorMessage = "تعذر فتح الفيديو."
                return
            }
            await app.analyzeVideo(data: data)
        } catch {
            app.errorMessage = "تعذر فتح الفيديو: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadCompare(_ items: [PhotosPickerItem]) async {
        isLoadingMedia = true
        compareImages = []
        defer { isLoadingMedia = false }

        for item in items.prefix(6) {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: raw),
                  let data = ImageCompressor.jpegData(from: image) else { continue }
            compareImages.append(data)
        }
    }

    private func handleImage(_ image: UIImage) {
        guard let data = ImageCompressor.jpegData(from: image) else {
            app.errorMessage = "تعذر تجهيز الصورة."
            return
        }
        app.selectedImageData = data
        Task { await app.analyze(imageData: data) }
    }
}
