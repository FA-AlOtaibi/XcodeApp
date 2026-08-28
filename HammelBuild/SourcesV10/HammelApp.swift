import SwiftUI
import Foundation
import UIKit
import Photos
import PhotosUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers

// MARK: - App

@main
struct HammelApp: App {
    @AppStorage("appearance") private var appearance = "system"

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}

// MARK: - Models

enum PlatformKind: String {
    case tiktok = "TikTok", youtube = "YouTube", x = "X", instagram = "Instagram", facebook = "Facebook", generic = "Web"
}

enum SaveTarget: String, CaseIterable, Identifiable {
    case app = "داخل التطبيق", photos = "الصور", ask = "اسألني كل مرة"
    var id: String { rawValue }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "الكل", photos = "صور", videos = "فيديو", audio = "صوت", documents = "مستندات"
    var id: String { rawValue }
}

enum AppError: Error {
    case message(String)
    var text: String { if case let .message(v) = self { return v }; return "حدث خطأ." }
}

struct DownloadMedia: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let filename: String
    let type: String
    let thumb: URL?
    let referer: String?
    let platform: PlatformKind
}

struct LocalItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let createdAt: Date
    let size: Int64
    var isFolder: Bool { url.hasDirectoryPath }
    var ext: String { url.pathExtension.lowercased() }
    var isImage: Bool { ["jpg","jpeg","png","webp","heic","gif"].contains(ext) }
    var isVideo: Bool { ["mp4","mov","m4v"].contains(ext) }
    var isAudio: Bool { ["mp3","m4a","aac","wav","caf"].contains(ext) }
    var isDocument: Bool { !isFolder && !isImage && !isVideo && !isAudio }
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {
    @Published var input = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var results: [DownloadMedia] = []
    @Published var library: [LocalItem] = []
    @Published var toast: String?
    @Published var detectedPlatform = "تلقائي"
    @Published var activeEngine = "جاهز"
    @Published var cacheBytes: Int64 = 0
    @Published var libraryBytes: Int64 = 0
    @Published var saveTarget: SaveTarget = SaveTarget(rawValue: UserDefaults.standard.string(forKey: "saveTarget") ?? "") ?? .app

    private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1"

    init() { refreshLibrary(); refreshStorage() }

    func setSaveTarget(_ target: SaveTarget) {
        saveTarget = target
        UserDefaults.standard.set(target.rawValue, forKey: "saveTarget")
    }

    func resolve() async {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = URL(string: raw), source.scheme?.hasPrefix("http") == true else {
            error = "الصق رابطًا صحيحًا."
            return
        }
        isLoading = true; error = nil; toast = nil; results = []
        let p = detect(source)
        detectedPlatform = p.rawValue
        activeEngine = "جاري التحليل"
        defer { isLoading = false }

        do {
            let media: [DownloadMedia]
            switch p {
            case .tiktok: media = try await resolveTikTok(source); activeEngine = "TikTok"
            case .youtube: media = try await resolveYouTube(source); activeEngine = "YouTube"
            case .x: media = try await resolveX(source); activeEngine = "X"
            case .instagram: media = try await resolveMeta(source, .instagram); activeEngine = "Instagram"
            case .facebook: media = try await resolveMeta(source, .facebook); activeEngine = "Facebook"
            case .generic: media = try await resolveMeta(source, .generic); activeEngine = "Web"
            }
            guard !media.isEmpty else { throw AppError.message("لم أجد وسائط قابلة للتنزيل.") }
            results = media
        } catch let caught {
            error = readable(caught)
            activeEngine = "تعذر الجلب"
        }
    }

    func clearResolved() { results = []; error = nil; activeEngine = "جاهز"; detectedPlatform = "تلقائي" }

    func download(_ item: DownloadMedia, name: String? = nil, target: SaveTarget? = nil) async {
        let destination = target ?? saveTarget
        if destination == .ask { return }
        isLoading = true; error = nil; toast = nil
        defer { isLoading = false }

        do {
            var req = URLRequest(url: item.url)
            req.timeoutInterval = 120
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
            if let referer = item.referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
            let (tmp, response) = try await URLSession.shared.download(for: req)
            guard let h = response as? HTTPURLResponse, (200..<400).contains(h.statusCode) else { throw URLError(.badServerResponse) }
            let desired = applyingExtension(from: item.filename, to: name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? item.filename)
            let saved = try persist(tmp, desired)
            refreshStorage()
            if destination == .photos {
                try await saveToPhotos(saved)
                toast = "تم الحفظ في الصور"
            } else {
                toast = "تم الحفظ في المكتبة"
            }
        } catch let caught { error = readable(caught) }
    }

    func downloadAll(_ items: [DownloadMedia], baseName: String, target: SaveTarget) async {
        for (idx, item) in items.enumerated() {
            let ext = (item.filename as NSString).pathExtension.isEmpty ? (item.type == "photo" ? "jpg" : "mp4") : (item.filename as NSString).pathExtension
            await download(item, name: "\(baseName)-\(idx + 1).\(ext)", target: target)
        }
    }

    func importPhotoItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var imported = 0
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first
                let ext = type?.preferredFilenameExtension ?? "jpg"
                let dst = uniqueURL(in: mediaFolder(), name: "imported-\(Int(Date().timeIntervalSince1970))-\(imported + 1).\(ext)")
                try data.write(to: dst, options: .atomic)
                imported += 1
            } catch { self.error = error.localizedDescription }
        }
        refreshStorage()
        if imported > 0 { toast = "تم استيراد \(imported) عنصر" }
    }

    func importCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
        do {
            let dst = uniqueURL(in: mediaFolder(), name: "camera-\(Int(Date().timeIntervalSince1970)).jpg")
            try data.write(to: dst, options: .atomic)
            refreshStorage(); toast = "تم حفظ الصورة"
        } catch { self.error = error.localizedDescription }
    }

    func createFolder(named name: String) {
        let trimmed = sanitize(name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { return }
        let url = uniqueFolderURL(name: trimmed)
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); refreshLibrary(); toast = "تم إنشاء المجلد" }
        catch { self.error = error.localizedDescription }
    }

    func rename(_ item: LocalItem, to name: String) {
        let trimmed = sanitize(name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { return }
        var final = trimmed
        if !item.isFolder && (final as NSString).pathExtension.isEmpty && !item.ext.isEmpty { final += ".\(item.ext)" }
        let dst = uniqueURL(in: item.url.deletingLastPathComponent(), name: final, excluding: item.url)
        do { try FileManager.default.moveItem(at: item.url, to: dst); refreshStorage(); toast = "تم تغيير الاسم" }
        catch { self.error = error.localizedDescription }
    }

    func delete(_ item: LocalItem) {
        do { try FileManager.default.removeItem(at: item.url); refreshStorage(); toast = "تم الحذف" }
        catch { self.error = error.localizedDescription }
    }

    func delete(_ items: [LocalItem]) {
        for item in items { try? FileManager.default.removeItem(at: item.url) }
        refreshStorage(); toast = "تم حذف العناصر المحددة"
    }

    func saveExistingToPhotos(_ url: URL) async {
        error = nil
        do { try await saveToPhotos(url); toast = "تم الحفظ في الصور" }
        catch let caught { error = readable(caught) }
    }

    func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        let fm = FileManager.default
        for dir in [fm.temporaryDirectory, fm.urls(for: .cachesDirectory, in: .userDomainMask).first].compactMap({ $0 }) {
            if let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for child in children { try? fm.removeItem(at: child) }
            }
        }
        refreshStorage(); toast = "تم حذف الكاش"
    }

    func deleteAllAppFiles() {
        let folder = mediaFolder()
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refreshStorage(); toast = "تم حذف جميع الملفات"
    }

    func refreshLibrary() {
        let folder = mediaFolder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey,.fileSizeKey,.isDirectoryKey])) ?? []
        library = urls.map { url in
            let v = try? url.resourceValues(forKeys: [.creationDateKey,.fileSizeKey,.isDirectoryKey])
            return LocalItem(url: url, createdAt: v?.creationDate ?? .distantPast, size: Int64(v?.fileSize ?? 0))
        }.sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            return $0.createdAt > $1.createdAt
        }
        libraryBytes = directorySize(folder)
    }

    func refreshStorage() {
        refreshLibrary()
        let fm = FileManager.default
        cacheBytes = directorySize(fm.temporaryDirectory) + (fm.urls(for: .cachesDirectory, in: .userDomainMask).first.map(directorySize) ?? 0)
    }

    func formattedBytes(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    // MARK: Resolver

    private func detect(_ u: URL) -> PlatformKind {
        let h = (u.host ?? "").lowercased()
        if h.contains("tiktok") { return .tiktok }
        if h.contains("youtube") || h.contains("youtu.be") { return .youtube }
        if h == "x.com" || h.contains("twitter.com") { return .x }
        if h.contains("instagram") { return .instagram }
        if h.contains("facebook") || h.contains("fb.watch") { return .facebook }
        return .generic
    }

    private func resolveTikTok(_ source: URL) async throws -> [DownloadMedia] {
        let (html, final) = try await fetchHTML(source, "https://www.tiktok.com/")
        var roots: [Any] = []
        for pattern in [#"<script[^>]*id=[\"']__UNIVERSAL_DATA_FOR_REHYDRATION__[\"'][^>]*>(.*?)</script>"#, #"<script[^>]*id=[\"']SIGI_STATE[\"'][^>]*>(.*?)</script>"#] {
            if let raw = regexFirst(html, pattern), let data = raw.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) { roots.append(obj) }
        }

        for root in roots {
            let images = tikTokImages(in: root)
            if !images.isEmpty {
                let id = firstString(in: root, keys: ["id","itemId","aweme_id"]) ?? "post"
                return images.enumerated().map { i, u in DownloadMedia(url: u, filename: "tiktok-\(id)-\(i + 1).jpg", type: "photo", thumb: u, referer: final.absoluteString, platform: .tiktok) }
            }
        }
        for root in roots {
            if let play = firstURL(in: root, keys: ["playAddr","playAddrH264"]), let u = URL(string: play) {
                let cover = firstURL(in: root, keys: ["cover","originCover"]).flatMap(URL.init(string:))
                let id = firstString(in: root, keys: ["id","itemId"]) ?? UUID().uuidString
                return [DownloadMedia(url: u, filename: "tiktok-\(id).mp4", type: "video", thumb: cover, referer: "https://www.tiktok.com/", platform: .tiktok)]
            }
        }
        if let raw = regexFirst(html, #"\"playAddr\"\s*:\s*\"([^\"]+)\""#), let u = URL(string: decodeEscapedURL(raw)) {
            return [DownloadMedia(url: u, filename: "tiktok-video.mp4", type: "video", thumb: nil, referer: final.absoluteString, platform: .tiktok)]
        }
        throw AppError.message("تعذر استخراج محتوى TikTok.")
    }

    private func tikTokImages(in value: Any) -> [URL] {
        var found: [URL] = []
        func walk(_ v: Any) {
            if let d = v as? [String: Any] {
                if let imagePost = d["imagePost"] as? [String: Any], let images = imagePost["images"] as? [[String: Any]] {
                    for image in images { if let s = firstURL(in: image, keys: ["displayImage","ownerWatermarkImage","imageURL","imageUrl"]), let u = URL(string: s) { found.append(u) } }
                }
                if let images = d["images"] as? [[String: Any]], d["video"] == nil {
                    for image in images { if let s = firstURL(in: image, keys: ["displayImage","imageURL","imageUrl"]), let u = URL(string: s) { found.append(u) } }
                }
                for child in d.values { walk(child) }
            } else if let a = v as? [Any] { for child in a { walk(child) } }
        }
        walk(value)
        var seen = Set<String>()
        return found.filter { seen.insert($0.absoluteString).inserted }
    }

    private func resolveYouTube(_ source: URL) async throws -> [DownloadMedia] {
        guard let id = youtubeID(source) else { throw AppError.message("لم أتعرف على رابط YouTube.") }
        if let direct = try? await youtubeWatch(id), !direct.isEmpty { return direct }
        return try await youtubeInvidious(id)
    }

    private func youtubeWatch(_ id: String) async throws -> [DownloadMedia] {
        let watch = URL(string: "https://www.youtube.com/watch?v=\(id)&hl=en&gl=US&bpctr=9999999999")!
        let (html, _) = try await fetchHTML(watch, "https://www.youtube.com/")
        guard let text = extractJSONObject(after: "ytInitialPlayerResponse =", in: html), let d = text.data(using: .utf8), let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw AppError.message("تعذر قراءة YouTube.") }
        if let p = j["playabilityStatus"] as? [String: Any], let status = p["status"] as? String, status != "OK" { throw AppError.message((p["reason"] as? String) ?? status) }
        guard let stream = j["streamingData"] as? [String: Any] else { return [] }
        let details = j["videoDetails"] as? [String: Any]
        let title = sanitize((details?["title"] as? String) ?? "youtube-\(id)")
        let thumb = ((details?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }.last
        let formats = (stream["formats"] as? [[String: Any]] ?? []).compactMap { f -> (URL, Int, String)? in
            guard let s = f["url"] as? String, let u = URL(string: s) else { return nil }
            return (u, f["height"] as? Int ?? 0, f["qualityLabel"] as? String ?? "video")
        }.sorted { $0.1 > $1.1 }
        guard let best = formats.first else { return [] }
        return [DownloadMedia(url: best.0, filename: "\(title)-\(best.2).mp4", type: "video", thumb: thumb, referer: "https://www.youtube.com/", platform: .youtube)]
    }

    private func youtubeInvidious(_ id: String) async throws -> [DownloadMedia] {
        let list = URL(string: "https://api.invidious.io/instances.json?sort_by=health")!
        let (d, _) = try await URLSession.shared.data(from: list)
        guard let rows = try JSONSerialization.jsonObject(with: d) as? [[Any]] else { throw AppError.message("لا يوجد محرك YouTube متاح الآن.") }
        for row in rows.prefix(18) {
            guard row.count > 1, let meta = row[1] as? [String: Any], (meta["api"] as? Bool) == true, let uri = meta["uri"] as? String, let endpoint = URL(string: "\(uri)/api/v1/videos/\(id)") else { continue }
            do {
                var req = URLRequest(url: endpoint); req.timeoutInterval = 8; req.setValue(ua, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let h = response as? HTTPURLResponse, (200..<300).contains(h.statusCode), let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let title = sanitize((j["title"] as? String) ?? "youtube-\(id)")
                let thumb = (j["videoThumbnails"] as? [[String: Any]])?.compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }.last
                let fs = (j["formatStreams"] as? [[String: Any]] ?? []).compactMap { f -> (URL, Int, String)? in
                    guard let s = f["url"] as? String, let u = URL(string: s) else { return nil }
                    let q = f["qualityLabel"] as? String ?? f["quality"] as? String ?? "video"
                    return (u, Int(q.filter(\.isNumber)) ?? 0, q)
                }.sorted { $0.1 > $1.1 }
                if let best = fs.first { return [DownloadMedia(url: best.0, filename: "\(title)-\(best.2).mp4", type: "video", thumb: thumb, referer: "https://www.youtube.com/", platform: .youtube)] }
            } catch { continue }
        }
        throw AppError.message("تعذر تنزيل فيديو YouTube حاليًا.")
    }

    private func youtubeID(_ u: URL) -> String? {
        if (u.host ?? "").contains("youtu.be") { return u.pathComponents.dropFirst().first }
        if let c = URLComponents(url: u, resolvingAgainstBaseURL: false), let v = c.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty { return v }
        let a = u.pathComponents
        if let i = a.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }), i + 1 < a.count { return a[i + 1] }
        return nil
    }

    private func resolveX(_ source: URL) async throws -> [DownloadMedia] {
        guard let sid = source.pathComponents.first(where: { $0.count > 8 && $0.allSatisfy(\.isNumber) }) else { throw AppError.message("لم أتعرف على منشور X.") }
        let comps = source.pathComponents
        let user = comps.count > 1 ? comps[1] : "i"
        let endpoint = URL(string: "https://api.fxtwitter.com/\(user)/status/\(sid)")!
        let (d, r) = try await URLSession.shared.data(from: endpoint)
        guard let h = r as? HTTPURLResponse, (200..<300).contains(h.statusCode), let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw URLError(.badServerResponse) }
        let tweet = (j["tweet"] as? [String: Any]) ?? j
        var out: [DownloadMedia] = []
        if let media = tweet["media"] as? [String: Any] {
            for (i, v) in (media["videos"] as? [[String: Any]] ?? []).enumerated() {
                let vars = (v["variants"] as? [[String: Any]] ?? []).compactMap { x -> (URL, Int)? in
                    guard let s = x["url"] as? String, s.contains(".mp4"), let u = URL(string: s) else { return nil }
                    return (u, x["bitrate"] as? Int ?? 0)
                }
                if let best = vars.max(by: { $0.1 < $1.1 }) { out.append(DownloadMedia(url: best.0, filename: "x-\(sid)-\(i + 1).mp4", type: "video", thumb: nil, referer: source.absoluteString, platform: .x)) }
            }
            for (i, p) in (media["photos"] as? [[String: Any]] ?? []).enumerated() {
                if let s = p["url"] as? String, let u = URL(string: s) { out.append(DownloadMedia(url: u, filename: "x-\(sid)-\(i + 1).jpg", type: "photo", thumb: u, referer: source.absoluteString, platform: .x)) }
            }
        }
        if out.isEmpty { throw AppError.message("لا توجد وسائط في المنشور.") }
        return out
    }

    private func resolveMeta(_ source: URL, _ p: PlatformKind) async throws -> [DownloadMedia] {
        let (html, final) = try await fetchHTML(source, source.absoluteString)
        if let s = meta(html, ["og:video","og:video:url","twitter:player:stream"]).first, let u = URL(string: htmlDecode(s)) {
            return [DownloadMedia(url: u, filename: "\(p.rawValue.lowercased())-video.mp4", type: "video", thumb: nil, referer: final.absoluteString, platform: p)]
        }
        if let s = meta(html, ["og:image","twitter:image"]).first, let u = URL(string: htmlDecode(s)) {
            return [DownloadMedia(url: u, filename: "\(p.rawValue.lowercased())-image.jpg", type: "photo", thumb: u, referer: final.absoluteString, platform: p)]
        }
        throw AppError.message("تعذر استخراج الوسائط من \(p.rawValue).")
    }

    // MARK: File / helpers

    private func mediaFolder() -> URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func persist(_ tmp: URL, _ filename: String) throws -> URL {
        let dst = uniqueURL(in: mediaFolder(), name: sanitize(filename))
        try FileManager.default.moveItem(at: tmp, to: dst)
        return dst
    }

    private func uniqueFolderURL(name: String) -> URL {
        let root = mediaFolder()
        var dst = root.appendingPathComponent(name, isDirectory: true), n = 2
        while FileManager.default.fileExists(atPath: dst.path) { dst = root.appendingPathComponent("\(name) \(n)", isDirectory: true); n += 1 }
        return dst
    }

    private func uniqueURL(in folder: URL, name: String, excluding: URL? = nil) -> URL {
        var dst = folder.appendingPathComponent(name)
        if dst == excluding { return dst }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: dst.path) && dst != excluding {
            dst = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return dst
    }

    private func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw AppError.message("اسمح للتطبيق بإضافة الوسائط إلى الصور.") }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                if ["mp4","mov","m4v"].contains(url.pathExtension.lowercased()) { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
                else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
            }) { ok, err in ok ? c.resume() : c.resume(throwing: err ?? AppError.message("تعذر الحفظ في الصور.")) }
        }
    }

    private func applyingExtension(from original: String, to requested: String) -> String {
        if !(requested as NSString).pathExtension.isEmpty { return requested }
        let ext = (original as NSString).pathExtension
        return ext.isEmpty ? requested : "\(requested).\(ext)"
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in e { if let n = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Int64(n ?? 0) } }
        return total
    }

    private func fetchHTML(_ u: URL, _ referer: String?) async throws -> (String, URL) {
        var r = URLRequest(url: u); r.timeoutInterval = 30; r.setValue(ua, forHTTPHeaderField: "User-Agent"); if let referer { r.setValue(referer, forHTTPHeaderField: "Referer") }
        let (d, response) = try await URLSession.shared.data(for: r)
        guard let h = response as? HTTPURLResponse, (200..<400).contains(h.statusCode), let s = String(data: d, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return (s, h.url ?? u)
    }

    private func regexFirst(_ s: String, _ p: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators,.caseInsensitive]), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    private func extractJSONObject(after marker: String, in text: String) -> String? {
        guard let mr = text.range(of: marker) else { return nil }
        var i = mr.upperBound
        while i < text.endIndex && text[i] != "{" { i = text.index(after: i) }
        guard i < text.endIndex else { return nil }
        var depth = 0, inside = false, esc = false, j = i
        while j < text.endIndex {
            let c = text[j]
            if inside { if esc { esc = false } else if c == "\\" { esc = true } else if c == "\"" { inside = false } }
            else { if c == "\"" { inside = true } else if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { return String(text[i...j]) } } }
            j = text.index(after: j)
        }
        return nil
    }

    private func meta(_ html: String, _ names: [String]) -> [String] {
        var out: [String] = []
        for n in names {
            let e = NSRegularExpression.escapedPattern(for: n)
            for p in [#"<meta[^>]+(?:property|name)=[\"']"# + e + #"[\"'][^>]+content=[\"']([^\"']+)[\"']"#, #"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']"# + e + #"[\"']"#] { if let x = regexFirst(html, p) { out.append(x) } }
        }
        return out
    }

    private func firstURL(in v: Any, keys: [String]) -> String? {
        if let d = v as? [String: Any] {
            for k in keys {
                if let s = d[k] as? String, s.hasPrefix("http") { return s }
                if let a = d[k] as? [String], let s = a.first(where: { $0.hasPrefix("http") }) { return s }
                if let sub = d[k] as? [String: Any], let a = (sub["urlList"] ?? sub["url_list"]) as? [String], let s = a.first { return s }
            }
            for child in d.values { if let x = firstURL(in: child, keys: keys) { return x } }
        }
        if let a = v as? [Any] { for child in a { if let x = firstURL(in: child, keys: keys) { return x } } }
        return nil
    }

    private func firstString(in v: Any, keys: [String]) -> String? {
        if let d = v as? [String: Any] {
            for k in keys { if let s = d[k] as? String, !s.isEmpty { return s }; if let n = d[k] as? NSNumber { return n.stringValue } }
            for child in d.values { if let x = firstString(in: child, keys: keys) { return x } }
        }
        if let a = v as? [Any] { for child in a { if let x = firstString(in: child, keys: keys) { return x } } }
        return nil
    }

    private func sanitize(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let x = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return x.isEmpty ? "media" : String(x.prefix(120))
    }

    private func decodeEscapedURL(_ s: String) -> String { s.replacingOccurrences(of: "\\u002F", with: "/").replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "\\u0026", with: "&") }
    private func htmlDecode(_ s: String) -> String { s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#x2F;", with: "/") }
    private func readable(_ e: Error) -> String { if let a = e as? AppError { return a.text }; if let u = e as? URLError, u.code == .timedOut { return "انتهت مهلة الاتصال." }; return e.localizedDescription }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }

