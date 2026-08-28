import SwiftUI
import Foundation
import UIKit
import Photos
import AVFoundation
import AVKit

@main
struct HammelApp: App {
    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(.light)
        }
    }
}

enum PlatformKind: String { case tiktok = "TikTok", youtube = "YouTube", x = "X", instagram = "Instagram", facebook = "Facebook", generic = "Web" }
enum SaveTarget: String, CaseIterable, Identifiable { case app = "داخل التطبيق", photos = "الصور", ask = "اسألني كل مرة"; var id: String { rawValue } }
enum AppError: Error { case message(String); var text: String { if case let .message(v) = self { return v }; return "حدث خطأ." } }

struct DownloadMedia: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let filename: String
    let type: String
    let thumb: URL?
    let referer: String?
    let platform: PlatformKind
}

struct LocalMedia: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let createdAt: Date
    let size: Int64
    var isImage: Bool { ["jpg","jpeg","png","webp","heic"].contains(url.pathExtension.lowercased()) }
    var isVideo: Bool { ["mp4","mov","m4v"].contains(url.pathExtension.lowercased()) }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var input = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var results: [DownloadMedia] = []
    @Published var library: [LocalMedia] = []
    @Published var activeEngine = "جاهز"
    @Published var detectedPlatform = "تلقائي"
    @Published var toast: String?
    @Published var saveTarget: SaveTarget = SaveTarget(rawValue: UserDefaults.standard.string(forKey: "saveTarget") ?? "") ?? .app
    @Published var cacheBytes: Int64 = 0
    @Published var libraryBytes: Int64 = 0

    private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1"

    init() { refreshLibrary(); refreshStorage() }

    func setSaveTarget(_ t: SaveTarget) { saveTarget = t; UserDefaults.standard.set(t.rawValue, forKey: "saveTarget") }

    func resolve() async {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = URL(string: raw), source.scheme?.hasPrefix("http") == true else { error = "الصق رابطًا صحيحًا."; return }
        isLoading = true; error = nil; toast = nil; results = []
        let p = detect(source); detectedPlatform = p.rawValue; activeEngine = "جاري التحليل…"
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
        } catch let caught { error = readable(caught); activeEngine = "تعذر الجلب" }
    }

    func download(_ item: DownloadMedia, filename: String? = nil, target: SaveTarget? = nil) async {
        let t = target ?? saveTarget
        if t == .ask { return }
        isLoading = true; error = nil; toast = nil
        defer { isLoading = false }
        do {
            var req = URLRequest(url: item.url); req.timeoutInterval = 120; req.setValue(ua, forHTTPHeaderField: "User-Agent")
            if let r = item.referer { req.setValue(r, forHTTPHeaderField: "Referer") }
            let (tmp, response) = try await URLSession.shared.download(for: req)
            guard let h = response as? HTTPURLResponse, (200..<400).contains(h.statusCode) else { throw URLError(.badServerResponse) }
            let requested = filename?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = (requested?.isEmpty == false ? requested! : item.filename)
            let saved = try persist(tmp, applyingExtension(from: item.filename, to: finalName))
            refreshLibrary(); refreshStorage()
            if t == .photos { try await saveToPhotos(saved); toast = "تم الحفظ في الصور" } else { toast = "تم الحفظ في المكتبة" }
        } catch let caught { error = readable(caught) }
    }

    func downloadAll(_ items: [DownloadMedia], baseName: String, target: SaveTarget) async {
        for (index, item) in items.enumerated() {
            let ext = item.url.pathExtension.isEmpty ? ((item.type == "photo") ? "jpg" : "mp4") : item.url.pathExtension
            await download(item, filename: "\(baseName)-\(index + 1).\(ext)", target: target)
        }
    }

    func saveExistingToPhotos(_ url: URL) async {
        error = nil; toast = nil
        do { try await saveToPhotos(url); toast = "تم الحفظ في الصور" }
        catch let caught { error = readable(caught) }
    }

    func renameLocal(_ item: LocalMedia, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ext = item.url.pathExtension
        var name = sanitize(trimmed)
        if (name as NSString).pathExtension.isEmpty && !ext.isEmpty { name += ".\(ext)" }
        var dst = item.url.deletingLastPathComponent().appendingPathComponent(name)
        if dst == item.url { return }
        var n = 2
        while FileManager.default.fileExists(atPath: dst.path) {
            let b = (name as NSString).deletingPathExtension, e = (name as NSString).pathExtension
            dst = item.url.deletingLastPathComponent().appendingPathComponent("\(b)-\(n).\(e)"); n += 1
        }
        do { try FileManager.default.moveItem(at: item.url, to: dst); refreshLibrary(); toast = "تم تغيير الاسم" }
        catch { self.error = error.localizedDescription }
    }

    func deleteLocal(_ item: LocalMedia) { try? FileManager.default.removeItem(at: item.url); refreshLibrary(); refreshStorage(); toast = "تم حذف الملف" }

    func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        let fm = FileManager.default
        for dir in [fm.temporaryDirectory, fm.urls(for: .cachesDirectory, in: .userDomainMask).first].compactMap({$0}) {
            if let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) { for u in urls { try? fm.removeItem(at: u) } }
        }
        refreshStorage(); toast = "تم حذف الكاش"
    }

    func deleteAllAppFiles() {
        let folder = mediaFolder(); if FileManager.default.fileExists(atPath: folder.path) { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refreshLibrary(); refreshStorage(); toast = "تم حذف جميع الملفات"
    }

    func refreshLibrary() {
        let folder = mediaFolder(); try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey,.fileSizeKey])) ?? []
        library = urls.filter { !$0.hasDirectoryPath }.map {
            let v = try? $0.resourceValues(forKeys: [.creationDateKey,.fileSizeKey])
            return LocalMedia(url: $0, createdAt: v?.creationDate ?? .distantPast, size: Int64(v?.fileSize ?? 0))
        }.sorted { $0.createdAt > $1.createdAt }
        libraryBytes = library.reduce(0) { $0 + $1.size }
    }

    func refreshStorage() {
        refreshLibrary(); let fm = FileManager.default
        cacheBytes = directorySize(fm.temporaryDirectory) + (fm.urls(for: .cachesDirectory, in: .userDomainMask).first.map(directorySize) ?? 0)
    }

    func formattedBytes(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

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
        for p in [#"<script[^>]*id=[\"']__UNIVERSAL_DATA_FOR_REHYDRATION__[\"'][^>]*>(.*?)</script>"#, #"<script[^>]*id=[\"']SIGI_STATE[\"'][^>]*>(.*?)</script>"#] {
            if let raw = regexFirst(html, p), let d = raw.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) { roots.append(obj) }
        }

        for root in roots {
            let imageURLs = tikTokImages(in: root)
            if !imageURLs.isEmpty {
                let id = firstString(in: root, keys: ["id","itemId","aweme_id"]) ?? "post"
                return imageURLs.enumerated().map { idx, u in
                    DownloadMedia(url: u, filename: "tiktok-\(id)-\(idx + 1).jpg", type: "photo", thumb: u, referer: final.absoluteString, platform: .tiktok)
                }
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
        if let p = j["playabilityStatus"] as? [String: Any], let s = p["status"] as? String, s != "OK" { throw AppError.message((p["reason"] as? String) ?? s) }
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
        for row in rows.prefix(20) {
            guard row.count > 1, let meta = row[1] as? [String: Any], (meta["api"] as? Bool) == true, let uri = meta["uri"] as? String, let endpoint = URL(string: "\(uri)/api/v1/videos/\(id)") else { continue }
            do {
                var req = URLRequest(url: endpoint); req.timeoutInterval = 10; req.setValue(ua, forHTTPHeaderField: "User-Agent")
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
        let comps = source.pathComponents, user = comps.count > 1 ? comps[1] : "i"
        let endpoint = URL(string: "https://api.fxtwitter.com/\(user)/status/\(sid)")!
        let (d, r) = try await URLSession.shared.data(from: endpoint)
        guard let h = r as? HTTPURLResponse, (200..<300).contains(h.statusCode), let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw URLError(.badServerResponse) }
        let tweet = (j["tweet"] as? [String: Any]) ?? j
        var out: [DownloadMedia] = []
        if let media = tweet["media"] as? [String: Any] {
            for (i, v) in (media["videos"] as? [[String: Any]] ?? []).enumerated() {
                let vars = (v["variants"] as? [[String: Any]] ?? []).compactMap { x -> (URL, Int)? in guard let s = x["url"] as? String, s.contains(".mp4"), let u = URL(string: s) else { return nil }; return (u, x["bitrate"] as? Int ?? 0) }
                if let best = vars.max(by: { $0.1 < $1.1 }) { out.append(DownloadMedia(url: best.0, filename: "x-\(sid)-\(i+1).mp4", type: "video", thumb: nil, referer: source.absoluteString, platform: .x)) }
            }
            for (i, p) in (media["photos"] as? [[String: Any]] ?? []).enumerated() { if let s = p["url"] as? String, let u = URL(string: s) { out.append(DownloadMedia(url: u, filename: "x-\(sid)-\(i+1).jpg", type: "photo", thumb: u, referer: source.absoluteString, platform: .x)) } }
        }
        if out.isEmpty { throw AppError.message("لا توجد وسائط في المنشور.") }
        return out
    }

    private func resolveMeta(_ source: URL, _ p: PlatformKind) async throws -> [DownloadMedia] {
        let (html, final) = try await fetchHTML(source, source.absoluteString)
        if let s = meta(html, ["og:video","og:video:url","twitter:player:stream"]).first, let u = URL(string: htmlDecode(s)) { return [DownloadMedia(url: u, filename: "\(p.rawValue.lowercased())-video.mp4", type: "video", thumb: nil, referer: final.absoluteString, platform: p)] }
        if let s = meta(html, ["og:image","twitter:image"]).first, let u = URL(string: htmlDecode(s)) { return [DownloadMedia(url: u, filename: "\(p.rawValue.lowercased())-image.jpg", type: "photo", thumb: u, referer: final.absoluteString, platform: p)] }
        throw AppError.message("تعذر استخراج الوسائط من \(p.rawValue).")
    }

    private func mediaFolder() -> URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel", isDirectory: true) }
    private func persist(_ tmp: URL, _ filename: String) throws -> URL {
        let f = mediaFolder(); try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        var name = sanitize(filename); if (name as NSString).pathExtension.isEmpty { name += ".mp4" }
        var dst = f.appendingPathComponent(name), n = 2
        while FileManager.default.fileExists(atPath: dst.path) { let b = (name as NSString).deletingPathExtension, e = (name as NSString).pathExtension; dst = f.appendingPathComponent("\(b)-\(n).\(e)"); n += 1 }
        try FileManager.default.moveItem(at: tmp, to: dst); return dst
    }
    private func applyingExtension(from original: String, to requested: String) -> String {
        if !(requested as NSString).pathExtension.isEmpty { return requested }
        let ext = (original as NSString).pathExtension
        return ext.isEmpty ? requested : "\(requested).\(ext)"
    }
    private func saveToPhotos(_ u: URL) async throws {
        let s = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard s == .authorized || s == .limited else { throw AppError.message("اسمح للتطبيق بالحفظ في الصور.") }
        guard FileManager.default.fileExists(atPath: u.path) else { throw AppError.message("ملف الوسائط غير موجود.") }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                if ["mp4","mov","m4v"].contains(u.pathExtension.lowercased()) { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: u) }
                else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: u) }
            }) { ok, e in ok ? c.resume() : c.resume(throwing: e ?? AppError.message("تعذر الحفظ في الصور.")) }
        }
    }
    private func fetchHTML(_ u: URL, _ referer: String?) async throws -> (String, URL) { var r = URLRequest(url: u); r.timeoutInterval = 30; r.setValue(ua, forHTTPHeaderField: "User-Agent"); if let referer { r.setValue(referer, forHTTPHeaderField: "Referer") }; let (d, response) = try await URLSession.shared.data(for: r); guard let h = response as? HTTPURLResponse, (200..<400).contains(h.statusCode), let s = String(data: d, encoding: .utf8) else { throw URLError(.badServerResponse) }; return (s, h.url ?? u) }
    private func regexFirst(_ s: String, _ p: String) -> String? { guard let re = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators,.caseInsensitive]), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }; return String(s[r]) }
    private func extractJSONObject(after marker: String, in text: String) -> String? { guard let mr = text.range(of: marker) else { return nil }; var i = mr.upperBound; while i < text.endIndex && text[i] != "{" { i = text.index(after: i) }; guard i < text.endIndex else { return nil }; var depth = 0, inside = false, esc = false, j = i; while j < text.endIndex { let c = text[j]; if inside { if esc { esc = false } else if c == "\\" { esc = true } else if c == "\"" { inside = false } } else { if c == "\"" { inside = true } else if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { return String(text[i...j]) } } }; j = text.index(after: j) }; return nil }
    private func meta(_ html: String, _ names: [String]) -> [String] { var out: [String] = []; for n in names { let e = NSRegularExpression.escapedPattern(for: n); for p in [#"<meta[^>]+(?:property|name)=[\"']"# + e + #"[\"'][^>]+content=[\"']([^\"']+)[\"']"#, #"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']"# + e + #"[\"']"#] { if let x = regexFirst(html, p) { out.append(x) } } }; return out }
    private func firstURL(in v: Any, keys: [String]) -> String? { if let d = v as? [String: Any] { for k in keys { if let s = d[k] as? String, s.hasPrefix("http") { return s }; if let a = d[k] as? [String], let s = a.first(where: { $0.hasPrefix("http") }) { return s }; if let sub = d[k] as? [String: Any], let a = (sub["urlList"] ?? sub["url_list"]) as? [String], let s = a.first { return s } }; for child in d.values { if let x = firstURL(in: child, keys: keys) { return x } } }; if let a = v as? [Any] { for child in a { if let x = firstURL(in: child, keys: keys) { return x } } }; return nil }
    private func firstString(in v: Any, keys: [String]) -> String? { if let d = v as? [String: Any] { for k in keys { if let s = d[k] as? String, !s.isEmpty { return s }; if let n = d[k] as? NSNumber { return n.stringValue } }; for child in d.values { if let x = firstString(in: child, keys: keys) { return x } } }; if let a = v as? [Any] { for child in a { if let x = firstString(in: child, keys: keys) { return x } } }; return nil }
    private func sanitize(_ s: String) -> String { let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>"); let x = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines); return x.isEmpty ? "media" : String(x.prefix(120)) }
    private func decodeEscapedURL(_ s: String) -> String { s.replacingOccurrences(of: "\\u002F", with: "/").replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "\\u0026", with: "&") }
    private func htmlDecode(_ s: String) -> String { s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#x2F;", with: "/") }
    private func readable(_ e: Error) -> String { if let a = e as? AppError { return a.text }; if let u = e as? URLError, u.code == .timedOut { return "انتهت مهلة الاتصال." }; return e.localizedDescription }
    private func directorySize(_ url: URL) -> Int64 { guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }; var total: Int64 = 0; for case let f as URL in en { if let s = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Int64(s ?? 0) } }; return total }
}

private enum Theme {
    static let bg = Color(red: 0.965, green: 0.957, blue: 0.925)
    static let card = Color(red: 0.995, green: 0.988, blue: 0.965)
    static let olive = Color(red: 0.28, green: 0.32, blue: 0.20)
    static let oliveSoft = Color(red: 0.89, green: 0.90, blue: 0.83)
    static let ink = Color(red: 0.10, green: 0.11, blue: 0.10)
    static let muted = Color(red: 0.38, green: 0.38, blue: 0.34)
    static let line = Color.black.opacity(0.08)
}

struct RootView: View {
    @StateObject private var model = AppModel()
    var body: some View {
        TabView {
            HomeView(model: model).tabItem { Label("تحميل", systemImage: "arrow.down.circle.fill") }
            LibraryView(model: model).tabItem { Label("المكتبة", systemImage: "folder.fill") }
            SettingsView(model: model).tabItem { Label("الإعدادات", systemImage: "gearshape") }
        }
        .tint(Theme.olive)
    }
}

struct HomeView: View {
    @ObservedObject var model: AppModel
    @State private var showDetails = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Button { } label: { Image(systemName: "line.3.horizontal").font(.title3).foregroundStyle(Theme.ink) }
                        Spacer()
                        Text("مُحمّل").font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                    }
                    .padding(.top, 6)

                    VStack(spacing: 8) {
                        Text("جاهز للتحميل").font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                        Text("الصق الرابط فقط").font(.subheadline).foregroundStyle(Theme.muted)
                    }

                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "link").foregroundStyle(.white).frame(width: 42, height: 42).background(Theme.olive, in: Circle())
                            TextField("الصق الرابط هنا", text: $model.input).textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing)
                        }
                        .padding(14)
                        .background(Theme.olive, in: RoundedRectangle(cornerRadius: 24))
                        .foregroundStyle(.white)
                        .tint(.white)
                        Button { model.input = UIPasteboard.general.string ?? "" } label: {
                            Label("لصق من الحافظة", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity).padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.ink)
                        .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
                    }

                    Button { Task { await model.resolve() } } label: {
                        HStack(spacing: 10) { if model.isLoading { ProgressView() }; Text(model.isLoading ? "جاري التحليل" : "متابعة").fontWeight(.semibold); Image(systemName: "arrow.left") }
                            .frame(maxWidth: .infinity).padding(.vertical, 15).foregroundStyle(.white).background(Theme.olive, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)

                    HStack(spacing: 18) {
                        platformBadge("play.rectangle.fill", "YouTube")
                        platformBadge("music.note", "TikTok")
                        platformBadge("camera.fill", "Instagram")
                        platformBadge("xmark", "X")
                        platformBadge("ellipsis", "المزيد")
                    }
                    .frame(maxWidth: .infinity)

                    if let e = model.error { Label(e, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .trailing).padding(14).background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 16)) }
                    if let toast = model.toast { Label(toast, systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(Theme.olive).frame(maxWidth: .infinity, alignment: .trailing) }

                    if !model.library.isEmpty {
                        VStack(alignment: .trailing, spacing: 12) {
                            HStack { NavigationLink("عرض الكل") { LibraryView(model: model) }.font(.caption).foregroundStyle(Theme.olive); Spacer(); Text("آخر الملفات").font(.headline).foregroundStyle(Theme.ink) }
                            ForEach(model.library.prefix(3)) { item in NavigationLink { MediaDetailView(model: model, item: item) } label: { LibraryRow(item: item, model: model) }.buttonStyle(.plain) }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarHidden(true)
            .onChange(of: model.results.count) { _, newValue in if newValue > 0 { showDetails = true } }
            .sheet(isPresented: $showDetails) { DownloadDetailSheet(model: model) }
        }
    }

    private func platformBadge(_ icon: String, _ name: String) -> some View {
        VStack(spacing: 6) { Image(systemName: icon).font(.headline).frame(width: 42, height: 42).background(Theme.card, in: Circle()).overlay(Circle().stroke(Theme.line)); Text(name).font(.system(size: 10)).foregroundStyle(Theme.muted) }
    }
}

