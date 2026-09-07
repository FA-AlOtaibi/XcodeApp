import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            Group {
                if app.history.entries.isEmpty {
                    ContentUnavailableView(
                        "ما عندك سجل حتى الآن",
                        systemImage: "leaf.circle",
                        description: Text("كل تشخيص جديد ينحفظ هنا تلقائيًا عشان تتابع حالة نباتاتك.")
                    )
                } else {
                    List {
                        ForEach(app.history.entries) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(entry.diagnosis.plantName)
                                        .font(.headline)
                                    Spacer()
                                    Text(entry.date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.diagnosis.likelyIssue)
                                    .font(.subheadline.bold())
                                Text(entry.diagnosis.healthStatus)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    Label("\(entry.diagnosis.confidence)%", systemImage: "scope")
                                    if let persona = entry.persona {
                                        Label(persona.mood, systemImage: "waveform")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.green)
                            }
                            .padding(.vertical, 8)
                        }
                        .onDelete(perform: app.history.remove)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("سجل نباتاتي")
            .toolbar {
                if !app.history.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("مسح الكل", role: .destructive) { app.history.clear() }
                    }
                }
            }
        }
    }
}