// MARK: - Theme

enum AppTheme {
    static let olive = Color(red: 0.27, green: 0.34, blue: 0.18)
    static let oliveLight = Color(red: 0.42, green: 0.50, blue: 0.31)
    static let warm = Color(red: 0.965, green: 0.952, blue: 0.912)

    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.055, green: 0.057, blue: 0.065) : warm }
    static func surface(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.09, green: 0.095, blue: 0.105) : Color.white.opacity(0.72) }
    static func secondary(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.55) }
}

// MARK: - Root

struct RootView: View {
    @StateObject private var model = AppModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(model: model, openLibrary: { selectedTab = 1 }).tag(0).tabItem { Label("تحميل", systemImage: "arrow.down") }
            LibraryView(model: model).tag(1).tabItem { Label("المكتبة", systemImage: "folder.fill") }
            SettingsView(model: model).tag(2).tabItem { Label("الإعدادات", systemImage: "gearshape.fill") }
        }
        .tint(AppTheme.olive)
    }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var model: AppModel
    let openLibrary: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var showDetails = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(scheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 26) {
                        HStack {
                            Text("مُحمّل").font(.system(size: 40, weight: .semibold, design: .serif))
                            Spacer()
                            Button { openLibrary() } label: { Image(systemName: "folder").font(.title3).frame(width: 44, height: 44).background(AppTheme.surface(scheme), in: Circle()) }
                        }

                        VStack(spacing: 9) {
                            Text("جاهز للتحميل").font(.system(size: 30, weight: .bold))
                            Text("الصق الرابط فقط").font(.title3).foregroundStyle(AppTheme.secondary(scheme))
                        }.padding(.top, 10)

                        VStack(spacing: 14) {
                            HStack(spacing: 12) {
                                TextField("https://", text: $model.input)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.leading)
                                Image(systemName: "link").font(.title2)
                            }
                            .padding(.horizontal, 22).frame(height: 76)
                            .background(AppTheme.olive, in: RoundedRectangle(cornerRadius: 25))
                            .foregroundStyle(.white)

                            Button {
                                model.input = UIPasteboard.general.string ?? ""
                            } label: {
                                Label("لصق من الحافظة", systemImage: "doc.on.clipboard")
                                    .frame(maxWidth: .infinity).frame(height: 56)
                                    .background(AppTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 19))
                            }

                            Button {
                                Task { await model.resolve(); if !model.results.isEmpty { showDetails = true } }
                            } label: {
                                HStack(spacing: 12) {
                                    if model.isLoading { ProgressView().tint(.white) }
                                    Text(model.isLoading ? "جاري التحليل" : "متابعة").font(.headline)
                                    Image(systemName: "arrow.left")
                                }
                                .frame(maxWidth: .infinity).frame(height: 58)
                                .background(AppTheme.olive, in: RoundedRectangle(cornerRadius: 20)).foregroundStyle(.white)
                            }
                            .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)
                        }

                        PlatformStrip()

                        if let error = model.error {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        if !model.library.isEmpty {
                            VStack(alignment: .trailing, spacing: 12) {
                                HStack { Button("عرض الكل", action: openLibrary).font(.subheadline); Spacer(); Text("الأخيرة").font(.headline) }
                                ForEach(model.library.filter { !$0.isFolder }.prefix(3)) { item in CompactFileRow(item: item, model: model) }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 30)
                }
            }
            .navigationDestination(isPresented: $showDetails) { DownloadDetailView(model: model) }
        }
    }
}