struct DownloadDetailSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var target: SaveTarget = .app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let first = model.results.first {
                        Group {
                            if let t = first.thumb { AsyncImage(url: t) { im in im.resizable().scaledToFill() } placeholder: { ProgressView() } }
                            else { ZStack { Theme.oliveSoft; Image(systemName: first.type == "photo" ? "photo.on.rectangle" : "play.rectangle.fill").font(.system(size: 48)).foregroundStyle(Theme.olive) } }
                        }
                        .frame(height: 220).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 22))
                    }

                    VStack(alignment: .trailing, spacing: 8) {
                        Text("اسم الملف").font(.caption).foregroundStyle(Theme.muted)
                        TextField("اسم الملف", text: $name).textFieldStyle(.plain).padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
                    }

                    if model.results.count > 1 {
                        VStack(alignment: .trailing, spacing: 10) {
                            Text("\(model.results.count) صور").font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 10) { ForEach(model.results) { item in AsyncImage(url: item.thumb ?? item.url) { im in im.resizable().scaledToFill() } placeholder: { Theme.oliveSoft } .frame(width: 92, height: 112).clipShape(RoundedRectangle(cornerRadius: 14)) } } }
                        }
                    }

                    Picker("الحفظ", selection: $target) { Text("داخل التطبيق").tag(SaveTarget.app); Text("الصور").tag(SaveTarget.photos) }.pickerStyle(.segmented)

                    Button {
                        Task {
                            let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "media" : name
                            if model.results.count == 1, let item = model.results.first { await model.download(item, filename: base, target: target) }
                            else { await model.downloadAll(model.results, baseName: base, target: target) }
                        }
                    } label: {
                        Label(model.results.count > 1 ? "تحميل الكل" : "بدء التحميل", systemImage: "arrow.down.to.line").frame(maxWidth: .infinity).padding(.vertical, 15).foregroundStyle(.white).background(Theme.olive, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .disabled(model.isLoading)

                    if let toast = model.toast { Label(toast, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.olive).font(.footnote) }
                    if let error = model.error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("تفاصيل المحتوى")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { dismiss() } } }
            .onAppear { if let f = model.results.first { name = (f.filename as NSString).deletingPathExtension } }
        }
    }
}

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack { Spacer(); VStack(alignment: .trailing, spacing: 3) { Text("المكتبة").font(.largeTitle.bold()).foregroundStyle(Theme.ink); Text("\(model.library.count) ملف • \(model.formattedBytes(model.libraryBytes))").font(.caption).foregroundStyle(Theme.muted) } }
                    if model.library.isEmpty { ContentUnavailableView("المكتبة فارغة", systemImage: "folder", description: Text("الملفات المحفوظة تظهر هنا." )).padding(.top, 80) }
                    else { LazyVStack(spacing: 10) { ForEach(filtered) { item in NavigationLink { MediaDetailView(model: model, item: item) } label: { LibraryRow(item: item, model: model) }.buttonStyle(.plain) } } }
                }.padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .searchable(text: $query, prompt: "بحث")
            .toolbar { Button { model.refreshLibrary() } label: { Image(systemName: "arrow.clockwise") } }
        }
    }
    private var filtered: [LocalMedia] { query.isEmpty ? model.library : model.library.filter { $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) } }
}

