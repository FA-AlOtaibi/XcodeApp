import Foundation

enum AYNMode: String, CaseIterable, Identifiable {
    case see = "شوف"
    case inspect = "افحص"
    case car = "سيارة"
    case ask = "اسأل"
    var id: String { rawValue }
}

struct AYNProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var kind: String
    var createdAt: Date
    var notes: String
}

struct AYNTimelineEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let profileID: UUID
    let date: Date
    let title: String
    let detail: String
    let severity: String
}

@MainActor
final class AYNWorkspaceStore: ObservableObject {
    @Published private(set) var profiles: [AYNProfile] = []
    @Published private(set) var events: [AYNTimelineEvent] = []
    private let profileKey = "ayn.workspace.profiles.v1"
    private let eventKey = "ayn.workspace.events.v1"

    init() { load() }

    func addProfile(name: String, kind: String, notes: String = "") -> AYNProfile {
        let p = AYNProfile(id: UUID(), name: name, kind: kind, createdAt: Date(), notes: notes)
        profiles.insert(p, at: 0); save(); return p
    }

    func addEvent(profileID: UUID, title: String, detail: String, severity: String = "info") {
        events.insert(AYNTimelineEvent(id: UUID(), profileID: profileID, date: Date(), title: title, detail: detail, severity: severity), at: 0)
        if events.count > 200 { events = Array(events.prefix(200)) }
        save()
    }

    func events(for profileID: UUID) -> [AYNTimelineEvent] { events.filter { $0.profileID == profileID } }

    func removeProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }; events.removeAll { $0.profileID == id }; save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(d, forKey: profileKey) }
        if let d = try? JSONEncoder().encode(events) { UserDefaults.standard.set(d, forKey: eventKey) }
    }

    private func load() {
        if let d = UserDefaults.standard.data(forKey: profileKey), let x = try? JSONDecoder().decode([AYNProfile].self, from: d) { profiles = x }
        if let d = UserDefaults.standard.data(forKey: eventKey), let x = try? JSONDecoder().decode([AYNTimelineEvent].self, from: d) { events = x }
    }
}