struct PlatformStrip: View {
    let items = [("play.rectangle.fill","YouTube"),("music.note","TikTok"),("camera","Instagram"),("xmark","X"),("ellipsis","المزيد")]
    var body: some View {
        HStack(spacing: 20) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 7) {
                    Image(systemName: item.0).font(.title3).frame(width: 48, height: 48).background(.thinMaterial, in: Circle())
                    Text(item.1).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity)
    }
}

struct DownloadDetailView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var baseName = "media"
    @State private var saveTo: SaveTarget = .app

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let first = model.results.first { RemotePreview(item: first).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 24)) }

                VStack(alignment: .trailing, spacing: 5) {
                    Text(model.detectedPlatform).font(.caption).foregroundStyle(.secondary)
                    Text(model.results.count == 1 ? "ملف جاهز" : "\(model.results.count) عناصر جاهزة").font(.title2.bold())
                }.frame(maxWidth: .infinity, alignment: .trailing)

                VStack(spacing: 12) {
                    TextField("اسم الملف", text: $baseName).padding(14).background(AppTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 16))
                    Picker("الحفظ", selection: $saveTo) { Text("داخل التطبيق").tag(SaveTarget.app); Text("الصور").tag(SaveTarget.photos) }.pickerStyle(.segmented)
                }

                if model.results.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) { ForEach(model.results) { item in RemoteThumb(item: item).frame(width: 94, height: 94).clipShape(RoundedRectangle(cornerRadius: 16)) } }
                    }
                }

                Button {
                    Task {
                        if model.results.count == 1, let item = model.results.first { await model.download(item, name: baseName, target: saveTo) }
                        else { await model.downloadAll(model.results, baseName: baseName, target: saveTo) }
                    }
                } label: {
                    HStack { if model.isLoading { ProgressView().tint(.white) }; Label("بدء التحميل", systemImage: "arrow.down.to.line") }
                        .frame(maxWidth: .infinity).frame(height: 58).background(AppTheme.olive, in: RoundedRectangle(cornerRadius: 19)).foregroundStyle(.white)
                }.disabled(model.isLoading)

                if let toast = model.toast { Label(toast, systemImage: "checkmark.circle.fill").foregroundStyle(AppTheme.olive) }
                if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.padding(20)
        }
        .background(AppTheme.background(scheme).ignoresSafeArea())
        .navigationTitle("تفاصيل المحتوى").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { model.clearResolved(); dismiss() } } }
        .onAppear {
            if let first = model.results.first { baseName = (first.filename as NSString).deletingPathExtension }
        }
    }
}

