import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @State private var showCamera = false
    @State private var showLibrary = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.04, green: 0.09, blue: 0.07)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    scannerCard
                    if app.isAnalyzing { analyzingCard }
                    if let diagnosis = app.diagnosis { diagnosisCard(diagnosis) }
                    if let persona = app.persona { personaCard(persona) }
                    if let error = app.errorMessage { errorCard(error) }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(sourceType: .camera, onImage: handleImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            CameraPicker(sourceType: .photoLibrary, onImage: handleImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $app.showSettings) { SettingsView() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PLANT PERSONA")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(.green.opacity(0.8))
                Text("وش تقول نبتتك؟")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            }
            Spacer()
            Button { app.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
    }

    private var scannerCard: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.green.opacity(0.22), lineWidth: 1))
                    .frame(height: 320)

                if let data = app.selectedImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .overlay(alignment: .topLeading) {
                            Text("BIO-SCAN")
                                .font(.caption2.monospaced().bold())
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.black.opacity(0.55), in: Capsule())
                                .padding(14)
                        }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "leaf.circle.fill")
                            .font(.system(size: 70))
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

            HStack(spacing: 12) {
                actionButton(title: "صوّر النبتة", icon: "camera.fill", primary: true) { showCamera = true }
                actionButton(title: "من الصور", icon: "photo.on.rectangle", primary: false) { showLibrary = true }
            }
        }
    }

    private var analyzingCard: some View {
        HStack(spacing: 14) {
            ProgressView().tint(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("قاعد أسمع شكوى النبتة…").bold()
                Text("تحليل الصورة ثم تحويل التشخيص إلى شخصية")
                    .font(.footnote).foregroundStyle(.secondary)
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
                    if let scientific = d.scientificName { Text(scientific).italic().foregroundStyle(.secondary) }
                }
                Spacer()
                Text("\(d.confidence)%")
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 11).padding(.vertical, 7)
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
                            .font(.subheadline).foregroundStyle(.secondary)
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
        .padding(20)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 24))
    }

    private func personaCard(_ p: PlantPersonaMessage) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label(p.mood, systemImage: "waveform")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.green.opacity(0.14), in: Capsule())
                Spacer()
                Text("VOICE LOG 01").font(.caption2.monospaced()).foregroundStyle(.secondary)
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
                    Image(systemName: "stop.fill").padding(.vertical, 14).padding(.horizontal, 5)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.green.opacity(0.22), lineWidth: 1))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ما قدرت أسمع النبتة", systemImage: "exclamationmark.triangle.fill").font(.headline)
            Text(message).foregroundStyle(.secondary)
            if message.contains("مفتاح Hugging Face") {
                Button("فتح الإعدادات") { app.showSettings = true }
                    .buttonStyle(.borderedProminent).tint(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private func actionButton(title: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(.borderedProminent)
        .tint(primary ? .green : Color.white.opacity(0.12))
    }

    private func handleImage(_ image: UIImage) {
        guard let data = ImageCompressor.jpegData(from: image) else { return }
        app.selectedImageData = data
        Task { await app.analyze(imageData: data) }
    }
}
