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
        .tint(.green)
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
            ScrollView {
                VStack(spacing: 18) {
                    topIdentity
                    scanStage
                    quickActions

                    if isLoadingPhoto { activityCard("جاري تجهيز الصورة", detail: "نقرأ الصورة قبل التحليل") }
                    if app.isAnalyzing { activityCard("النبتة تتكلم الآن…", detail: "تحليل بصري + صياغة شخصية") }
                    if let diagnosis = app.diagnosis { healthDashboard(diagnosis) }
                    if let persona = app.persona { voiceCard(persona) }
                    if let error = app.errorMessage { errorCard(error) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
            .background(
                LinearGradient(
                    colors: [Color(red: 0.015, green: 0.045, blue: 0.03), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationBarHidden(true)
        }
    }

    private var topIdentity: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.green.opacity(0.14))
                Image(systemName: "leaf.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.green)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text("Plant Persona")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("مختبر شخصيات النباتات")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let d = app.diagnosis {
                Text(d.urgency.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.green.opacity(0.12), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
    }

    private var scanStage: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let data = app.selectedImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color.green.opacity(0.2), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        VStack(spacing: 14) {
                            Image(systemName: "viewfinder.circle.fill")
                                .font(.system(size: 78))
                                .foregroundStyle(.green)
                            Text("صوّر ورقة النبتة")
                                .font(.title2.bold())
                            Text("خلي المشكلة واضحة، والإضاءة طبيعية قدر الإمكان")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 390)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)

            HStack {
                Label(app.selectedImageData == nil ? "جاهز للمسح" : "الصورة جاهزة", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Spacer()
                if app.selectedImageData != nil {
                    Button("مسح") { app.reset() }
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.08)))
        .shadow(color: .green.opacity(0.08), radius: 30, y: 12)
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                showCamera = true
            } label: {
                Label("الكاميرا", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(.green, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)

            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label("الصور", systemImage: "photo.stack.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .disabled(app.isAnalyzing || isLoadingPhoto)
    }

    private func activityCard(_ title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            ProgressView().tint(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func healthDashboard(_ d: PlantDiagnosis) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("نتيجة الفحص")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    Text(d.plantName)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    if let scientific = d.scientificName {
                        Text(scientific).italic().foregroundStyle(.secondary)
                    }
                }
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, min(100, d.confidence))) / 100)
                        .stroke(.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(d.confidence)%").font(.caption.bold().monospacedDigit())
                }
                .frame(width: 66, height: 66)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(d.likelyIssue).font(.title3.bold())
                Text(d.healthStatus).foregroundStyle(.secondary)
            }

            if !d.careSteps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("خطة الإنقاذ").font(.headline)
                    ForEach(Array(d.careSteps.prefix(4).enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 26, height: 26)
                                .background(.green.opacity(0.15), in: Circle())
                                .foregroundStyle(.green)
                            Text(step).font(.subheadline)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.07)))
    }

    private func voiceCard(_ p: PlantPersonaMessage) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Label("صوت النبتة", systemImage: "waveform.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                Spacer()
                Text(p.mood)
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.12), in: Capsule())
            }

            Text(p.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(p.message)
                .font(.system(size: 21, weight: .medium, design: .rounded))
                .lineSpacing(6)

            HStack(spacing: 10) {
                Button { app.speech.speak(p) } label: {
                    Label("تشغيل", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.green, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)

                Button { app.speech.stop() } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 54, height: 54)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(.plain)

                ShareLink(item: "\(p.title)\n\n\(p.message)\n\n\(p.shortAction)") {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 54, height: 54)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                selectedTab = 2
            } label: {
                Label("غيّر الصوت والشخصية", systemImage: "waveform.badge.mic")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [.green.opacity(0.13), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.green.opacity(0.16)))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("تعذر إكمال العملية", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
