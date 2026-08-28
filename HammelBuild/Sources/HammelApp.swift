import SwiftUI
import Foundation
import UIKit
import Photos
import AVFoundation
import AVKit

@main
struct HammelApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(.dark)
        }
    }
}

enum PlatformKind: String {
    case tiktok = "TikTok", youtube = "YouTube", x = "X", instagram = "Instagram", facebook = "Facebook", generic = "Web"
}

enum SaveTarget: String, CaseIterable, Identifiable {
    case app = "داخل التطبيق", photos = "الصور", ask = "اسألني كل مرة"
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

struct LocalMedia: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let createdAt: Date
    let size: Int64
    var isImage: Bool { ["jpg", "jpeg", "png", "webp", "heic"].contains(url.pathExtension.lowercased()) }
    var isVideo: Bool { ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) }
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

    init() {
        refreshLibrary()
        refreshStorage()
    }

    func setSaveTarget(_ t: SaveTarget) {
        saveTarget = t
        UserDefaults.standard.set(t.rawValue, forKey: "saveTarget")
    }

    func resolve() async {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = URL(string: raw), source.scheme?.hasPrefix("http") == true else {
            error = "الصق رابطًا صحيحًا."
            return
        }
        isLoading = true
        error = nil
        results = []
        toast = nil
        let p = detect(source)
        detectedPlatform = p.rawValue
        activeEngine = "جاري التحليل…"
        defer { isLoading = false }

        do {
            let media: [DownloadMedia]
            switch p {
            case .tiktok:
                media = try await resolveTikTok(source)
                activeEngine = "TikTok مباشر"
            case .youtube:
                media = try await resolveYouTube(source)
                activeEngine = "YouTube"
            case .x:
                media = try await resolveX(source)
                activeEngine = "X مباشر"
            case .instagram:
                media = try await resolveMeta(source, .instagram)
                activeEngine = "Instagram"
            case .facebook:
                media = try await resolveMeta(source, .facebook)
                activeEngine = "Facebook"
            case .generic:
                media = try await resolveMeta(source, .generic)
                activeEngine = "Web"
            }
            guard !media.isEmpty else { throw AppError.message("لم أجد وسائط قابلة للتنزيل.") }
            results = media
        } catch let caught {
            error = readable(caught)
            activeEngine = "تعذر الجلب"
        }
    }

    func download(_ item: DownloadMedia, target: SaveTarget? = nil) async {
        let t = target ?? saveTarget
        if t == .ask { return }
        isLoading = true
        error = nil
        toast = nil
        defer { isLoading = false }

        do {
            var req = URLRequest(url: item.url)
            req.timeoutInterval = 120
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
            if let r = item.referer { req.setValue(r, forHTTPHeaderField: "Referer") }
            let (tmp, response) = try await URLSession.shared.download(for: req)
            guard let h = response as? HTTPURLResponse, (200..<400).contains(h.statusCode) else { throw URLError(.badServerResponse) }
            let saved = try persist(tmp, item.filename)
            refreshLibrary()
            refreshStorage()
            if t == .photos {
                try await saveToPhotos(saved)
                toast = "تم الحفظ في الصور"
            } else {
                toast = "تم الحفظ في المكتبة"
            }
        } catch let caught {
            error = readable(caught)
        }
    }

    func saveExistingToPhotos(_ url: URL) async {
        error = nil
        toast = nil
        do {
            try await saveToPhotos(url)
            toast = "تم الحفظ في الصور"
        } catch let caught {
            error = readable(caught)
        }
    }

    func deleteLocal(_ item: LocalMedia) {
        try? FileManager.default.removeItem(at: item.url)
        refreshLibrary()
        refreshStorage()
        toast = "تم حذف الملف"
    }

    func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        let fm = FileManager.default
        let temp = fm.temporaryDirectory
        if let urls = try? fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil) {
            for url in urls { try? fm.removeItem(at: url) }
        }
        refreshStorage()
        toast = "تم حذف الكاش"
    }

    func deleteAllAppFiles() {
        let folder = mediaFolder()
        if FileManager.default.fileExists(atPath: folder.path) { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refreshLibrary()
        refreshStorage()
        toast = "تم حذف جميع ملفات التطبيق"
    }

    func refreshLibrary() {
        let folder = mediaFolder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])) ?? []
        library = urls.filter { !$0.hasDirectoryPath }.map {
            let values = try? $0.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            return LocalMedia(url: $0, createdAt: values?.creationDate ?? .distantPast, size: Int64(values?.fileSize ?? 0))
        }.sorted { $0.createdAt > $1.createdAt }
        libraryBytes = library.reduce(0) { $0 + $1.size }
    }

    func refreshStorage() {
        refreshLibrary()
        let fm = FileManager.default
        let temp = fm.temporaryDirectory
        let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        cacheBytes = directorySize(temp) + (cache.map(directorySize) ?? 0)
    }

    func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Int64(size ?? 0) }
        }
        return total
    }

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
        for p in [#"<script[^>]*id=[\"']__UNIVERSAL_DATA_FOR_REHYDRATION__[\"'][^>]*>(.*?)</script>"#, #"<script[^>]*id=[\"']SIGI_STATE[\"'][^>]*>(.*?)</script>"#] {
            if let raw = regexFirst(html, p), let d = raw.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d), let play = firstURL(in: obj, keys: ["playAddr", "playAddrH264"]), let u = URL(string: play) {
                let cover = firstURL(in: obj, keys: ["cover", "originCover"]).flatMap(URL.init(string:))
                let id = firstString(in: obj, keys: ["id", "itemId"]) ?? UUID().uuidString
                return [DownloadMedia(url: u, filename: "tiktok-\(id).mp4", type: "video", thumb: cover, referer: "https://www.tiktok.com/", platform: .tiktok)]
            }
        }
        if let raw = regexFirst(html, #"\"playAddr\"\s*:\s*\"([^\"]+)\""#), let u = URL(string: decodeEscapedURL(raw)) {
            return [DownloadMedia(url: u, filename: "tiktok-video.mp4", type: "video", thumb: nil, referer: final.absoluteString, platform: .tiktok)]
        }
        throw AppError.message("تعذر استخراج فيديو TikTok.")
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
                var req = URLRequest(url: endpoint)
                req.timeoutInterval = 10
                req.setValue(ua, forHTTPHeaderField: "User-Agent")
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
        if let s = meta(html, ["og:video", "og:video:url", "twitter:player:stream"]).first, let u = URL(string: htmlDecode(s)) {
            return [DownloadMedia(url: u, filename: "\(p.rawValue.lowercased())-video.mp4", type: "video", thumb: nil, referer: final.absoluteString, platform: p)]
        }
        if let s = meta(html, ["og:image", "twitter:image"]).first, let u = URL(string: htmlDecode(s)) {
            return [DownloadMedia(url: u, filename: "\(p.rawValue.lowercased())-image.jpg", type: "photo", thumb: u, referer: final.absoluteString, platform: p)]
        }
        throw AppError.message("تعذر استخراج الوسائط من \(p.rawValue).")
    }

    private func mediaFolder() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel", isDirectory: true)
    }

    private func persist(_ tmp: URL, _ filename: String) throws -> URL {
        let f = mediaFolder()
        try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        var name = sanitize(filename)
        if (name as NSString).pathExtension.isEmpty { name += ".mp4" }
        var dst = f.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: dst.path) {
            let b = (name as NSString).deletingPathExtension
            let e = (name as NSString).pathExtension
            dst = f.appendingPathComponent("\(b)-\(n).\(e)")
            n += 1
        }
        try FileManager.default.moveItem(at: tmp, to: dst)
        return dst
    }

    private func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw AppError.message("اسمح للتطبيق بإضافة الوسائط إلى الصور من إعدادات iPhone.") }
        guard FileManager.default.fileExists(atPath: url.path) else { throw AppError.message("ملف الوسائط غير موجود.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let ext = url.pathExtension.lowercased()
                if ["mp4", "mov", "m4v"].contains(ext) {
                    guard PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) != nil else { return }
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }) { ok, err in
                if ok { continuation.resume() }
                else { continuation.resume(throwing: err ?? AppError.message("تعذر الحفظ في الصور. قد يكون ترميز الملف غير مدعوم.")) }
            }
        }
    }

    private func fetchHTML(_ u: URL, _ referer: String?) async throws -> (String, URL) {
        var r = URLRequest(url: u)
        r.timeoutInterval = 30
        r.setValue(ua, forHTTPHeaderField: "User-Agent")
        if let referer { r.setValue(referer, forHTTPHeaderField: "Referer") }
        let (d, response) = try await URLSession.shared.data(for: r)
        guard let h = response as? HTTPURLResponse, (200..<400).contains(h.statusCode), let s = String(data: d, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return (s, h.url ?? u)
    }

    private func regexFirst(_ s: String, _ p: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators, .caseInsensitive]), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
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
            if inside {
                if esc { esc = false }
                else if c == "\\" { esc = true }
                else if c == "\"" { inside = false }
            } else {
                if c == "\"" { inside = true }
                else if c == "{" { depth += 1 }
                else if c == "}" { depth -= 1; if depth == 0 { return String(text[i...j]) } }
            }
            j = text.index(after: j)
        }
        return nil
    }

    private func meta(_ html: String, _ names: [String]) -> [String] {
        var out: [String] = []
        for n in names {
            let e = NSRegularExpression.escapedPattern(for: n)
            for p in [#"<meta[^>]+(?:property|name)=[\"']"# + e + #"[\"'][^>]+content=[\"']([^\"']+)[\"']"#, #"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']"# + e + #"[\"']"#] {
                if let x = regexFirst(html, p) { out.append(x) }
            }
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
            for k in keys {
                if let s = d[k] as? String, !s.isEmpty { return s }
                if let n = d[k] as? NSNumber { return n.stringValue }
            }
            for child in d.values { if let x = firstString(in: child, keys: keys) { return x } }
        }
        if let a = v as? [Any] { for child in a { if let x = firstString(in: child, keys: keys) { return x } } }
        return nil
    }

    private func sanitize(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let x = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return x.isEmpty ? "media" : String(x.prefix(100))
    }

    private func decodeEscapedURL(_ s: String) -> String {
        s.replacingOccurrences(of: "\\u002F", with: "/").replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "\\u0026", with: "&")
    }

    private func htmlDecode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#x2F;", with: "/")
    }

    private func readable(_ e: Error) -> String {
        if let a = e as? AppError { return a.text }
        if let u = e as? URLError, u.code == .timedOut { return "انتهت مهلة الاتصال." }
        return e.localizedDescription
    }
}