struct LibraryRow: View {
    let item: LocalMedia
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            LocalThumb(item: item).frame(width: 64, height: 58).clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .trailing, spacing: 4) { Text(item.url.deletingPathExtension().lastPathComponent).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1); Text("\(model.formattedBytes(item.size)) • \(item.createdAt.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(Theme.muted) }.frame(maxWidth: .infinity, alignment: .trailing)
            Image(systemName: "chevron.left").font(.caption).foregroundStyle(Theme.muted)
        }.padding(11).background(Theme.card, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
    }
}

struct LocalThumb: View {
    let item: LocalMedia
    var body: some View {
        if item.isImage, let image = UIImage(contentsOfFile: item.url.path) { Image(uiImage: image).resizable().scaledToFill() }
        else { ZStack { Theme.oliveSoft; Image(systemName: item.isVideo ? "play.fill" : "doc.fill").foregroundStyle(Theme.olive) } }
    }
}

struct MediaDetailView: View {
    @ObservedObject var model: AppModel
    let item: LocalMedia
    @State private var showDelete = false
    @State private var rename = ""
    @State private var editName = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                MediaPreview(url: item.url).frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .trailing, spacing: 6) {
                    HStack {
                        Button { rename = item.url.deletingPathExtension().lastPathComponent; editName = true } label: { Image(systemName: "pencil").foregroundStyle(Theme.olive) }
                        Spacer()
                        Text(item.url.deletingPathExtension().lastPathComponent).font(.headline).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
                    }
                    Text(model.formattedBytes(item.size)).font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))

                HStack(spacing: 10) {
                    ShareLink(item: item.url) { Label("مشاركة للتطبيقات", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 13) }.buttonStyle(.plain).foregroundStyle(Theme.ink).background(Theme.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
                    Button { Task { await model.saveExistingToPhotos(item.url) } } label: { Label("حفظ بالصور", systemImage: "photo.badge.plus").frame(maxWidth: .infinity).padding(.vertical, 13) }.buttonStyle(.plain).foregroundStyle(.white).background(Theme.olive, in: RoundedRectangle(cornerRadius: 16))
                }

                if item.isVideo { NavigationLink { TrimEditorView(sourceURL: item.url, model: model) } label: { Label("قص الفيديو", systemImage: "scissors").frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(Theme.ink).background(Theme.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line)) } }

                Button(role: .destructive) { showDelete = true } label: { Label("حذف الملف", systemImage: "trash") }
                if let toast = model.toast { Text(toast).font(.footnote).foregroundStyle(Theme.olive) }
                if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("الوسائط").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("حذف الملف؟", isPresented: $showDelete) { Button("حذف", role: .destructive) { model.deleteLocal(item) }; Button("إلغاء", role: .cancel) {} }
        .alert("تغيير الاسم", isPresented: $editName) { TextField("الاسم", text: $rename); Button("حفظ") { model.renameLocal(item, to: rename) }; Button("إلغاء", role: .cancel) {} }
    }
}

