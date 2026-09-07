import SwiftUI
import UIKit
import PhotosUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            studio
                .tabItem { Label("الاستوديو", systemImage: "viewfinder") }
                .tag(0)

            HistoryView()
                .tabItem { Label("السجل", systemImage: "clock.arrow.circlepath") }
                .tag(1)

            SettingsView(embedInNavigation: true)
                .tabItem { Label("الإعدادات", systemImage: "slider.horizontal.3") }
                .tag(2)
        }
        .tint(.cyan)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onImage: handleImage)
                .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
    }

    private var studio: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.025, green: 0.045, blue: 0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        brandHeader
                        scanner
                        if isLoadingPhoto { statusCard("جاري تجهيز الصورة…") }
                        if app.isAnalyzing { statusCard("جاري فهم الصورة…") }
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
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.cyan.opacity(0.16))
                    .frame(width: 58, height: 58)
                Image(systemName: "eye.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.cyan)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("عَيْن")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                Text("صوّر أي شيء، وافهمه")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("AI VISION")
                .font(.caption2.monospaced().bold())
                .foregroundStyle(.cyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.cyan.opacity(0.10), in: Capsule())
        }
        .frame(maxWidth: .infinity)
    }

    private var scanner: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let data = app.selectedImageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.cyan.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay {
                            VStack(spacing: 14) {
                                Image(systemName: "viewfinder.circle.fill")
                                    .font(.system(size: 86))
                                    .foregroundStyle(.cyan.opacity(0.8))
                                Text("وش تبي تعرف عنه؟")
                                    .font(.title2.bold())
                                Text("جهاز، سيارة، أداة، طعام، نبات، مبنى… أي شيء قدامك")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 28)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 430)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

                HStack {
                    Label(app.selectedImageData == nil ? "جاهز للمسح" : "الصورة جاهزة", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    if app.selectedImageData != nil {
                        Button("مسح") { app.reset() }
                            .buttonStyle(.plain)
                    }
                }
                .font(.caption.bold())
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
            }

            HStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    Label("الكاميرا", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(.cyan, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingPhoto || app.isAnalyzing)

                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label("الصور", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .disabled(isLoadingPhoto || app.isAnalyzing)
            }
        }
    }

    private func statusCard(_ text: String) -> some View {
        HStack(spacing: 14) {
            ProgressView().tint(.cyan)
            Text(text).font(.headline)
            Spacer()
        }
        .padding(18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func analysisCard(_ a: VisualAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(a.category.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                    Text(a.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(a.summary)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineSpacing(4)
                }
                Spacer(minLength: 14)
                confidenceBadge(a.confidence)
            }

            section(title: "أهم المعلومات", icon: "sparkles", items: a.keyFacts)
            section(title: "وش ظاهر بالصورة", icon: "eye", items: a.visibleDetails)
            section(title: "الاستخدام أو طريقة العمل", icon: "gearshape.2", items: a.howItWorksOrUsed)

            if !a.cautions.isEmpty {
                section(title: "تنبيهات", icon: "exclamationmark.triangle", items: a.cautions, warning: true)
            }

            if let uncertainty = a.uncertainty, !uncertainty.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                    Text(uncertainty).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }

            ShareLink(item: shareText(a)) {
                Label("مشاركة النتيجة", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.cyan.opacity(0.15)))
    }

    private func confidenceBadge(_ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)%").font(.title3.bold().monospacedDigit())
            Text("ثقة").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 68, height: 68)
        .background(Color.cyan.opacity(0.12), in: Circle())
        .overlay(Circle().stroke(Color.cyan.opacity(0.35), lineWidth: 2))
    }

    private func section(title: String, icon: String, items: [String], warning: Bool = false) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    Label(title, systemImage: icon)
                        .font(.headline)
                        .foregroundStyle(warning ? .orange : .white)
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(warning ? Color.orange : Color.cyan)
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)
                            Text(item).font(.subheadline).foregroundStyle(.white.opacity(0.78))
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("تعذر تحليل الصورة", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }

    private func shareText(_ a: VisualAnalysis) -> String {
        let facts = a.keyFacts.map { "• \($0)" }.joined(separator: "\n")
        return "\(a.title)\n\(a.summary)\n\n\(facts)"
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer {
            isLoadingPhoto = false
            photoItem = nil
        }
        do {
            guard let rawData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: rawData) else {
                app.errorMessage = "تعذر قراءة الصورة المختارة."
                return
            }
            handleImage(image)
        } catch {
            app.errorMessage = "تعذر فتح الصورة: \(error.localizedDescription)"
        }
    }

    private func handleImage(_ image: UIImage) {
        guard let data = ImageCompressor.jpegData(from: image) else {
            app.errorMessage = "تعذر تجهيز الصورة للتحليل."
            return
        }
        app.selectedImageData = data
        Task { await app.analyze(imageData: data) }
    }
}