struct RemotePreview: View {
    let item: DownloadMedia
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
            if let t = item.thumb { AsyncImage(url: t) { phase in if let image = phase.image { image.resizable().scaledToFit() } else { ProgressView() } } }
            else { Image(systemName: item.type == "photo" ? "photo.fill" : "play.circle.fill").font(.system(size: 70)).foregroundStyle(.white.opacity(0.8)) }
        }
    }
}

struct RemoteThumb: View {
    let item: DownloadMedia
    var body: some View { Group { if let t = item.thumb { AsyncImage(url: t) { phase in if let image = phase.image { image.resizable().scaledToFill() } else { Color.gray.opacity(0.2) } } } else { ZStack { Color.gray.opacity(0.2); Image(systemName: item.type == "photo" ? "photo" : "play") } } } }
}

// MARK: - Library

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @State private var grid = true
    @State private var selecting = false
    @State private var selected = Set<URL>()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showCreateFolder = false
    @State private var folderName = ""
    @State private var shareURLs: [URL] = []
    @State private var showShare = false

    private var filtered: [LocalItem] {
        model.library.filter { item in
            let qOK = query.isEmpty || item.url.lastPathComponent.localizedCaseInsensitiveContains(query)
            let fOK: Bool
            switch filter {
            case .all: fOK = true
            case .photos: fOK = item.isImage
            case .videos: fOK = item.isVideo
            case .audio: fOK = item.isAudio
            case .documents: fOK = item.isDocument
            }
            return qOK && fOK
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(scheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        HStack {
                            Button { selecting.toggle(); selected.removeAll() } label: { Text(selecting ? "تم" : "تحديد").fontWeight(.semibold) }
                            Spacer()
                            Text("ملفاتي").font(.system(size: 34, weight: .bold))
                        }

                        HStack(spacing: 14) {
                            LibraryAction(icon: "checkmark.square", title: "تحديد") { selecting = true }
                            LibraryAction(icon: "folder.badge.plus", title: "إنشاء") { showCreateFolder = true }
                            LibraryAction(icon: "camera.fill", title: "التقط صورة") { showCamera = true }
                            PhotosPicker(selection: $photoItems, maxSelectionCount: 30, matching: .any(of: [.images,.videos])) {
                                ActionIcon(icon: "photo.on.rectangle", title: "استيراد")
                            }
                            LibraryAction(icon: "wand.and.stars", title: "تنظيم") { filter = .all; query = "" }
                        }

                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("بحث...", text: $query)
                        }.padding(.horizontal, 16).frame(height: 52).background(AppTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 17))

                        HStack(spacing: 8) {
                            Button { grid.toggle() } label: { Image(systemName: grid ? "list.bullet" : "square.grid.2x2").frame(width: 42, height: 38).background(AppTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 12)) }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 7) { ForEach(LibraryFilter.allCases) { f in FilterChip(title: f.rawValue, selected: filter == f) { filter = f } } }
                            }
                        }

                        if selecting && !selected.isEmpty {
                            HStack(spacing: 12) {
                                Button(role: .destructive) { model.delete(filtered.filter { selected.contains($0.url) }); selected.removeAll() } label: { Label("حذف", systemImage: "trash") }
                                Button { shareURLs = Array(selected); showShare = true } label: { Label("مشاركة", systemImage: "square.and.arrow.up") }
                                Spacer(); Text("\(selected.count) محدد").font(.subheadline)
                            }.padding(13).background(AppTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 16))
                        }

                        if filtered.isEmpty {
                            ContentUnavailableView("لا توجد ملفات", systemImage: "folder", description: Text("حمّل أو استورد صورًا وفيديوهات."))
                                .padding(.top, 70)
                        } else if grid {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(filtered) { item in LibraryGridCard(item: item, model: model, selecting: selecting, selected: selected.contains(item.url)) { toggle(item) } }
                            }
                        } else {
                            LazyVStack(spacing: 8) { ForEach(filtered) { item in LibraryListRow(item: item, model: model, selecting: selecting, selected: selected.contains(item.url)) { toggle(item) } } }
                        }
                    }.padding(20).padding(.bottom, 24)
                }
            }
            .task(id: photoItems) { if !photoItems.isEmpty { await model.importPhotoItems(photoItems); photoItems = [] } }
            .sheet(isPresented: $showCamera) { CameraPicker { image in model.importCameraImage(image) } }
            .sheet(isPresented: $showShare) { ActivityView(items: shareURLs) }
            .alert("إنشاء مجلد", isPresented: $showCreateFolder) {
                TextField("اسم المجلد", text: $folderName)
                Button("إنشاء") { model.createFolder(named: folderName); folderName = "" }
                Button("إلغاء", role: .cancel) { }
            }
        }
    }

    private func toggle(_ item: LocalItem) {
        if selecting {
            if selected.contains(item.url) { selected.remove(item.url) } else { selected.insert(item.url) }
        }
    }
}

