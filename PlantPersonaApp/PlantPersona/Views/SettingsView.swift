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
            Section("Hugging Face") {
                SecureField("hf_...", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text("المفتاح يُحفظ محليًا داخل Keychain على جهازك ولا يظهر بعد الحفظ.")
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

            Section("عن عَيْن") {
                LabeledContent("الإصدار", value: "2.0")
                LabeledContent("نوع التحليل", value: "رؤية عامة")
                LabeledContent("السجل", value: "آخر 40 تحليل")
                Text("عَيْن يشرح ما يظهر في الصور بشكل مبسط. النتائج تعتمد على وضوح الصورة وقد لا تحدد الموديل أو العلامة التجارية بدقة إذا لم تكن ظاهرة.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
