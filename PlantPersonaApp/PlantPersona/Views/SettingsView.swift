import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var status = ""
    var embedInNavigation: Bool = false

    var body: some View {
        Group {
            if embedInNavigation {
                NavigationStack { content.navigationTitle("الإعدادات") }
            } else {
                NavigationStack {
                    content
                        .navigationTitle("الإعدادات")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("تم") { dismiss() }
                            }
                        }
                }
            }
        }
    }

    private var content: some View {
        Form {
            VoiceLabView(speech: app.speech)

            Section("Hugging Face") {
                SecureField("hf_...", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("المفتاح يُحفظ داخل Keychain على جهازك فقط.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("حفظ المفتاح") {
                    do {
                        try KeychainStore.shared.saveToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
                        token = ""
                        status = "تم الحفظ ✓"
                    } catch {
                        status = error.localizedDescription
                    }
                }

                Button("حذف المفتاح", role: .destructive) {
                    KeychainStore.shared.deleteToken()
                    status = "تم حذف المفتاح"
                }

                if !status.isEmpty { Text(status).font(.footnote) }
            }

            Section("التطبيق") {
                LabeledContent("الإصدار", value: "1.4")
                LabeledContent("السجل", value: "آخر 30 تشخيص")
                Text("التشخيص من صورة واحدة تقديري. استخدم النتيجة كدليل للعناية وليس كتشخيص زراعي قطعي.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct VoiceLabView: View {
    @ObservedObject var speech: PlantSpeechService

    var body: some View {
        Section("مختبر الصوت") {
            if speech.arabicVoices.isEmpty {
                Text("ما لقيت أصوات عربية مثبتة على الجهاز. نزّل صوتًا عربيًا من إعدادات iPhone > تسهيلات الاستخدام > المحتوى المنطوق > الأصوات.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("الصوت", selection: $speech.selectedVoiceID) {
                    Text("أفضل صوت تلقائي").tag("")
                    ForEach(speech.arabicVoices) { voice in
                        Text("\(voice.name) — \(voice.subtitle)").tag(voice.id)
                    }
                }
            }

            Picker("الشخصية", selection: $speech.style) {
                ForEach(PlantSpeechService.Style.allCases) { style in
                    Label(style.rawValue, systemImage: style.icon).tag(style)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("سرعة القراءة")
                    Spacer()
                    Text(String(format: "%.0f%%", speech.speed * 100))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $speech.speed, in: 0.82...1.16, step: 0.02)
            }

            Button {
                speech.preview()
            } label: {
                Label("جرّب الصوت", systemImage: "speaker.wave.2.fill")
            }

            Button {
                speech.stop()
            } label: {
                Label("إيقاف الصوت", systemImage: "stop.fill")
            }
        }
    }
}