struct LibraryAction: View {
    let icon: String, title: String, action: () -> Void
    var body: some View { Button(action: action) { ActionIcon(icon: icon, title: title) }.buttonStyle(.plain) }
}

struct ActionIcon: View {
    let icon: String, title: String
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.title2).frame(width: 54, height: 54).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
            Text(title).font(.caption2).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }
}

struct FilterChip: View {
    let title: String, selected: Bool, action: () -> Void
    var body: some View { Button(title, action: action).font(.subheadline.weight(.medium)).padding(.horizontal, 16).frame(height: 38).background(selected ? AppTheme.oliveLight.opacity(0.85) : Color.clear, in: RoundedRectangle(cornerRadius: 11)).foregroundStyle(selected ? .white : .primary) }
}

struct LibraryGridCard: View {
    let item: LocalItem
    @ObservedObject var model: AppModel
    let selecting: Bool, selected: Bool, toggle: () -> Void
    var body: some View {
        Group {
            if selecting {
                Button(action: toggle) { content }.buttonStyle(.plain)
            } else {
                NavigationLink { FileDetailView(item: item, model: model) } label: { content }.buttonStyle(.plain)
            }
        }
    }
    private var content: some View {
        VStack(alignment: .trailing, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                FileThumbnail(item: item).frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 18))
                if selecting { Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(selected ? AppTheme.olive : .white).padding(8) }
            }
            Text(item.url.lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(item.isFolder ? "مجلد" : model.formattedBytes(item.size)).font(.caption2).foregroundStyle(.secondary)
        }.padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct LibraryListRow: View {
    let item: LocalItem
    @ObservedObject var model: AppModel
    let selecting: Bool, selected: Bool, toggle: () -> Void
    var body: some View {
        Group {
            if selecting { Button(action: toggle) { content }.buttonStyle(.plain) }
            else { NavigationLink { FileDetailView(item: item, model: model) } label: { content }.buttonStyle(.plain) }
        }
    }
    private var content: some View {
        HStack(spacing: 12) {
            if selecting { Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(AppTheme.olive) }
            VStack(alignment: .trailing, spacing: 4) { Text(item.url.lastPathComponent).lineLimit(1); Text(item.isFolder ? "مجلد" : model.formattedBytes(item.size)).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .trailing)
            FileThumbnail(item: item).frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 14))
        }.padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
    }
}

