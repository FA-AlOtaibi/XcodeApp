import SwiftUI
import Foundation
import UIKit
import Photos
import AVFoundation
import AVKit
import PhotosUI
import UniformTypeIdentifiers

@main
struct HammelApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(model.appearance.colorScheme)
        }
    }
}

enum PlatformKind: String, Codable { case tiktok = "TikTok", youtube = "YouTube", x = "X", instagram = "Instagram", facebook = "Facebook", generic = "Web" }
enum SaveTarget: String, CaseIterable, Identifiable { case app = "داخل التطبيق", photos = "الصور", ask = "اسألني كل مرة"; var id: String { rawValue } }
enum AppearanceMode: String, CaseIterable, Identifiable { case system = "النظام", light = "فاتح", dark = "داكن"; var id: String { rawValue }; var colorScheme: ColorScheme? { self == .system ? nil : (self == .dark ? .dark : .light) } }
enum MediaFilter: String, CaseIterable, Identifiable { case all = "الكل", image = "صور", video = "فيديو", audio = "صوت", document = "مستندات"; var id: String { rawValue } }
enum SortMode: String, CaseIterable, Identifiable { case newest = "الأحدث", oldest = "الأقدم", name = "الاسم", size = "الحجم"; var id: String { rawValue } }
enum NoticeStyle { case success, error, info }
struct Notice: Identifiable { let id = UUID(); let text: String; let style: NoticeStyle }
enum AppError: Error { case message(String); var text: String { if case let .message(v) = self { return v }; return "تعذر إكمال العملية." } }

struct DownloadMedia: Identifiable, Hashable {
    let id = UUID(); let url: URL; let filename: String; let type: String; let thumb: URL?; let referer: String?; let platform: PlatformKind
    var quality: String = "أصلي"; var estimatedSize: Int64? = nil; var hasAudio: Bool = true
}

struct LocalMedia: Identifiable, Hashable {
    let id: String; let url: URL; let createdAt: Date; let size: Int64
    init(url: URL, createdAt: Date, size: Int64) { self.id = url.path; self.url = url; self.createdAt = createdAt; self.size = size }
    var ext: String { url.pathExtension.lowercased() }
    var isImage: Bool { ["jpg","jpeg","png","webp","heic"].contains(ext) }
    var isVideo: Bool { ["mp4","mov","m4v"].contains(ext) }
    var isAudio: Bool { ["mp3","m4a","aac","wav"].contains(ext) }
}

enum DownloadState: String { case waiting = "بانتظار", downloading = "جارٍ التنزيل", done = "مكتمل", failed = "فشل" }
struct DownloadJob: Identifiable { let id = UUID(); let item: DownloadMedia; var state: DownloadState = .waiting; var progress: Double = 0; var createdAt = Date(); var error: String? }

@MainActor
final class AppModel: ObservableObject {
    @Published var input = ""
    @Published var isResolving = false
    @Published var results: [DownloadMedia] = []
    @Published var library: [LocalMedia] = []
    @Published var jobs: [DownloadJob] = []
    @Published var notice: Notice?
    @Published var saveTarget: SaveTarget
    @Published var appearance: AppearanceMode
    @Published var cacheBytes: Int64 = 0
    @Published var libraryBytes: Int64 = 0
    @Published var favoritePaths: Set<String>

    let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1"

    init() {
        saveTarget = SaveTarget(rawValue: UserDefaults.standard.string(forKey: "saveTarget") ?? "") ?? .app
        appearance = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        favoritePaths = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        configureAudio(); refreshStorage()
    }

