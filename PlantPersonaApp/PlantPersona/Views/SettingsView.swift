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
                    SecureField("hf_...", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("حفظ") {
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
                        status = "تم الحذف"
                    }

                    if !status.isEmpty { Text(status).font(.footnote) }
                }

                Section("عَيْن") {
                    LabeledContent("الإصدار", value: "4.1")
                    LabeledContent("Build", value: "10")
                    LabeledContent("تحليل المكان", value: "بصري تقريبي")
                }
            }
            .navigationTitle("الإعدادات")
            .toolbar {
                if !embedInNavigation {
                    ToolbarItem(placement: .topBarTrailing) { Button("تم") { dismiss() } }
                }
            }
        }
    }
}
