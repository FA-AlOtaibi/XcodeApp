import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var status = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Hugging Face") {
                    SecureField("hf_...", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("يُحفظ المفتاح محليًا داخل Keychain على جهازك ولا يظهر في الواجهة بعد الحفظ.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("حفظ المفتاح") {
                        do {
                            try KeychainStore.shared.saveToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
                            token = ""
                            status = "تم الحفظ ✓"
                        } catch { status = error.localizedDescription }
                    }
                    Button("حذف المفتاح", role: .destructive) {
                        KeychainStore.shared.deleteToken()
                        status = "تم حذف المفتاح"
                    }
                    if !status.isEmpty { Text(status).font(.footnote) }
                }

                Section("النماذج") {
                    LabeledContent("الرؤية", value: "Qwen2.5-VL-3B")
                    LabeledContent("الشخصية", value: "Qwen2.5-7B")
                }

                Section("تنبيه") {
                    Text("تشخيص النبات من صورة واحدة تقديري. افحص الري والتربة والإضاءة فعليًا قبل اتخاذ إجراء قوي مثل استخدام مبيد أو التخلص من النبات.")
                }
            }
            .navigationTitle("الإعدادات")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }
}