    func configureAudio() {
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay]); try AVAudioSession.sharedInstance().setActive(true) } catch { }
    }
    func setAppearance(_ a: AppearanceMode) { appearance = a; UserDefaults.standard.set(a.rawValue, forKey: "appearance") }
    func setSaveTarget(_ t: SaveTarget) { saveTarget = t; UserDefaults.standard.set(t.rawValue, forKey: "saveTarget") }
    func show(_ text: String, _ style: NoticeStyle = .info) { notice = Notice(text: text, style: style); Task { try? await Task.sleep(for: .seconds(2.2)); if self.notice?.text == text { self.notice = nil } } }
    func clearTransientState() { notice = nil }

    func resolve() async {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = URL(string: raw), source.scheme?.hasPrefix("http") == true else { show("الرابط غير صحيح", .error); return }
        isResolving = true; results = []; notice = nil; defer { isResolving = false }
        do {
            let p = detect(source)
            let media: [DownloadMedia]
            switch p {
            case .tiktok: media = try await resolveTikTok(source)
            case .youtube: media = try await resolveYouTubeV2(source)
            case .x: media = try await resolveX(source)
            case .instagram: media = try await resolveMeta(source, .instagram)
            case .facebook: media = try await resolveMeta(source, .facebook)
            case .generic: media = try await resolveMeta(source, .generic)
            }
            guard !media.isEmpty else { throw AppError.message("لم أجد وسائط في الرابط") }
            results = media
        } catch { show(readable(error), .error) }
    }

    func enqueue(_ item: DownloadMedia, filename: String? = nil, target: SaveTarget? = nil) async {
        let chosen = target ?? saveTarget
        guard chosen != .ask else { return }
        let job = DownloadJob(item: item)
        jobs.insert(job, at: 0)
        let jobID = job.id
        setJob(jobID, state: .downloading, progress: 0.08)
        do {
            var req = URLRequest(url: item.url); req.timeoutInterval = 180; req.setValue(ua, forHTTPHeaderField: "User-Agent"); if let r = item.referer { req.setValue(r, forHTTPHeaderField: "Referer") }
            let (tmp, response) = try await URLSession.shared.download(for: req)
            guard let h = response as? HTTPURLResponse, (200..<400).contains(h.statusCode) else { throw URLError(.badServerResponse) }
            setJob(jobID, state: .downloading, progress: 0.86)
            let desired = filename?.trimmingCharacters(in: .whitespacesAndNewlines)
            let final = applyingExtension(from: item.filename, to: (desired?.isEmpty == false ? desired! : item.filename))
            let saved = try persist(tmp, final)
            if chosen == .photos { try await saveToPhotos(saved) }
            setJob(jobID, state: .done, progress: 1)
            refreshStorage(); show(chosen == .photos ? "تم الحفظ في الصور" : "تم التنزيل", .success)
        } catch { setJob(jobID, state: .failed, progress: 0, error: readable(error)); show("فشل التنزيل", .error) }
    }

    private func setJob(_ id: UUID, state: DownloadState, progress: Double, error: String? = nil) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }; jobs[i].state = state; jobs[i].progress = progress; jobs[i].error = error
    }

    func saveExistingToPhotos(_ url: URL) async { do { try await saveToPhotos(url); show("تم الحفظ في الصور", .success) } catch { show(readable(error), .error) } }
    func importFile(_ src: URL) { do { let access = src.startAccessingSecurityScopedResource(); defer { if access { src.stopAccessingSecurityScopedResource() } }; let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(src.lastPathComponent); try? FileManager.default.removeItem(at: tmp); try FileManager.default.copyItem(at: src, to: tmp); _ = try persist(tmp, src.lastPathComponent); refreshStorage(); show("تم الاستيراد", .success) } catch { show("تعذر استيراد الملف", .error) } }
    func importImageData(_ data: Data, ext: String = "jpg") { let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("imported-\(Int(Date().timeIntervalSince1970)).\(ext)"); do { try data.write(to: tmp); _ = try persist(tmp, tmp.lastPathComponent); refreshStorage(); show("تم الاستيراد", .success) } catch { show("تعذر الاستيراد", .error) } }
    func importVideoURL(_ src: URL) { importFile(src) }

    func renameLocal(_ item: LocalMedia, to newName: String) {
        var n = sanitize(newName.trimmingCharacters(in: .whitespacesAndNewlines)); guard !n.isEmpty else { return }
        if (n as NSString).pathExtension.isEmpty && !item.ext.isEmpty { n += ".\(item.ext)" }
        var dst = item.url.deletingLastPathComponent().appendingPathComponent(n), counter = 2
        while FileManager.default.fileExists(atPath: dst.path) { let b = (n as NSString).deletingPathExtension, e = (n as NSString).pathExtension; dst = item.url.deletingLastPathComponent().appendingPathComponent("\(b)-\(counter).\(e)"); counter += 1 }
        do { try FileManager.default.moveItem(at: item.url, to: dst); if favoritePaths.remove(item.url.path) != nil { favoritePaths.insert(dst.path); persistFavorites() }; refreshStorage(); show("تم تغيير الاسم", .success) } catch { show("تعذر تغيير الاسم", .error) }
    }
    func deleteLocal(_ item: LocalMedia) { try? FileManager.default.removeItem(at: item.url); favoritePaths.remove(item.url.path); persistFavorites(); refreshStorage(); show("تم الحذف", .success) }
    func toggleFavorite(_ item: LocalMedia) { if favoritePaths.contains(item.url.path) { favoritePaths.remove(item.url.path) } else { favoritePaths.insert(item.url.path) }; persistFavorites() }
    func isFavorite(_ item: LocalMedia) -> Bool { favoritePaths.contains(item.url.path) }
    private func persistFavorites() { UserDefaults.standard.set(Array(favoritePaths), forKey: "favorites") }

    func clearCache() { URLCache.shared.removeAllCachedResponses(); let fm = FileManager.default; for d in [fm.temporaryDirectory, fm.urls(for: .cachesDirectory, in: .userDomainMask).first].compactMap({$0}) { if let u = try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) { u.forEach { try? fm.removeItem(at: $0) } } }; refreshStorage(); show("تم تنظيف الكاش", .success) }
    func deleteAllAppFiles() { let f = mediaFolder(); try? FileManager.default.removeItem(at: f); try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true); favoritePaths = []; persistFavorites(); refreshStorage(); show("تم حذف الملفات", .success) }
    func deleteOlderThan30Days() { let cutoff = Date().addingTimeInterval(-30*86400); library.filter { $0.createdAt < cutoff }.forEach { try? FileManager.default.removeItem(at: $0.url) }; refreshStorage(); show("تم حذف الملفات القديمة", .success) }
    func removeDuplicates() { var seen: [String: URL] = [:]; var removed = 0; for item in library { if let data = try? Data(contentsOf: item.url, options: .mappedIfSafe) { let key = "\(item.size)-\(data.prefix(128).hashValue)"; if seen[key] != nil { try? FileManager.default.removeItem(at: item.url); removed += 1 } else { seen[key] = item.url } } }; refreshStorage(); show(removed > 0 ? "تم حذف \(removed) ملف مكرر" : "لا توجد ملفات مكررة", .success) }

    func refreshStorage() {
        let f = mediaFolder(); try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: f, includingPropertiesForKeys: [.creationDateKey,.fileSizeKey])) ?? []
        library = urls.filter { !$0.hasDirectoryPath }.map { let v = try? $0.resourceValues(forKeys: [.creationDateKey,.fileSizeKey]); return LocalMedia(url: $0, createdAt: v?.creationDate ?? .distantPast, size: Int64(v?.fileSize ?? 0)) }.sorted { $0.createdAt > $1.createdAt }
        libraryBytes = library.reduce(0) { $0 + $1.size }
        let fm = FileManager.default; cacheBytes = directorySize(fm.temporaryDirectory) + (fm.urls(for: .cachesDirectory, in: .userDomainMask).first.map(directorySize) ?? 0)
    }
    func formattedBytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    func detect(_ u: URL) -> PlatformKind { let h = (u.host ?? "").lowercased(); if h.contains("tiktok") { return .tiktok }; if h.contains("youtube") || h.contains("youtu.be") { return .youtube }; if h == "x.com" || h.contains("twitter.com") { return .x }; if h.contains("instagram") { return .instagram }; if h.contains("facebook") || h.contains("fb.watch") { return .facebook }; return .generic }
    func mediaFolder() -> URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel", isDirectory: true) }
    func persist(_ tmp: URL, _ filename: String) throws -> URL { let f = mediaFolder(); try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true); var name = sanitize(filename); if (name as NSString).pathExtension.isEmpty { name += ".mp4" }; var dst = f.appendingPathComponent(name), n = 2; while FileManager.default.fileExists(atPath: dst.path) { let b = (name as NSString).deletingPathExtension, e = (name as NSString).pathExtension; dst = f.appendingPathComponent("\(b)-\(n).\(e)"); n += 1 }; try FileManager.default.moveItem(at: tmp, to: dst); return dst }
    func sanitize(_ s: String) -> String { let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>"); let x = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines); return x.isEmpty ? "media" : String(x.prefix(120)) }
    func applyingExtension(from source: String, to wanted: String) -> String { let ext = (source as NSString).pathExtension; return ((wanted as NSString).pathExtension.isEmpty && !ext.isEmpty) ? "\(wanted).\(ext)" : wanted }
    func readable(_ e: Error) -> String { if let a = e as? AppError { return a.text }; if let u = e as? URLError { if u.code == .timedOut { return "انتهت مهلة الاتصال" }; if u.code == .notConnectedToInternet { return "لا يوجد اتصال بالإنترنت" } }; return "تعذر إكمال العملية" }
    private func directorySize(_ u: URL) -> Int64 { guard let en = FileManager.default.enumerator(at: u, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }; var t:Int64 = 0; for case let f as URL in en { t += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }; return t }
    private func saveToPhotos(_ u: URL) async throws { let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly); guard status == .authorized || status == .limited else { throw AppError.message("اسمح للتطبيق بالوصول إلى الصور") }; try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void,Error>) in PHPhotoLibrary.shared().performChanges({ if ["mp4","mov","m4v"].contains(u.pathExtension.lowercased()) { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: u) } else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: u) } }) { ok,e in ok ? c.resume() : c.resume(throwing: e ?? AppError.message("تعذر الحفظ")) } } }
}