struct CompactFileRow: View {
    let item: LocalItem
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            Text(model.formattedBytes(item.size)).font(.caption2).foregroundStyle(.secondary)
            VStack(alignment: .trailing, spacing: 3) { Text(item.url.lastPathComponent).lineLimit(1); Text(item.ext.uppercased()).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .trailing)
            FileThumbnail(item: item).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 13))
        }.padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct FileThumbnail: View {
    let item: LocalItem
    var body: some View {
        ZStack {
            Color.secondary.opacity(0.08)
            if item.isFolder { Image(systemName: "folder.fill").font(.system(size: 38)).foregroundStyle(AppTheme.olive) }
            else if item.isImage, let image = UIImage(contentsOfFile: item.url.path) { Image(uiImage: image).resizable().scaledToFill() }
            else if item.isVideo { VideoPoster(url: item.url) }
            else if item.isAudio { Image(systemName: "music.note").font(.system(size: 34)).foregroundStyle(AppTheme.olive) }
            else { Image(systemName: "doc.fill").font(.system(size: 34)).foregroundStyle(AppTheme.olive) }
        }.clipped()
    }
}

struct VideoPoster: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View { ZStack { if let image { Image(uiImage: image).resizable().scaledToFill() } else { Color.black.opacity(0.85); Image(systemName: "play.fill").foregroundStyle(.white) } } .task { let asset = AVURLAsset(url: url); let gen = AVAssetImageGenerator(asset: asset); gen.appliesPreferredTrackTransform = true; if let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.15, preferredTimescale: 600), actualTime: nil) { image = UIImage(cgImage: cg) } } }
}