struct MediaPreview: View {
    let url: URL
    var body: some View {
        let ext = url.pathExtension.lowercased()
        Group {
            if ["jpg","jpeg","png","webp","heic"].contains(ext), let image = UIImage(contentsOfFile: url.path) { ZStack { Color.black; Image(uiImage: image).resizable().scaledToFit() } }
            else if ["mp4","mov","m4v"].contains(ext) { LocalVideoPlayer(url: url) }
            else { ZStack { Theme.oliveSoft; Image(systemName: "doc.fill").font(.system(size: 44)).foregroundStyle(Theme.olive) } }
        }
    }
}

struct LocalVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        ZStack { Color.black; if let player { VideoPlayer(player: player) } else { ProgressView().tint(.white) } }
            .task {
                guard player == nil else { return }
                do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback); try AVAudioSession.sharedInstance().setActive(true) } catch { }
                let p = AVPlayer(url: url); player = p
            }
            .onDisappear { player?.pause(); player = nil }
    }
}

struct TrimEditorView: View {
    let sourceURL: URL
    @ObservedObject var model: AppModel
    @State private var duration = 1.0; @State private var start = 0.0; @State private var end = 1.0; @State private var exporting = false; @State private var message = ""
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                LocalVideoPlayer(url: sourceURL).frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .trailing, spacing: 12) { Text("من \(fmt(start)) إلى \(fmt(end))").font(.headline); Slider(value: $start, in: 0...max(0.1,end-0.1), step: 0.1).tint(Theme.olive); Slider(value: $end, in: min(duration,start+0.1)...max(duration,min(duration,start+0.1)), step: 0.1).tint(Theme.olive) }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                Button { exportTrim() } label: { Label(exporting ? "جاري الحفظ" : "حفظ نسخة مقصوصة", systemImage: "scissors").frame(maxWidth: .infinity).padding(15).foregroundStyle(.white).background(Theme.olive, in: RoundedRectangle(cornerRadius: 17)) }.disabled(exporting || end <= start)
                if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(Theme.muted) }
            }.padding(20)
        }.background(Theme.bg.ignoresSafeArea()).navigationTitle("قص الفيديو").task { let a = AVURLAsset(url: sourceURL); if let d = try? await a.load(.duration) { duration = max(0.1,d.seconds); end = duration } }
    }
    private func fmt(_ s: Double) -> String { String(format: "%02d:%02d", Int(s)/60, Int(s)%60) }
    private func exportTrim() {
        exporting = true; message = ""; let asset = AVURLAsset(url: sourceURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { exporting = false; message = "تعذر تجهيز المحرر."; return }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel", isDirectory: true); try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dst = folder.appendingPathComponent("trimmed-\(Int(Date().timeIntervalSince1970)).mp4"); export.outputURL = dst; export.outputFileType = .mp4; export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        export.exportAsynchronously { DispatchQueue.main.async { exporting = false; if export.status == .completed { model.refreshLibrary(); model.refreshStorage(); message = "تم الحفظ." } else { message = export.error?.localizedDescription ?? "فشل التصدير." } } }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmDeleteAll = false
    var body: some View {
        NavigationStack {
            Form {
                Section("الحفظ") { Picker("المكان الافتراضي", selection: Binding(get: { model.saveTarget }, set: { model.setSaveTarget($0) })) { ForEach(SaveTarget.allCases) { Text($0.rawValue).tag($0) } } }
                Section("المساحة") {
                    LabeledContent("المكتبة", value: model.formattedBytes(model.libraryBytes))
                    LabeledContent("الكاش", value: model.formattedBytes(model.cacheBytes))
                    Button("حذف الكاش") { model.clearCache() }
                    Button("حذف جميع ملفات التطبيق", role: .destructive) { confirmDeleteAll = true }
                }
                Section { LabeledContent("الإصدار", value: "0.9") }
            }
            .scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("الإعدادات").onAppear { model.refreshStorage() }
            .confirmationDialog("حذف جميع الملفات؟", isPresented: $confirmDeleteAll) { Button("حذف الكل", role: .destructive) { model.deleteAllAppFiles() }; Button("إلغاء", role: .cancel) {} }
        }
    }
}