import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var status = ""
    var embedInNavigation: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Hugging Face") {
                    SecureField("hf_...", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("المفتاح يُحفظ محليًا داخل Keychain على جهازك.").font(.footnote).foregroundStyle(.secondary)
                    Button("حفظ المفتاح") { do { try KeychainStore.shared.saveToken(token.trimmingCharacters(in: .whitespacesAndNewlines)); token = ""; status = "تم الحفظ ✓" } catch { status = error.localizedDescription } }
                    Button("حذف المفتاح", role: .destructive) { KeychainStore.shared.deleteToken(); status = "تم حذف المفتاح" }
                    if !status.isEmpty { Text(status).font(.footnote) }
                }
                Section("قدرات عَيْن 4.0") {
                    LabeledContent("شوف", value: "تعرف + شرح")
                    LabeledContent("افحص", value: "مقارنة + فحص موجه")
                    LabeledContent("سيارة", value: "صورة + فيديو + OBD Live")
                    LabeledContent("اسأل", value: "سياق آخر تحليل")
                    LabeledContent("الذاكرة", value: "ملفات + Timeline")
                }
                Section("مهم") {
                    Text("تشخيص السيارة احتمالي حتى يتم إثباته بفحص ميداني أو قياسات. عند تحذير زيت أو حرارة أو فرامل أو وقود أو طرق قوي بالمحرك، أوقف القيادة وافحص السيارة.").font(.footnote).foregroundStyle(.orange)
                    Text("USB OBD يعتمد على دعم iOS وبروتوكول الملحق. ELM327 عبر Wi‑Fi هو المسار الأكثر مباشرة في هذه النسخة.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("عن عَيْن") { LabeledContent("الإصدار", value: "4.0"); LabeledContent("Build", value: "9") }
            }
            .navigationTitle("الإعدادات")
            .toolbar { if !embedInNavigation { ToolbarItem(placement: .topBarTrailing) { Button("تم") { dismiss() } } } }
        }
    }
}
