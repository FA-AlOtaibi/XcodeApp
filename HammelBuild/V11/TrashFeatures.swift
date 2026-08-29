import SwiftUI
import Foundation

extension AppModel {
    func trashFolder() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hammel-Trash", isDirectory: true)
    }

    func moveToTrash(_ item: LocalMedia) {
        do {
            let fm = FileManager.default
            let folder = trashFolder()
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = Int(Date().timeIntervalSince1970)
            let safe = item.url.lastPathComponent.replacingOccurrences(of: "__", with: "_")
            var dst = folder.appendingPathComponent("trash-\(stamp)__\(safe)")
            var n = 2
            while fm.fileExists(atPath: dst.path) {
                dst = folder.appendingPathComponent("trash-\(stamp)-\(n)__\(safe)")
                n += 1
            }
            try fm.moveItem(at: item.url, to: dst)
            favoritePaths.remove(item.url.path)
            UserDefaults.standard.set(Array(favoritePaths), forKey: "favorites")
            refreshStorage()
            show("نُقل إلى سلة المهملات", .success)
        } catch {
            show("تعذر نقل الملف إلى السلة", .error)
        }
    }

    func trashItems() -> [LocalMedia] {
        purgeExpiredTrash()
        let fm = FileManager.default
        let folder = trashFolder()
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])) ?? []
        return urls.filter { !$0.hasDirectoryPath }.map {
            let v = try? $0.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            return LocalMedia(url: $0, createdAt: v?.creationDate ?? .distantPast, size: Int64(v?.fileSize ?? 0))
        }.sorted { deletionDate(for: $0.url) > deletionDate(for: $1.url) }
    }

    func restoreFromTrash(_ item: LocalMedia) {
        do {
            let original = originalTrashName(item.url)
            let folder = mediaFolder()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var dst = folder.appendingPathComponent(original)
            var n = 2
            while FileManager.default.fileExists(atPath: dst.path) {
                let base = (original as NSString).deletingPathExtension
                let ext = (original as NSString).pathExtension
                dst = folder.appendingPathComponent(ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)")
                n += 1
            }
            try FileManager.default.moveItem(at: item.url, to: dst)
            refreshStorage()
            show("تم استرجاع الملف", .success)
        } catch {
            show("تعذر استرجاع الملف", .error)
        }
    }

    func deleteTrashPermanently(_ item: LocalMedia) {
        try? FileManager.default.removeItem(at: item.url)
        show("تم الحذف نهائيًا", .success)
    }

    func emptyTrash() {
        let fm = FileManager.default
        let folder = trashFolder()
        if let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            urls.forEach { try? fm.removeItem(at: $0) }
        }
        show("تم إفراغ سلة المهملات", .success)
    }

    func purgeExpiredTrash() {
        let fm = FileManager.default
        let folder = trashFolder()
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        let cutoff = Date().addingTimeInterval(-15 * 86400)
        for url in urls where deletionDate(for: url) < cutoff {
            try? fm.removeItem(at: url)
        }
    }

    func trashRemainingText(_ item: LocalMedia) -> String {
        let age = Date().timeIntervalSince(deletionDate(for: item.url))
        let days = max(0, 15 - Int(age / 86400))
        return days == 0 ? "سيُحذف قريبًا" : "يبقى \(days) يوم"
    }

    private func deletionDate(for url: URL) -> Date {
        let name = url.lastPathComponent
        guard name.hasPrefix("trash-"), let marker = name.range(of: "__") else {
            return (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        }
        let raw = String(name[name.index(name.startIndex, offsetBy: 6)..<marker.lowerBound])
        let epochPart = raw.split(separator: "-").first.flatMap { Double($0) } ?? Date().timeIntervalSince1970
        return Date(timeIntervalSince1970: epochPart)
    }

    private func originalTrashName(_ url: URL) -> String {
        let name = url.lastPathComponent
        guard let marker = name.range(of: "__") else { return name }
        return String(name[marker.upperBound...])
    }
}

