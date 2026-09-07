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
            LinearGradient(
                colors: [Color.black, Color(red: 0.04, green: 0.09, blue: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    scannerCard
                    if isLoadingPhoto { loadingPhotoCard }
                    if app.isAnalyzing { analyzingCard }
                    if let diagnosis = app.diagnosis { diagnosisCard(diagnosis) }
                    if let persona = app.persona { personaCard(persona) }
                    if let error = app.errorMessage { errorCard(error) }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PLANT PERSONA")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(.green.opacity(0.8))
                Text("وش تقول نبتتك؟")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: 8)
            Button { app.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var scannerCard: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Color.green.opacity(0.22), lineWidth: 1)
                    )

                if let data = app.selectedImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .overlay(alignment: .topLeading) {
                            Text("BIO-SCAN")
                                .font(.caption2.monospaced().bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.55), in: Capsule())
                                .padding(14)
                        }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "leaf.circle.fill")
                            .font(.system(size: 76))
                            .foregroundStyle(.green)
                            .symbolRenderingMode(.hierarchical)
                        Text("وجّه الكاميرا لأوراق النبتة")
                            .font(.title3.bold())
                        Text("صورة واضحة، ضوء جيد، وخلي الورقة المصابة ظاهرة")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 25)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1.06, contentMode: .fit)
            .frame(minHeight: 300, maxHeight: 430)

            HStack(spacing: 12) {
                actionButton(title: "صوّر النبتة", icon: "camera.fill", primary: true) {
                    showCamera = true
                }

                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label("من الصور", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.white.opacity(0.12))
                .disabled(isLoadingPhoto || app.isAnalyzing)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingPhotoCard: some View {
        HStack(spacing: 14) {
            ProgressView().tint(.green)
            Text("قاعد أجهز الصورة…").bold()
            Spacer()
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var analyzingCard: some View {
        HStack(spacing: 14) {
            ProgressView().tint(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("قاعد أسمع شكوى النبتة…").bold()
                Text("تحليل الصورة ثم تحويل التشخيص إلى شخصية")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func diagnosisCard(_ d: PlantDiagnosis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.plantName).font(.title2.bold())
                    if let scientific = d.scientificName {
                        Text(scientific).italic().foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(d.confidence)%")
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.green.opacity(0.14), in: Capsule())
            }

            Divider().overlay(Color.white.opacity(0.08))
            Label(d.likelyIssue, systemImage: "stethoscope")
                .font(.headline)
            Text(d.healthStatus).foregroundStyle(.secondary)

            if !d.visualEvidence.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("وش شاف الذكاء الاصطناعي").font(.subheadline.bold())
                    ForEach(d.visualEvidence, id: \.self) { item in
                        Label(item, systemImage: "viewfinder")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !d.careSteps.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("الخطة الآن").font(.subheadline.bold())
                    ForEach(Array(d.careSteps.enumerated()), id: \.offset) { index, item in
                        Text("\(index + 1). \(item)").font(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 24))
    }

    private func personaCard(_ p: PlantPersonaMessage) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label(p.mood, systemImage: "waveform")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.14), in: Capsule())
                Spacer()
                Text("VOICE LOG 01")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(p.title).font(.title2.bold())
            Text("“\(p.message)”")
                .font(.system(size: 21, weight: .medium, design: .rounded))
                .lineSpacing(6)
            Label(p.shortAction, systemImage: "bolt.heart.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.green)

            HStack(spacing: 12) {
                Button {
                    app.speech.speak(p)
                } label: {
                    Label("اسمع نبتتك", systemImage: "speaker.wave.2.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button { app.speech.stop() } label: {
                    Image(systemName: "stop.fill")
                        .padding(.vertical, 14)
                        .padding(.horizontal, 5)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.green.opacity(0.22), lineWidth: 1)
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ما قدرت أسمع النبتة", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text(message).foregroundStyle(.secondary)
            if message.contains("مفتاح Hugging Face") {
                Button("فتح الإعدادات") { app.showSettings = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private func actionButton(
        title: String,
        icon: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(.borderedProminent)
        .tint(primary ? .green : Color.white.opacity(0.12))
        .disabled(isLoadingPhoto || app.isAnalyzing)
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
