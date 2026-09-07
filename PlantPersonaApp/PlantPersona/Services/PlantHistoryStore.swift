import Foundation

struct AnalysisHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let analysis: VisualAnalysis
}

@MainActor
final class PlantHistoryStore: ObservableObject {
    @Published private(set) var entries: [AnalysisHistoryEntry] = []
    private let key = "ayn.visual.history.v1"

    init() { load() }

    func add(analysis: VisualAnalysis) {
        let item = AnalysisHistoryEntry(id: UUID(), date: Date(), analysis: analysis)
        entries.insert(item, at: 0)
        if entries.count > 40 { entries = Array(entries.prefix(40)) }
        save()
    }

    func clear() {
        entries = []
        UserDefaults.standard.removeObject(forKey: key)
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where entries.indices.contains(index) {
            entries.remove(at: index)
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AnalysisHistoryEntry].self, from: data) else { return }
        entries = decoded
    }
}
