import Foundation

struct PlantHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let diagnosis: PlantDiagnosis
    let persona: PlantPersonaMessage?
}

@MainActor
final class PlantHistoryStore: ObservableObject {
    @Published private(set) var entries: [PlantHistoryEntry] = []
    private let key = "plant.persona.history.v1"

    init() { load() }

    func add(diagnosis: PlantDiagnosis, persona: PlantPersonaMessage?) {
        let item = PlantHistoryEntry(id: UUID(), date: Date(), diagnosis: diagnosis, persona: persona)
        entries.insert(item, at: 0)
        if entries.count > 30 { entries = Array(entries.prefix(30)) }
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
              let decoded = try? JSONDecoder().decode([PlantHistoryEntry].self, from: data) else { return }
        entries = decoded
    }
}