// MARK: - Detail / media

struct FileDetailView: View {
    let item: LocalItem
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var rename = ""
    @State private var showRename = false
    @State private var showDelete = false
    @State private var showShare = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if item.isFolder {
                    Image(systemName: "folder.fill").font(.system(size: 90)).foregroundStyle(AppTheme.olive).frame(height: 240)
                } else {
                    MediaPreview(item: item).frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 24))
                }

                VStack(alignment: .trailing, spacing: 5) {
                    Text(item.url.lastPathComponent).font(.title3.bold()).multilineTextAlignment(.trailing)
                    if !item.isFolder { Text(model.formattedBytes(item.size)).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .trailing)

                HStack(spacing: 10) {
                    Button { rename = (item.url.lastPathComponent as NSString).deletingPathExtension; showRename = true } label: { Label("إعادة تسمية", systemImage: "pencil") }.buttonStyle(.bordered)
                    if !item.isFolder { Button { showShare = true } label: { Label("مشاركة", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent).tint(AppTheme.olive) }
                }

                if item.isImage || item.isVideo {
                    Button { Task { await model.saveExistingToPhotos(item.url) } } label: { Label("حفظ في الصور", systemImage: "photo.badge.plus").frame(maxWidth: .infinity).frame(height: 50) }.buttonStyle(.bordered)
                }

                if item.isVideo { NavigationLink { TrimEditorView(url: item.url, model: model) } label: { Label("قص الفيديو", systemImage: "scissors").frame(maxWidth: .infinity).frame(height: 50).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15)) } }

                Button(role: .destructive) { showDelete = true } label: { Label("حذف", systemImage: "trash") }
                if let toast = model.toast { Text(toast).font(.footnote).foregroundStyle(AppTheme.olive) }
                if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.padding(20)
        }
        .background(AppTheme.background(scheme).ignoresSafeArea())
        .navigationTitle("التفاصيل").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) { ActivityView(items: [item.url]) }
        .alert("إعادة تسمية", isPresented: $showRename) { TextField("الاسم", text: $rename); Button("حفظ") { model.rename(item, to: rename) }; Button("إلغاء", role: .cancel) { } }
        .confirmationDialog("حذف هذا العنصر؟", isPresented: $showDelete) { Button("حذف", role: .destructive) { model.delete(item) }; Button("إلغاء", role: .cancel) { } }
    }
}

