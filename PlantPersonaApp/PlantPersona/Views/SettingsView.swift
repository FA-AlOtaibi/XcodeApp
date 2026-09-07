import SwiftUI

struct SettingsView: View {
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
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("تم") { dismiss() } } }
                }
            }
        }
    }

    private var content: some View {
        Form {
            Section("Hugging Face") {
                SecureField("hf_...", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("المفتاح يُحفظ محليًا داخل Keychain على جهازك ولا يظهر بعد الحفظ.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("حفظ المفتاح") {
                    do {
                        try KeychainStore.shared.saveToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
                        token = ""
                        status = "تم الحفظ ✓"
                    } catch { status = error.localizedDescription }
                }
                Button("حذف المفتاح", role: .destructive) {
                    KeychainStore.shared.deleteToken(); status = "تم حذف المفتاح"
                }
                if !status.isEmpty { Text(status).font(.footnote) }
            }

            Section("قدرات عَيْن 3.0") {
                LabeledContent("الصور", value: "تحليل عام + سيارات")
                LabeledContent("الفيديو", value: "لقطات متعددة + بصمة صوت")
                LabeledContent("OBD-II", value: "ELM327 Wi‑Fi")
                LabeledContent("USB", value: "اكتشاف الملحقات المتوافقة")
                Text("تشخيص السيارة يجمع الأدلة المرئية والصوتية وبيانات OBD إن وُجدت، ويرتب الأسباب المرجحة والفحوصات قبل اقتراح تبديل القطع.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("مهم") {
                Text("الصورة أو صوت الجوال وحدهما لا يثبتان العطل الميكانيكي. عند ظهور تحذير زيت، حرارة، فرامل، وقود، دخان شديد أو طرق قوي بالمحرك، أوقف القيادة وافحص السيارة ميدانيًا.")
                    .font(.footnote).foregroundStyle(.orange)
                Text("اتصال USB المباشر يعتمد على ما يسمح به iOS وبروتوكول الملحق؛ محول USB‑Serial عادي ليس مضمونًا أن يكون متاحًا للتطبيق.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("عن عَيْن") {
                LabeledContent("الإصدار", value: "3.0")
                LabeledContent("Build", value: "7")
                LabeledContent("السجل", value: "آخر 40 تحليل")
            }
        }
    }
}
