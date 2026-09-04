import AVFoundation
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    struct Item: Identifiable, Codable, Equatable {
        let id: UUID
        let fileName: String
        let createdAt: Date
        let width: Int
        let height: Int
        let fps: Double
        let duration: Double
        let bytes: Int64
        let title: String

        var resolutionText: String { "\(width)×\(height)" }
        var fpsText: String { String(format: "%.0f FPS", fps) }
        var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        var durationText: String {
            let total = max(0, Int(duration.rounded()))
            return String(format: "%d:%02d", total / 60, total % 60)
        }
    }

    @Published private(set) var items: [Item] = []

    private let fm = FileManager.default
    private let folderName = "ScreenFlowLibrary"
    private let indexName = "library.json"

    init() { load() }

    private var folderURL: URL {
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private var indexURL: URL { folderURL.appendingPathComponent(indexName) }

    func url(for item: Item) -> URL { folderURL.appendingPathComponent(item.fileName) }

    func add(sourceURL: URL, info: VideoModel.Info) throws -> Item {
        let id = UUID()
        let fileName = "ScreenFlow_\(Int(Date().timeIntervalSince1970))_\(id.uuidString.prefix(6)).mp4"
        let destination = folderURL.appendingPathComponent(fileName)
        try? fm.removeItem(at: destination)
        try fm.copyItem(at: sourceURL, to: destination)
        let attrs = try? fm.attributesOfItem(atPath: destination.path)
        let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? info.bytes
        let item = Item(id: id, fileName: fileName, createdAt: Date(), width: info.width, height: info.height,
                        fps: info.fps, duration: info.duration, bytes: bytes,
                        title: "\(Int(info.fps.rounded())) FPS · \(info.width)×\(info.height)")
        items.insert(item, at: 0)
        persist()
        return item
    }

    func delete(_ item: Item) {
        try? fm.removeItem(at: url(for: item))
        items.removeAll { $0.id == item.id }
        persist()
    }

    func removeMissingFiles() {
        items.removeAll { !fm.fileExists(atPath: url(for: $0).path) }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else {
            items = []
            return
        }
        items = decoded.filter { fm.fileExists(atPath: url(for: $0).path) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