struct TrashView: View {
    @ObservedObject var model: AppModel
    @State private var items: [LocalMedia] = []
    @State private var confirmEmpty = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if items.isEmpty {
                    ContentUnavailableView("السلة فارغة", systemImage: "trash", description: Text("الملفات المحذوفة تبقى هنا 15 يومًا"))
                        .padding(.top, 80)
                } else {
                    HStack {
                        Text("تُحذف تلقائيًا بعد 15 يومًا").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("إفراغ السلة", role: .destructive) { confirmEmpty = true }
                    }
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            LocalThumb(item: item).frame(width: 64, height: 58).clipShape(RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(displayName(item.url)).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text("\(model.formattedBytes(item.size)) • \(model.trashRemainingText(item))").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("استرجاع", systemImage: "arrow.uturn.backward") { model.restoreFromTrash(item); reload() }
                                Button("حذف نهائي", systemImage: "trash", role: .destructive) { model.deleteTrashPermanently(item); reload() }
                            } label: {
                                Image(systemName: "ellipsis").frame(width: 40, height: 40)
                            }
                        }
                        .padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }.padding(16)
        }
        .navigationTitle("سلة المهملات")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .confirmationDialog("حذف جميع الملفات نهائيًا؟", isPresented: $confirmEmpty) {
            Button("حذف الكل", role: .destructive) { model.emptyTrash(); reload() }
        }
    }

    private func reload() { items = model.trashItems() }
    private func displayName(_ url: URL) -> String {
        let name = url.lastPathComponent
        guard let r = name.range(of: "__") else { return name }
        return String(name[r.upperBound...])
    }
}

struct MediaQuickActionsSheet: View {
    @ObservedObject var model: AppModel
    let item: LocalMedia
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 12) {
                        LocalThumb(item: item).frame(width: 72, height: 64).clipShape(RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.url.deletingPathExtension().lastPathComponent).font(.headline).lineLimit(2)
                            Text(model.formattedBytes(item.size)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        if item.isVideo {
                            QuickAction(title: "فيديو → GIF", icon: "photo.stack") { run { await model.videoToGIF(item) } }
                            QuickAction(title: "استخراج الصوت", icon: "waveform") { run { await model.extractAudio(from: item) } }
                            QuickAction(title: "تقليل الصوت البشري", icon: "person.wave.2") { run { await model.separateCenterAudio(from: item, keepVoice: false) } }
                            QuickAction(title: "عزل الكلام", icon: "mic") { run { await model.separateCenterAudio(from: item, keepVoice: true) } }
                            QuickAction(title: "نسخة 720p", icon: "arrow.down.right.and.arrow.up.left") { run { await model.compress720(from: item) } }
                            QuickAction(title: "لقطة وسطية", icon: "photo") { run { await model.grabMiddleFrame(from: item) } }
                            QuickAction(title: "لوحة 9 لقطات", icon: "square.grid.3x3") { run { await model.contactSheet(from: item) } }
                            NavigationLink { MediaEditorView(sourceURL: item.url, model: model) } label: { QuickActionLabel(title: "قص وتعديل", icon: "slider.horizontal.3") }
                        }
                        if item.ext == "gif" {
                            QuickAction(title: "GIF → فيديو", icon: "film") { run { await model.gifToVideo(item) } }
                        }
                        if item.isImage || item.isVideo {
                            QuickAction(title: "تنظيف الخصوصية", icon: "shield") { run { await model.privacyCleanCopy(from: item) } }
                            QuickAction(title: "إرسال إلى Snapchat", icon: "paperplane") { model.prepareForSnapchat(item) }
                            QuickAction(title: "حفظ في الصور", icon: "photo.badge.plus") { run { await model.saveExistingToPhotos(item.url) } }
                        }
                        QuickAction(title: "اسم مرتب", icon: "textformat") { model.autoRename(item); dismiss() }
                    }

                    ShareLink(item: item.url) {
                        Label("مشاركة للتطبيقات", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).padding(14)
                    }.buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        model.moveToTrash(item)
                        dismiss()
                    } label: {
                        Label("نقل إلى سلة المهملات", systemImage: "trash")
                            .frame(maxWidth: .infinity).padding(14)
                    }

                    if busy { ProgressView("جارٍ تنفيذ العملية…").padding(.top, 8) }
                }.padding(18)
            }
            .navigationTitle("أدوات الملف")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func run(_ op: @escaping () async -> Void) {
        busy = true
        Task { await op(); busy = false }
    }
}

struct QuickAction: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { QuickActionLabel(title: title, icon: icon) }
        .buttonStyle(.plain)
    }
}

struct QuickActionLabel: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.title2)
            Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(15)
        .frame(minHeight: 98)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 19))
    }
}
