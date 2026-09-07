import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HistoryContent(history: app.history)
    }
}

private struct HistoryContent: View {
    @ObservedObject var history: PlantHistoryStore

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    ContentUnavailableView(
                        "ما عندك تحليلات حتى الآن",
                        systemImage: "viewfinder.circle",
                        description: Text("كل صورة تحللها تنحفظ هنا تلقائيًا.")
                    )
                } else {
                    List {
                        ForEach(history.entries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(entry.analysis.title).font(.headline)
                                    Spacer()
                                    Text(entry.date, style: .date).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(entry.analysis.category).font(.caption.bold()).foregroundStyle(.cyan)
                                Text(entry.analysis.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                Label("\(entry.analysis.confidence)%", systemImage: "scope").font(.caption).foregroundStyle(.cyan)
                            }
                            .padding(.vertical, 7)
                        }
                        .onDelete(perform: history.remove)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("السجل")
            .toolbar {
                if !history.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("مسح الكل", role: .destructive) { history.clear() }
                    }
                }
            }
        }
    }
}