struct MediaPreview: View {
    let item: LocalItem
    var body: some View {
        Group {
            if item.isImage, let image = UIImage(contentsOfFile: item.url.path) { ZStack { Color.black; Image(uiImage: image).resizable().scaledToFit() } }
            else if item.isVideo || item.isAudio { LocalPlayer(url: item.url, audioOnly: item.isAudio) }
            else { ZStack { Color.secondary.opacity(0.08); Image(systemName: "doc.fill").font(.system(size: 64)) } }
        }
    }
}

struct LocalPlayer: View {
    let url: URL, audioOnly: Bool
    @State private var player: AVPlayer?
    var body: some View {
        ZStack {
            Color.black
            if audioOnly { VStack(spacing: 20) { Image(systemName: "waveform").font(.system(size: 70)).foregroundStyle(.white); Text(url.lastPathComponent).foregroundStyle(.white).lineLimit(1) } }
            if let player { VideoPlayer(player: player) } else { ProgressView().tint(.white) }
        }
        .task {
            guard player == nil else { return }
            do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback); try AVAudioSession.sharedInstance().setActive(true) } catch { }
            let p = AVPlayer(url: url); player = p
        }
        .onDisappear { player?.pause(); player = nil }
    }
}

struct TrimEditorView: View {
    let url: URL
    @ObservedObject var model: AppModel
    @State private var duration = 1.0
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var exporting = false
    @State private var message = ""

    var body: some View {
        Form {
            Section { LocalPlayer(url: url, audioOnly: false).frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 18)) }
            Section("القص") {
                Text("\(fmt(start)) — \(fmt(end))")
                Slider(value: $start, in: 0...max(0.1, end - 0.1), step: 0.1).tint(AppTheme.olive)
                Slider(value: $end, in: min(duration,start + 0.1)...max(duration,min(duration,start + 0.1)), step: 0.1).tint(AppTheme.olive)
            }
            Button { export() } label: { HStack { if exporting { ProgressView() }; Label("حفظ نسخة", systemImage: "scissors") } }.disabled(exporting)
            if !message.isEmpty { Text(message) }
        }.navigationTitle("قص الفيديو").task { let a = AVURLAsset(url: url); if let d = try? await a.load(.duration) { duration = max(0.1,d.seconds); end = duration } }
    }

    private func fmt(_ s: Double) -> String { String(format: "%02d:%02d", Int(s)/60, Int(s)%60) }
    private func export() {
        exporting = true; message = ""
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { exporting = false; return }
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel", isDirectory: true)
        let dst = root.appendingPathComponent("trimmed-\(Int(Date().timeIntervalSince1970)).mp4")
        session.outputURL = dst; session.outputFileType = .mp4; session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        session.exportAsynchronously { DispatchQueue.main.async { exporting = false; if session.status == .completed { model.refreshStorage(); message = "تم الحفظ" } else { message = session.error?.localizedDescription ?? "فشل التصدير" } } }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appearance") private var appearance = "system"
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(scheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .trailing, spacing: 18) {
                        Text("الإعدادات").font(.system(size: 34, weight: .bold)).frame(maxWidth: .infinity, alignment: .trailing)

                        SettingBlock(title: "المظهر", icon: "circle.lefthalf.filled") {
                            Picker("المظهر", selection: $appearance) { Text("النظام").tag("system"); Text("فاتح").tag("light"); Text("داكن").tag("dark") }.pickerStyle(.segmented)
                        }

                        SettingBlock(title: "الحفظ", icon: "square.and.arrow.down") {
                            Picker("مكان الحفظ", selection: Binding(get: { model.saveTarget }, set: { model.setSaveTarget($0) })) { ForEach(SaveTarget.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                        }

                        SettingBlock(title: "المساحة", icon: "internaldrive") {
                            VStack(spacing: 12) {
                                HStack { Text(model.formattedBytes(model.libraryBytes)).foregroundStyle(.secondary); Spacer(); Text("ملفات المكتبة") }
                                HStack { Text(model.formattedBytes(model.cacheBytes)).foregroundStyle(.secondary); Spacer(); Text("الكاش") }
                                Divider()
                                Button { model.clearCache() } label: { Label("حذف الكاش", systemImage: "trash.slash") }.foregroundStyle(AppTheme.olive)
                                Button(role: .destructive) { confirmDeleteAll = true } label: { Label("حذف جميع ملفات التطبيق", systemImage: "trash") }
                            }
                        }

                        Text("الإصدار 1.0").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
                    }.padding(20)
                }
            }
            .onAppear { model.refreshStorage() }
            .confirmationDialog("حذف جميع الملفات؟", isPresented: $confirmDeleteAll) { Button("حذف الكل", role: .destructive) { model.deleteAllAppFiles() }; Button("إلغاء", role: .cancel) { } }
        }
    }
}

struct SettingBlock<Content: View>: View {
    let title: String, icon: String
    @ViewBuilder var content: Content
    init(title: String, icon: String, @ViewBuilder content: () -> Content) { self.title = title; self.icon = icon; self.content = content() }
    var body: some View { VStack(alignment: .trailing, spacing: 14) { HStack { Spacer(); Text(title).font(.headline); Image(systemName: icon).foregroundStyle(AppTheme.olive) }; content }.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20)) }
}

// MARK: - UIKit bridges

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
