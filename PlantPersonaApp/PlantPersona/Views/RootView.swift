import SwiftUI
import UIKit
import PhotosUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    hero

                    VStack(spacing: 16) {
                        if isLoadingPhoto { statusCard("جاري تجهيز الصورة…", icon: "photo.badge.clock") }
                        if app.isAnalyzing { statusCard("جاري تحليل النبتة…", icon: "waveform.path.ecg") }
                        if let diagnosis = app.diagnosis { diagnosisCard(diagnosis) }
                        if let persona = app.persona { personaCard(persona) }
                        if let error = app.errorMessage { errorCard(error) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 38)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onImage: handleImage)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $app.showSettings) {
            SettingsView()
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(newItem) }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let data = app.selectedImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.02, green: 0.17, blue: 0.09), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 130, weight: .semibold))
                            .foregroundStyle(.green.opacity(0.22))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 500)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.18), .black.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 500)

            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PLANT PERSONA")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(2.3)
                            .foregroundStyle(.green)
                        Text(app.selectedImageData == nil ? "خلّ نبتتك تتكلم" : "الصورة جاهزة للتحليل")
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                    }

                    Spacer(minLength: 12)

                    Button { app.showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .background(.black.opacity(0.5), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }

                Text("صوّر الورقة أو اختر صورة، والتطبيق يحلل نوع النبتة وحالتها ثم يحوّل النتيجة إلى رسالة بصوت وشخصية.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("صوّر النبتة", systemImage: "camera.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(.green, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingPhoto || app.isAnalyzing)

                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label("من الصور", systemImage: "photo.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingPhoto || app.isAnalyzing)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private func statusCard(_ title: String, icon: String) -> some View {
        HStack(spacing: 14) {
            ProgressView().tint(.green)
            Label(title, systemImage: icon)
                .font(.headline)
            Spacer()
        }
        .padding(18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func diagnosisCard(_ d: PlantDiagnosis) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("التشخيص")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    Text(d.plantName)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    if let scientific = d.scientificName {
                        Text(scientific)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(d.confidence)%")
                    .font(.title3.bold().monospacedDigit())
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(.green.opacity(0.14), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(d.likelyIssue).font(.title3.bold())
                Text(d.healthStatus).foregroundStyle(.secondary)
            }

            if !d.visualEvidence.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("العلامات الظاهرة").font(.headline)
                    ForEach(d.visualEvidence, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "viewfinder.circle.fill").foregroundStyle(.green)
                            Text(item).foregroundStyle(.white.opacity(0.78))
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            if !d.careSteps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("وش تسوي الآن؟").font(.headline)
                    ForEach(Array(d.careSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 26, height: 26)
                                .background(.green.opacity(0.16), in: Circle())
                                .foregroundStyle(.green)
                            Text(step)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.08)))
    }

    private func personaCard(_ p: PlantPersonaMessage) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(p.mood, systemImage: "waveform")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                Spacer()
                Text("صوت النبتة")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(p.title)
                .font(.system(size: 27, weight: .bold, design: .rounded))

            Text("“\(p.message)”")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .lineSpacing(7)

            Label(p.shortAction, systemImage: "bolt.heart.fill")
                .font(.headline)
                .foregroundStyle(.green)

            HStack(spacing: 12) {
                Button {
                    app.speech.speak(p)
                } label: {
                    Label("اسمعها", systemImage: "speaker.wave.2.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.green, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)

                Button { app.speech.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.headline)
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [.green.opacity(0.12), .white.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.green.opacity(0.18)))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("تعذر إكمال التحليل", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.white.opacity(0.72))
                .textSelection(.enabled)
            if message.contains("مفتاح Hugging Face") || message.contains("Inference Providers") {
                Button("فتح الإعدادات") { app.showSettings = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                app.errorMessage = "تعذر قراءة الصورة المختارة. جرّب صورة ثانية."
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
