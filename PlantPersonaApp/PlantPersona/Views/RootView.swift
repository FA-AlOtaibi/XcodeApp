import SwiftUI
import UIKit
import PhotosUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var isLoadingMedia = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            studio
                .tabItem { Label("عَيْن", systemImage: "viewfinder") }
                .tag(0)

            OBDView()
                .tabItem { Label("السيارة", systemImage: "car.fill") }
                .tag(1)

            HistoryView()
                .tabItem { Label("السجل", systemImage: "clock.arrow.circlepath") }
                .tag(2)

            SettingsView(embedInNavigation: true)
                .tabItem { Label("الإعدادات", systemImage: "slider.horizontal.3") }
                .tag(3)
        }
        .tint(.cyan)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onImage: handleImage).ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            Task { await loadVideo(item) }
        }
    }

    private var studio: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, Color(red: 0.02, green: 0.04, blue: 0.075)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        brandHeader
                        scanner
                        modeStrip
                        if isLoadingMedia { statusCard("جاري تجهيز الوسائط…") }
                        if app.isAnalyzing { statusCard(app.selectedMediaKind == "فيديو + صوت" ? "جاري فهم الفيديو والصوت…" : "جاري فهم الصورة…") }
                        if let sound = app.soundProfile { soundCard(sound) }
                        if let analysis = app.analysis { analysisCard(analysis) }
                        if let error = app.errorMessage { errorCard(error) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.cyan.opacity(0.14)).frame(width: 58, height: 58)
                Image(systemName: "eye.fill").font(.system(size: 25, weight: .bold)).foregroundStyle(.cyan)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("عَيْن").font(.system(size: 32, weight: .black, design: .rounded))
                Text("صورة، فيديو، صوت، وبيانات سيارة").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("3.0").font(.caption.monospaced().bold()).foregroundStyle(.cyan)
        }
    }

    private var scanner: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let data = app.selectedImageData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [Color.white.opacity(0.07), Color.cyan.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay {
                                VStack(spacing: 14) {
                                    Image(systemName: "viewfinder.circle.fill").font(.system(size: 86)).foregroundStyle(.cyan.opacity(0.8))
                                    Text("خل عَيْن يفهم اللي قدامك").font(.title2.bold())
                                    Text("صوّر شيء، اختر فيديو لصوت عطل، أو اربط OBD للسيارة").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 25)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 410).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.10)))

                HStack {
                    Label(app.selectedImageData == nil ? "جاهز" : app.selectedMediaKind, systemImage: app.selectedMediaKind == "فيديو + صوت" ? "waveform.and.magnifyingglass" : "dot.radiowaves.left.and.right")
                    Spacer()
                    if app.selectedImageData != nil { Button("مسح") { app.reset() }.buttonStyle(.plain) }
                }
                .font(.caption.bold()).padding(16).background(.ultraThinMaterial)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
            }

            HStack(spacing: 10) {
                Button { showCamera = true } label: {
                    mediaButton("كاميرا", icon: "camera.fill", primary: true)
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    mediaButton("صورة", icon: "photo.fill", primary: false)
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $videoItem, matching: .videos, photoLibrary: .shared()) {
                    mediaButton("فيديو", icon: "video.fill", primary: false)
                }
                .buttonStyle(.plain)
            }
            .disabled(isLoadingMedia || app.isAnalyzing)
        }
    }

    private func mediaButton(_ title: String, icon: String, primary: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(primary ? Color.cyan : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(primary ? .black : .white)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(primary ? 0 : 0.10)))
    }

    private var modeStrip: some View {
        HStack(spacing: 10) {
            capability("أي شيء", "cube.transparent")
            capability("أعطال سيارة", "wrench.and.screwdriver")
            capability("صوت فيديو", "waveform")
            capability("OBD", "cable.connector")
        }
        .font(.caption2.bold())
    }

    private func capability(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }

    private func statusCard(_ text: String) -> some View {
        HStack(spacing: 14) { ProgressView().tint(.cyan); Text(text).font(.headline); Spacer() }
            .padding(18).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
    }

    private func soundCard(_ s: MediaSoundProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("بصمة الصوت من الفيديو", systemImage: "waveform.badge.magnifyingglass").font(.headline).foregroundStyle(.cyan)
            HStack {
                metric("المدة", String(format: "%.1fs", s.durationSeconds))
                metric("RMS", String(format: "%.3f", s.rms))
                metric("Peak", String(format: "%.3f", s.peak))
                if let hz = s.dominantPulseHz { metric("نبض", String(format: "%.1fHz", hz)) }
            }
            Text(s.note).font(.caption).foregroundStyle(.secondary)
        }
        .padding(17).background(Color.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 21))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) { Text(value).font(.caption.bold().monospacedDigit()); Text(title).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }

    private func analysisCard(_ a: VisualAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(a.category.uppercased()).font(.caption.bold()).foregroundStyle(.cyan)
                    Text(a.title).font(.system(size: 29, weight: .bold, design: .rounded))
                    Text(a.summary).foregroundStyle(.white.opacity(0.78)).lineSpacing(4)
                }
                Spacer(minLength: 12)
                confidenceBadge(a.confidence)
            }

            if let auto = a.automotive, auto.isVehicleRelated { automotiveCard(auto) }
            section(title: "أهم المعلومات", icon: "sparkles", items: a.keyFacts)
            section(title: "وش ظاهر", icon: "eye", items: a.visibleDetails)
            section(title: "كيف يعمل أو يُستخدم", icon: "gearshape.2", items: a.howItWorksOrUsed)
            if !a.cautions.isEmpty { section(title: "تنبيهات", icon: "exclamationmark.triangle", items: a.cautions, warning: true) }
            if let uncertainty = a.uncertainty, !uncertainty.isEmpty {
                Label(uncertainty, systemImage: "questionmark.circle.fill").font(.subheadline).foregroundStyle(.orange)
                    .padding(14).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }
            ShareLink(item: shareText(a)) {
                Label("مشاركة النتيجة", systemImage: "square.and.arrow.up").font(.headline).frame(maxWidth: .infinity).frame(height: 54).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain)
        }
        .padding(20).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.cyan.opacity(0.15)))
    }

    private func automotiveCard(_ a: AutomotiveDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("تشخيص السيارة", systemImage: "car.badge.gearshape.fill").font(.title3.bold()).foregroundStyle(.cyan)
                Spacer()
                if let severity = a.severity { Text(severity.uppercased()).font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 6).background(severity == "critical" ? Color.red.opacity(0.2) : Color.orange.opacity(0.15), in: Capsule()) }
            }
            if let system = a.probableSystem { Label(system, systemImage: "wrench.adjustable").font(.headline) }
            if let drive = a.canDrive { Label("القيادة: \(drive)", systemImage: drive == "لا" ? "hand.raised.fill" : "steeringwheel").foregroundStyle(drive == "لا" ? .red : .orange).font(.headline) }

            if !a.likelyCauses.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("الأسباب المرجحة").font(.headline)
                    ForEach(Array(a.likelyCauses.enumerated()), id: \.offset) { index, cause in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text("\(index + 1). \(cause.cause)").bold(); Spacer(); Text("\(cause.probability)%").font(.caption.bold().monospacedDigit()).foregroundStyle(.cyan) }
                            Text(cause.reasoning).font(.subheadline).foregroundStyle(.secondary)
                        }.padding(12).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            section(title: "افحص بهذا الترتيب", icon: "checklist", items: a.checks)
            section(title: "الحلول المحتملة", icon: "wrench.and.screwdriver", items: a.fixes)
            if !a.dtcHints.isEmpty { section(title: "أكواد OBD محتملة", icon: "number.square", items: a.dtcHints) }
            if let note = a.mechanicNote, !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary).padding(12).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14)) }
        }
        .padding(16).background(Color.cyan.opacity(0.065), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.cyan.opacity(0.16)))
    }

    private func confidenceBadge(_ value: Int) -> some View {
        VStack(spacing: 2) { Text("\(value)%").font(.title3.bold().monospacedDigit()); Text("ثقة").font(.caption2).foregroundStyle(.secondary) }
            .frame(width: 68, height: 68).background(Color.cyan.opacity(0.12), in: Circle()).overlay(Circle().stroke(Color.cyan.opacity(0.35), lineWidth: 2))
    }

    private func section(title: String, icon: String, items: [String], warning: Bool = false) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    Label(title, systemImage: icon).font(.headline).foregroundStyle(warning ? .orange : .white)
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(warning ? Color.orange : Color.cyan).frame(width: 6, height: 6).padding(.top, 7)
                            Text(item).font(.subheadline).foregroundStyle(.white.opacity(0.78)); Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Label("تعذر التحليل", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.red); Text(message).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }

    private func shareText(_ a: VisualAnalysis) -> String {
        var text = "\(a.title)\n\(a.summary)\n\n" + a.keyFacts.map { "• \($0)" }.joined(separator: "\n")
        if let auto = a.automotive, auto.isVehicleRelated { text += "\n\nتشخيص السيارة:\n" + auto.likelyCauses.map { "• \($0.cause) — \($0.probability)%" }.joined(separator: "\n") }
        return text
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingMedia = true
        defer { isLoadingMedia = false; photoItem = nil }
        do {
            guard let rawData = try await item.loadTransferable(type: Data.self), let image = UIImage(data: rawData) else { app.errorMessage = "تعذر قراءة الصورة المختارة."; return }
            handleImage(image)
        } catch { app.errorMessage = "تعذر فتح الصورة: \(error.localizedDescription)" }
    }

    @MainActor
    private func loadVideo(_ item: PhotosPickerItem) async {
        isLoadingMedia = true
        defer { isLoadingMedia = false; videoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { app.errorMessage = "تعذر قراءة الفيديو."; return }
            await app.analyzeVideo(data: data)
        } catch { app.errorMessage = "تعذر فتح الفيديو: \(error.localizedDescription)" }
    }

    private func handleImage(_ image: UIImage) {
        guard let data = ImageCompressor.jpegData(from: image) else { app.errorMessage = "تعذر تجهيز الصورة للتحليل."; return }
        app.selectedImageData = data
        Task { await app.analyze(imageData: data) }
    }
}