private enum Theme {
    static let background = Color(red: 0.055, green: 0.063, blue: 0.075)
    static let surface = Color(red: 0.095, green: 0.105, blue: 0.122)
    static let surface2 = Color(red: 0.125, green: 0.137, blue: 0.155)
    static let accent = Color(red: 0.43, green: 0.67, blue: 0.61)
    static let accentSoft = Color(red: 0.18, green: 0.29, blue: 0.27)
    static let text2 = Color.white.opacity(0.62)
}

struct RootView: View {
    @StateObject private var model = AppModel()
    var body: some View {
        TabView {
            HomeView(model: model).tabItem { Label("الرئيسية", systemImage: "arrow.down.circle") }
            LibraryView(model: model).tabItem { Label("المكتبة", systemImage: "square.stack.3d.up.fill") }
            StudioView(model: model).tabItem { Label("الاستوديو", systemImage: "slider.horizontal.3") }
            SettingsView(model: model).tabItem { Label("الإعدادات", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .background(Theme.background)
    }
}

struct HomeView: View {
    @ObservedObject var model: AppModel
    @State private var askItem: DownloadMedia?
    @State private var showSaveChoice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(alignment: .center) {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("حمّل").font(.system(size: 38, weight: .bold, design: .rounded))
                            Text("الرابط عندك، والباقي علينا").font(.subheadline).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 26, weight: .semibold))
                            .frame(width: 58, height: 58)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 18))
                            .foregroundStyle(Theme.accent)
                    }

                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Button { model.input = UIPasteboard.general.string ?? "" } label: {
                                Image(systemName: "doc.on.clipboard")
                                    .frame(width: 42, height: 42)
                                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 13))
                            }
                            TextField("الصق رابط الفيديو أو المنشور", text: $model.input)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                                .padding(.vertical, 14)
                        }
                        .padding(.horizontal, 12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))

                        Button { Task { await model.resolve() } } label: {
                            HStack(spacing: 9) {
                                if model.isLoading { ProgressView().tint(.white) }
                                Text(model.isLoading ? "جاري التحليل" : "جلب المحتوى").fontWeight(.semibold)
                                Image(systemName: "arrow.down")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18))
                            .foregroundStyle(Color.black.opacity(0.82))
                        }
                        .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)

                        HStack(spacing: 7) {
                            Circle().fill(model.activeEngine == "تعذر الجلب" ? Color.red : Theme.accent).frame(width: 7, height: 7)
                            Text("\(model.detectedPlatform) • \(model.activeEngine)").font(.caption).foregroundStyle(Theme.text2)
                            Spacer()
                        }
                    }

                    if let e = model.error {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.circle")
                            Text(e).font(.footnote).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .foregroundStyle(Color(red: 0.95, green: 0.66, blue: 0.55))
                        .padding(14)
                        .background(Color(red: 0.22, green: 0.12, blue: 0.11), in: RoundedRectangle(cornerRadius: 16))
                    }

                    if let toast = model.toast {
                        Label(toast, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(14)
                            .background(Theme.accentSoft.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                    }

                    if !model.results.isEmpty {
                        VStack(alignment: .trailing, spacing: 12) {
                            Text("المحتوى المتاح").font(.title3.bold()).frame(maxWidth: .infinity, alignment: .trailing)
                            ForEach(model.results) { item in
                                ResultCard(item: item) {
                                    if model.saveTarget == .ask { askItem = item; showSaveChoice = true }
                                    else { Task { await model.download(item) } }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .confirmationDialog("مكان الحفظ", isPresented: $showSaveChoice) {
            if let item = askItem {
                Button("داخل التطبيق") { Task { await model.download(item, target: .app) } }
                Button("الصور") { Task { await model.download(item, target: .photos) } }
            }
            Button("إلغاء", role: .cancel) {}
        }
    }
}

struct ResultCard: View {
    let item: DownloadMedia
    let action: () -> Void
    var body: some View {
        HStack(spacing: 13) {
            Button(action: action) {
                Image(systemName: "arrow.down")
                    .font(.headline)
                    .frame(width: 46, height: 46)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Color.black.opacity(0.82))
            }
            VStack(alignment: .trailing, spacing: 5) {
                Text(item.filename).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("\(item.platform.rawValue) • \(item.type)").font(.caption).foregroundStyle(Theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            Group {
                if let t = item.thumb {
                    AsyncImage(url: t) { image in image.resizable().scaledToFill() } placeholder: { ProgressView() }
                } else {
                    ZStack { Theme.surface2; Image(systemName: item.type == "photo" ? "photo" : "play.rectangle").foregroundStyle(Theme.accent) }
                }
            }
            .frame(width: 78, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct LibraryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("المكتبة").font(.largeTitle.bold())
                            Text("\(model.library.count) ملف • \(model.formattedBytes(model.libraryBytes))").font(.caption).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                    }
                    if model.library.isEmpty {
                        ContentUnavailableView("المكتبة فارغة", systemImage: "square.stack.3d.up", description: Text("الملفات التي تحملها تظهر هنا."))
                            .padding(.top, 80)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(model.library) { item in
                                NavigationLink { MediaDetailView(model: model, item: item) } label: { LibraryRow(item: item, model: model) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar { Button { model.refreshLibrary() } label: { Image(systemName: "arrow.clockwise") } }
        }
    }
}

struct LibraryRow: View {
    let item: LocalMedia
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isImage ? "photo" : "play.rectangle")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 52, height: 52)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.url.lastPathComponent).foregroundStyle(.white).lineLimit(1)
                Text("\(model.formattedBytes(item.size)) • \(item.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(Theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            Image(systemName: "chevron.left").font(.caption).foregroundStyle(Theme.text2)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct MediaDetailView: View {
    @ObservedObject var model: AppModel
    let item: LocalMedia
    @State private var showDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                MediaPreview(url: item.url)
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .trailing, spacing: 5) {
                    Text(item.url.lastPathComponent).font(.headline).multilineTextAlignment(.trailing)
                    Text(model.formattedBytes(item.size)).font(.caption).foregroundStyle(Theme.text2)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                HStack(spacing: 10) {
                    ShareLink(item: item.url) { Label("مشاركة", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                    Button { Task { await model.saveExistingToPhotos(item.url) } } label: { Label("حفظ في الصور", systemImage: "photo.badge.plus") }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }

                if item.isVideo {
                    NavigationLink { TrimEditorView(sourceURL: item.url, model: model) } label: {
                        Label("قص الفيديو", systemImage: "scissors")
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .foregroundStyle(.white)
                }

                Button(role: .destructive) { showDelete = true } label: { Label("حذف الملف", systemImage: "trash") }
                    .padding(.top, 6)

                if let toast = model.toast { Text(toast).font(.footnote).foregroundStyle(Theme.accent) }
                if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("الوسائط")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("حذف هذا الملف؟", isPresented: $showDelete) {
            Button("حذف", role: .destructive) { model.deleteLocal(item) }
            Button("إلغاء", role: .cancel) {}
        }
    }
}

struct MediaPreview: View {
    let url: URL
    var body: some View {
        let ext = url.pathExtension.lowercased()
        Group {
            if ["jpg", "jpeg", "png", "webp", "heic"].contains(ext), let image = UIImage(contentsOfFile: url.path) {
                ZStack { Color.black; Image(uiImage: image).resizable().scaledToFit() }
            } else if ["mp4", "mov", "m4v"].contains(ext) {
                LocalVideoPlayer(url: url)
            } else {
                ZStack { Theme.surface; VStack(spacing: 10) { Image(systemName: "doc.fill").font(.system(size: 48)); Text("معاينة غير متاحة") } }
            }
        }
    }
}

struct LocalVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
            }
        }
        .task {
            guard player == nil else { return }
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

struct StudioView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: 16) {
                    Text("الاستوديو").font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("اختر فيديو من المكتبة لقص البداية والنهاية. أدوات أكثر سنضيفها هنا بدون ما نخلي الشاشة زحمة.")
                        .font(.subheadline).foregroundStyle(Theme.text2).frame(maxWidth: .infinity, alignment: .trailing)
                    ForEach(model.library.filter { $0.isVideo }) { item in
                        NavigationLink { TrimEditorView(sourceURL: item.url, model: model) } label: {
                            HStack { Image(systemName: "scissors").foregroundStyle(Theme.accent); Spacer(); Text(item.url.lastPathComponent).lineLimit(1) }
                                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .foregroundStyle(.white)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
        }
    }
}

struct TrimEditorView: View {
    let sourceURL: URL
    @ObservedObject var model: AppModel
    @State private var duration = 1.0
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var exporting = false
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                LocalVideoPlayer(url: sourceURL).frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .trailing, spacing: 12) {
                    Text("من \(fmt(start)) إلى \(fmt(end))").font(.headline)
                    Text("البداية").font(.caption).foregroundStyle(Theme.text2)
                    Slider(value: $start, in: 0...max(0.1, end - 0.1), step: 0.1).tint(Theme.accent)
                    Text("النهاية").font(.caption).foregroundStyle(Theme.text2)
                    Slider(value: $end, in: min(duration, start + 0.1)...max(duration, min(duration, start + 0.1)), step: 0.1).tint(Theme.accent)
                }
                .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                Button { exportTrim() } label: {
                    HStack { if exporting { ProgressView() }; Label("حفظ نسخة مقصوصة", systemImage: "scissors") }
                        .frame(maxWidth: .infinity).padding(15).background(Theme.accent, in: RoundedRectangle(cornerRadius: 17)).foregroundStyle(.black)
                }
                .disabled(exporting || end <= start)
                if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(Theme.text2) }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("قص الفيديو")
        .task {
            let asset = AVURLAsset(url: sourceURL)
            if let d = try? await asset.load(.duration) { duration = max(0.1, d.seconds); end = duration }
        }
    }

    private func fmt(_ s: Double) -> String { String(format: "%02d:%02d", Int(s) / 60, Int(s) % 60) }

    private func exportTrim() {
        exporting = true
        message = ""
        let asset = AVURLAsset(url: sourceURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { exporting = false; message = "تعذر تجهيز المحرر."; return }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dst = folder.appendingPathComponent("trimmed-\(Int(Date().timeIntervalSince1970)).mp4")
        export.outputURL = dst
        export.outputFileType = .mp4
        export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        export.exportAsynchronously {
            DispatchQueue.main.async {
                exporting = false
                if export.status == .completed { model.refreshLibrary(); model.refreshStorage(); message = "تم حفظ النسخة المقصوصة." }
                else { message = export.error?.localizedDescription ?? "فشل التصدير." }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: 18) {
                    Text("الإعدادات").font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .trailing)

                    SettingsCard(title: "الحفظ", icon: "square.and.arrow.down") {
                        Picker("مكان الحفظ", selection: Binding(get: { model.saveTarget }, set: { model.setSaveTarget($0) })) {
                            ForEach(SaveTarget.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }

                    SettingsCard(title: "المساحة", icon: "internaldrive") {
                        VStack(spacing: 12) {
                            storageRow("ملفات المكتبة", model.formattedBytes(model.libraryBytes))
                            storageRow("الكاش والملفات المؤقتة", model.formattedBytes(model.cacheBytes))
                            Divider().overlay(Color.white.opacity(0.08))
                            Button { model.clearCache() } label: { Label("حذف الكاش", systemImage: "sparkles") }.foregroundStyle(Theme.accent)
                            Button(role: .destructive) { confirmDeleteAll = true } label: { Label("حذف جميع ملفات التطبيق", systemImage: "trash") }
                        }
                    }

                    SettingsCard(title: "المنصات", icon: "link") {
                        Text("TikTok • YouTube • X • Instagram • Facebook • Web")
                            .font(.subheadline).foregroundStyle(Theme.text2)
                    }

                    if let toast = model.toast { Text(toast).font(.footnote).foregroundStyle(Theme.accent) }
                    Text("الإصدار 0.8").font(.caption).foregroundStyle(Theme.text2).frame(maxWidth: .infinity, alignment: .center).padding(.top, 10)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .onAppear { model.refreshStorage() }
            .confirmationDialog("حذف جميع الملفات المحفوظة داخل حمّل؟", isPresented: $confirmDeleteAll) {
                Button("حذف الكل", role: .destructive) { model.deleteAllAppFiles() }
                Button("إلغاء", role: .cancel) {}
            }
        }
    }

    private func storageRow(_ name: String, _ value: String) -> some View {
        HStack { Text(value).foregroundStyle(Theme.text2); Spacer(); Text(name) }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 14) {
            HStack { Spacer(); Text(title).font(.headline); Image(systemName: icon).foregroundStyle(Theme.accent) }
            content
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}
