import SwiftUI
import Foundation
import UIKit
import Photos
import AVFoundation
import UniformTypeIdentifiers

@main
struct HammelApp: App {
    var body: some Scene {
        WindowGroup {
            RootView().environment(\.layoutDirection, .rightToLeft)
        }
    }
}

enum PlatformKind: String, CaseIterable {
    case tiktok = "TikTok", youtube = "YouTube", x = "X", instagram = "Instagram", facebook = "Facebook", generic = "Web"
}

enum SaveTarget: String, CaseIterable, Identifiable {
    case app = "داخل التطبيق"
    case photos = "الصور"
    case ask = "اسألني كل مرة"
    var id: String { rawValue }
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
}

enum AppError: Error {
    case message(String)
    var text: String { if case let .message(v) = self { return v }; return "حدث خطأ غير معروف." }
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
    @Published var progressText = ""
    @Published var saveTarget: SaveTarget = SaveTarget(rawValue: UserDefaults.standard.string(forKey: "saveTarget") ?? "") ?? .app
    @Published var lastSavedToPhotos = false

    private let safariUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"

    init() { refreshLibrary() }

    func setSaveTarget(_ target: SaveTarget) {
        saveTarget = target
        UserDefaults.standard.set(target.rawValue, forKey: "saveTarget")
    }

    func resolve() async {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = URL(string: value), source.scheme?.hasPrefix("http") == true else {
            error = "الصق رابطًا صحيحًا من منصة مدعومة."
            return
        }
        isLoading = true; error = nil; results = []; progressText = ""
        let platform = detectPlatform(source)
        detectedPlatform = platform.rawValue
        activeEngine = "جاري تحليل \(platform.rawValue)…"
        defer { isLoading = false }
        do {
            let media: [DownloadMedia]
            switch platform {
            case .tiktok:
                media = try await resolveTikTok(source); activeEngine = "TikTok مباشر"
            case .youtube:
                media = try await resolveYouTube(source); activeEngine = "YouTube"
            case .x:
                media = try await resolveX(source); activeEngine = "X مباشر"
            case .instagram:
                media = try await resolveMetaPage(source, platform: .instagram); activeEngine = "Instagram"
            case .facebook:
                media = try await resolveMetaPage(source, platform: .facebook); activeEngine = "Facebook"
            case .generic:
                media = try await resolveGeneric(source); activeEngine = "Web"
            }
            guard !media.isEmpty else { throw AppError.message("لم أجد وسائط قابلة للتنزيل في الرابط.") }
            results = media
        } catch {
            self.error = readable(error)
            activeEngine = "تعذر الجلب"
        }
    }

    func download(_ item: DownloadMedia, overrideTarget: SaveTarget? = nil) async {
        let target = overrideTarget ?? saveTarget
        if target == .ask { return }
        isLoading = true; error = nil; progressText = "جاري تنزيل الملف…"; lastSavedToPhotos = false
        defer { isLoading = false; progressText = "" }
        do {
            var req = URLRequest(url: item.url)
            req.timeoutInterval = 120
            req.setValue(safariUA, forHTTPHeaderField: "User-Agent")
            if let r = item.referer { req.setValue(r, forHTTPHeaderField: "Referer") }
            let (temp, response) = try await URLSession.shared.download(for: req)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let saved = try persist(temp: temp, filename: item.filename)
            if target == .photos {
                try await saveToPhotos(saved)
                lastSavedToPhotos = true
            }
            refreshLibrary()
        } catch { self.error = readable(error) }
    }

    func saveExistingToPhotos(_ url: URL) async {
        do { try await saveToPhotos(url); lastSavedToPhotos = true } catch { self.error = readable(error) }
    }

    func deleteLocal(_ item: LocalMedia) {
        try? FileManager.default.removeItem(at: item.url)
        refreshLibrary()
    }

    func refreshLibrary() {
        let folder = mediaFolder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        library = urls.filter { !$0.hasDirectoryPath }.map { u in
            let d = (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return LocalMedia(url: u, createdAt: d)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private func mediaFolder() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel", isDirectory: true)
    }

    private func persist(temp: URL, filename: String) throws -> URL {
        let folder = mediaFolder(); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var name = sanitize(filename)
        if (name as NSString).pathExtension.isEmpty { name += ".mp4" }
        var dst = folder.appendingPathComponent(name); var n = 2
        while FileManager.default.fileExists(atPath: dst.path) {
            let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
            dst = folder.appendingPathComponent("\(base)-\(n).\(ext)"); n += 1
        }
        try FileManager.default.moveItem(at: temp, to: dst)
        return dst
    }

    private func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw AppError.message("اسمح للتطبيق بإضافة الفيديوهات إلى الصور من إعدادات الخصوصية.") }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                if ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }) { ok, err in ok ? cont.resume() : cont.resume(throwing: err ?? AppError.message("تعذر الحفظ في الصور.")) }
        }
    }

    private func detectPlatform(_ url: URL) -> PlatformKind {
        let h = (url.host ?? "").lowercased()
        if h.contains("tiktok.com") || h.contains("tiktokv.com") { return .tiktok }
        if h.contains("youtube.com") || h.contains("youtu.be") { return .youtube }
        if h == "x.com" || h.hasSuffix(".x.com") || h.contains("twitter.com") { return .x }
        if h.contains("instagram.com") { return .instagram }
        if h.contains("facebook.com") || h.contains("fb.watch") { return .facebook }
        return .generic
    }

    // MARK: TikTok
    private func resolveTikTok(_ source: URL) async throws -> [DownloadMedia] {
        let (html, finalURL) = try await fetchHTML(source, referer: "https://www.tiktok.com/")
        let patterns = [
            #"<script[^>]*id=[\"']__UNIVERSAL_DATA_FOR_REHYDRATION__[\"'][^>]*>(.*?)</script>"#,
            #"<script[^>]*id=[\"']SIGI_STATE[\"'][^>]*>(.*?)</script>"#
        ]
        for p in patterns {
            if let raw = regexFirst(html, pattern: p), let d = raw.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d),
               let play = firstURLString(in: obj, keys: ["playAddr", "playAddrH264", "playAddrBytevc1"]), let u = URL(string: play) {
                let cover = firstURLString(in: obj, keys: ["cover", "originCover", "dynamicCover"]).flatMap(URL.init(string:))
                let id = firstString(in: obj, keys: ["id", "itemId", "aweme_id"]) ?? UUID().uuidString
                let author = sanitize(firstString(in: obj, keys: ["uniqueId", "nickname"]) ?? "tiktok")
                return [DownloadMedia(url: u, filename: "\(author)-\(id).mp4", type: "video", thumb: cover, referer: "https://www.tiktok.com/", platform: .tiktok)]
            }
        }
        for p in [#"\"playAddr\"\s*:\s*\"([^\"]+)\""#, #"\"playAddrH264\"\s*:\s*\"([^\"]+)\""#] {
            if let raw = regexFirst(html, pattern: p), let u = URL(string: decodeEscapedURL(raw)) {
                return [DownloadMedia(url: u, filename: "tiktok-video.mp4", type: "video", thumb: nil, referer: finalURL.absoluteString, platform: .tiktok)]
            }
        }
        throw AppError.message("تعذر استخراج فيديو TikTok.")
    }

    // MARK: YouTube – watch page first, then Invidious fallback
    private func resolveYouTube(_ source: URL) async throws -> [DownloadMedia] {
        guard let id = youtubeVideoID(source) else { throw AppError.message("لم أتعرف على معرّف فيديو YouTube.") }
        if let direct = try? await resolveYouTubeWatchPage(id: id), !direct.isEmpty { return direct }
        return try await resolveYouTubeInvidious(id: id)
    }

    private func resolveYouTubeWatchPage(id: String) async throws -> [DownloadMedia] {
        let url = URL(string: "https://www.youtube.com/watch?v=\(id)&hl=en&gl=US&bpctr=9999999999")!
        let (html, _) = try await fetchHTML(url, referer: "https://www.youtube.com/")
        guard let jsonText = extractJSONObject(after: "ytInitialPlayerResponse =", in: html) ?? extractJSONObject(after: "var ytInitialPlayerResponse =", in: html),
              let data = jsonText.data(using: .utf8), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AppError.message("تعذر قراءة بيانات YouTube.") }
        if let p = json["playabilityStatus"] as? [String: Any], let status = p["status"] as? String, status != "OK" { throw AppError.message((p["reason"] as? String) ?? status) }
        return youtubeItems(from: json, id: id)
    }

    private func resolveYouTubeInvidious(id: String) async throws -> [DownloadMedia] {
        let listURL = URL(string: "https://api.invidious.io/instances.json?sort_by=health")!
        let (data, _) = try await URLSession.shared.data(from: listURL)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [[Any]] else { throw AppError.message("تعذر العثور على محرك YouTube متاح.") }
        var last = ""
        for row in raw.prefix(20) {
            guard row.count > 1, let meta = row[1] as? [String: Any], (meta["api"] as? Bool) == true,
                  let uri = meta["uri"] as? String, let endpoint = URL(string: "\(uri)/api/v1/videos/\(id)") else { continue }
            do {
                var req = URLRequest(url: endpoint); req.timeoutInterval = 10; req.setValue(safariUA, forHTTPHeaderField: "User-Agent")
                let (d, r) = try await URLSession.shared.data(for: req)
                guard let h = r as? HTTPURLResponse, (200..<300).contains(h.statusCode), let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                let title = sanitize((j["title"] as? String) ?? "youtube-\(id)")
                let thumb = (j["videoThumbnails"] as? [[String: Any]])?.compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }.last
                let formats = (j["formatStreams"] as? [[String: Any]] ?? []).compactMap { f -> (URL, Int, String)? in
                    guard let rawURL = f["url"] as? String, let u = URL(string: rawURL) else { return nil }
                    let q = f["qualityLabel"] as? String ?? f["quality"] as? String ?? "video"
                    let n = Int(q.filter(\.isNumber)) ?? 0
                    return (u, n, q)
                }.sorted { $0.1 > $1.1 }
                if let best = formats.first { return [DownloadMedia(url: best.0, filename: "\(title)-\(best.2).mp4", type: "video", thumb: thumb, referer: "https://www.youtube.com/", platform: .youtube)] }
            } catch { last = error.localizedDescription }
        }
        throw AppError.message(last.isEmpty ? "تعذر تنزيل فيديو YouTube حاليًا. جرّب بعد قليل." : "YouTube: \(last)")
    }

    private func youtubeItems(from json: [String: Any], id: String) -> [DownloadMedia] {
        guard let s = json["streamingData"] as? [String: Any] else { return [] }
        let details = json["videoDetails"] as? [String: Any]
        let title = sanitize((details?["title"] as? String) ?? "youtube-\(id)")
        let thumb = ((details?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }.last
        let formats = (s["formats"] as? [[String: Any]] ?? []).compactMap { f -> (URL, Int, String)? in
            guard let raw = f["url"] as? String, let u = URL(string: raw) else { return nil }
            let q = f["qualityLabel"] as? String ?? "video"; let h = f["height"] as? Int ?? 0
            return (u, h, q)
        }.sorted { $0.1 > $1.1 }
        guard let best = formats.first else { return [] }
        return [DownloadMedia(url: best.0, filename: "\(title)-\(best.2).mp4", type: "video", thumb: thumb, referer: "https://www.youtube.com/", platform: .youtube)]
    }

    private func youtubeVideoID(_ url: URL) -> String? {
        let h = (url.host ?? "").lowercased()
        if h.contains("youtu.be") { return url.pathComponents.dropFirst().first }
        if let c = URLComponents(url: url, resolvingAgainstBaseURL: false), let v = c.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty { return v }
        let comps = url.pathComponents
        if let i = comps.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }), i + 1 < comps.count { return comps[i + 1] }
        return nil
    }

    // MARK: X
    private func resolveX(_ source: URL) async throws -> [DownloadMedia] {
        guard let sid = source.pathComponents.first(where: { $0.allSatisfy(\.isNumber) && $0.count > 8 }) else { throw AppError.message("لم أتعرف على منشور X.") }
        let comps = source.pathComponents; let user = comps.count > 1 ? comps[1] : "i"
        let endpoint = URL(string: "https://api.fxtwitter.com/\(user)/status/\(sid)")!
        let (d, r) = try await URLSession.shared.data(from: endpoint)
        guard let h = r as? HTTPURLResponse, (200..<300).contains(h.statusCode), let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw URLError(.badServerResponse) }
        let tweet = (j["tweet"] as? [String: Any]) ?? j
        var out: [DownloadMedia] = []
        if let media = tweet["media"] as? [String: Any] {
            if let videos = media["videos"] as? [[String: Any]] {
                for (i, v) in videos.enumerated() {
                    let vars = (v["variants"] as? [[String: Any]] ?? []).compactMap { x -> (URL, Int)? in
                        guard let s = x["url"] as? String, s.contains(".mp4"), let u = URL(string: s) else { return nil }; return (u, x["bitrate"] as? Int ?? 0)
                    }
                    if let best = vars.max(by: { $0.1 < $1.1 }) { out.append(DownloadMedia(url: best.0, filename: "x-\(sid)-\(i+1).mp4", type: "video", thumb: nil, referer: source.absoluteString, platform: .x)) }
                }
            }
            if let photos = media["photos"] as? [[String: Any]] {
                for (i, p) in photos.enumerated() { if let s = p["url"] as? String, let u = URL(string: s) { out.append(DownloadMedia(url: u, filename: "x-\(sid)-\(i+1).jpg", type: "photo", thumb: u, referer: source.absoluteString, platform: .x)) } }
            }
        }
        if out.isEmpty { throw AppError.message("لا توجد وسائط قابلة للتنزيل في منشور X.") }
        return out
    }

    // MARK: Meta + Generic
    private func resolveMetaPage(_ source: URL, platform: PlatformKind) async throws -> [DownloadMedia] {
        let (html, finalURL) = try await fetchHTML(source, referer: source.absoluteString)
        let candidates = metaURLs(html, names: ["og:video", "og:video:url", "twitter:player:stream"])
        if let raw = candidates.first, let u = URL(string: htmlDecode(raw)) { return [DownloadMedia(url: u, filename: "\(platform.rawValue.lowercased())-video.mp4", type: "video", thumb: nil, referer: finalURL.absoluteString, platform: platform)] }
        let pics = metaURLs(html, names: ["og:image", "twitter:image"])
        if let raw = pics.first, let u = URL(string: htmlDecode(raw)) { return [DownloadMedia(url: u, filename: "\(platform.rawValue.lowercased())-image.jpg", type: "photo", thumb: u, referer: finalURL.absoluteString, platform: platform)] }
        throw AppError.message("تعذر استخراج الوسائط من \(platform.rawValue). قد يحتاج المنشور لتسجيل دخول أو يكون خاصًا.")
    }

    private func resolveGeneric(_ source: URL) async throws -> [DownloadMedia] { try await resolveMetaPage(source, platform: .generic) }

    // MARK: Helpers
    private func fetchHTML(_ url: URL, referer: String?) async throws -> (String, URL) {
        var req = URLRequest(url: url); req.timeoutInterval = 30; req.setValue(safariUA, forHTTPHeaderField: "User-Agent"); req.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept"); if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
        let (d, r) = try await URLSession.shared.data(for: req)
        guard let h = r as? HTTPURLResponse, (200..<400).contains(h.statusCode), let s = String(data: d, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return (s, h.url ?? url)
    }

    private func regexFirst(_ s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }; return String(s[r])
    }

    private func extractJSONObject(after marker: String, in text: String) -> String? {
        guard let mr = text.range(of: marker) else { return nil }
        var i = mr.upperBound
        while i < text.endIndex, text[i] != "{" { i = text.index(after: i) }
        guard i < text.endIndex else { return nil }
        var depth = 0, inString = false, escape = false, j = i
        while j < text.endIndex {
            let c = text[j]
            if inString { if escape { escape = false } else if c == "\\" { escape = true } else if c == "\"" { inString = false } }
            else { if c == "\"" { inString = true } else if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { return String(text[i...j]) } } }
            j = text.index(after: j)
        }
        return nil
    }

    private func metaURLs(_ html: String, names: [String]) -> [String] {
        var out: [String] = []
        for n in names {
            let esc = NSRegularExpression.escapedPattern(for: n)
            for p in [#"<meta[^>]+(?:property|name)=[\"']"# + esc + #"[\"'][^>]+content=[\"']([^\"']+)[\"']"#, #"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']"# + esc + #"[\"']"#] { if let x = regexFirst(html, pattern: p) { out.append(x) } }
        }
        return out
    }

    private func firstURLString(in v: Any, keys: [String]) -> String? {
        if let d = v as? [String: Any] { for k in keys { if let s = d[k] as? String, s.hasPrefix("http") { return s }; if let a = d[k] as? [String], let s = a.first(where: { $0.hasPrefix("http") }) { return s }; if let sub = d[k] as? [String: Any], let a = (sub["urlList"] ?? sub["url_list"]) as? [String], let s = a.first { return s } }; for c in d.values { if let x = firstURLString(in: c, keys: keys) { return x } } }
        if let a = v as? [Any] { for c in a { if let x = firstURLString(in: c, keys: keys) { return x } } }
        return nil
    }

    private func firstString(in v: Any, keys: [String]) -> String? {
        if let d = v as? [String: Any] { for k in keys { if let s = d[k] as? String, !s.isEmpty { return s }; if let n = d[k] as? NSNumber { return n.stringValue } }; for c in d.values { if let x = firstString(in: c, keys: keys) { return x } } }
        if let a = v as? [Any] { for c in a { if let x = firstString(in: c, keys: keys) { return x } } }
        return nil
    }

    private func decodeEscapedURL(_ s: String) -> String { s.replacingOccurrences(of: "\\u002F", with: "/").replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "\\u0026", with: "&") }
    private func htmlDecode(_ s: String) -> String { s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#x2F;", with: "/").replacingOccurrences(of: "&quot;", with: "\"") }
    private func sanitize(_ s: String) -> String { let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>"); let x = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines); return x.isEmpty ? "media" : String(x.prefix(100)) }
    private func readable(_ e: Error) -> String { if let a = e as? AppError { return a.text }; if let u = e as? URLError { if u.code == .timedOut { return "انتهت مهلة الاتصال. حاول مرة أخرى." }; if u.code == .notConnectedToInternet { return "لا يوجد اتصال بالإنترنت." } }; return e.localizedDescription }
}

struct RootView: View {
    @StateObject private var model = AppModel()
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            HomeView(model: model, goLibrary: { tab = 1 }).tabItem { Label("الرئيسية", systemImage: "sparkles") }.tag(0)
            LibraryView(model: model).tabItem { Label("المكتبة", systemImage: "rectangle.stack.fill") }.tag(1)
            StudioView(model: model).tabItem { Label("الاستوديو", systemImage: "slider.horizontal.3") }.tag(2)
            SettingsView(model: model).tabItem { Label("الإعدادات", systemImage: "gearshape.fill") }.tag(3)
        }.tint(.orange)
    }
}

struct HomeView: View {
    @ObservedObject var model: AppModel
    let goLibrary: () -> Void
    @State private var askItem: DownloadMedia?
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color.black, Color(.systemGray6).opacity(0.15)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        HStack {
                            VStack(alignment: .trailing, spacing: 4) { Text("حمّل").font(.system(size: 38, weight: .black)); Text("نزّل، احفظ، وعدّل").foregroundStyle(.secondary) }
                            Spacer()
                            ZStack { RoundedRectangle(cornerRadius: 22).fill(.orange.gradient); Image(systemName: "arrow.down.to.line.compact").font(.system(size: 34, weight: .bold)).foregroundStyle(.white) }.frame(width: 72, height: 72)
                        }
                        .padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30))

                        VStack(spacing: 12) {
                            HStack(spacing: 10) {
                                Button { model.input = UIPasteboard.general.string ?? "" } label: { Image(systemName: "doc.on.clipboard.fill").font(.title3).frame(width: 42, height: 42).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14)) }
                                TextField("الصق رابط TikTok / YouTube / X…", text: $model.input).textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing).padding(.vertical, 14)
                            }.padding(.horizontal, 14).background(Color(.secondarySystemBackground).opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
                            Button { Task { await model.resolve() } } label: { HStack { if model.isLoading { ProgressView().tint(.white) }; Text(model.isLoading ? "جاري التحليل" : "جلب المحتوى").font(.headline); Image(systemName: "arrow.down.circle.fill") }.frame(maxWidth: .infinity).padding(.vertical, 15).foregroundStyle(.white).background(.orange.gradient, in: RoundedRectangle(cornerRadius: 20)) }.disabled(model.input.isEmpty || model.isLoading)
                            HStack { statusDot; Text("\(model.detectedPlatform) • \(model.activeEngine)").font(.caption).foregroundStyle(.secondary); Spacer() }
                        }

                        if let e = model.error { Label(e, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .trailing).padding(14).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18)) }
                        if !model.results.isEmpty { resultSection }
                        if model.lastSavedToPhotos { Label("تم الحفظ في تطبيق الصور", systemImage: "checkmark.circle.fill").foregroundStyle(.green).padding(12).frame(maxWidth: .infinity).background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 16)) }
                    }.padding()
                }
            }.navigationBarHidden(true)
        }.confirmationDialog("مكان الحفظ", item: $askItem) { item in
            Button("داخل التطبيق") { Task { await model.download(item, overrideTarget: .app) } }
            Button("الصور") { Task { await model.download(item, overrideTarget: .photos) } }
            Button("إلغاء", role: .cancel) {}
        }
    }

    private var statusDot: some View { Circle().fill(model.activeEngine == "تعذر الجلب" ? .red : .green).frame(width: 8, height: 8) }
    private var resultSection: some View {
        VStack(alignment: .trailing, spacing: 12) {
            HStack { Button("المكتبة", action: goLibrary).font(.subheadline); Spacer(); Text("المحتوى المتاح").font(.title3.bold()) }
            ForEach(model.results) { item in
                HStack(spacing: 12) {
                    Button { if model.saveTarget == .ask { askItem = item } else { Task { await model.download(item) } } } label: { Image(systemName: "arrow.down").font(.headline).frame(width: 46, height: 46).foregroundStyle(.white).background(.orange.gradient, in: RoundedRectangle(cornerRadius: 15)) }
                    VStack(alignment: .trailing, spacing: 5) { Text(item.filename).font(.subheadline.bold()).lineLimit(2); Text("\(item.platform.rawValue) • \(item.type)").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .trailing)
                    Group { if let t = item.thumb { AsyncImage(url: t) { im in im.resizable().scaledToFill() } placeholder: { ProgressView() } } else { ZStack { Color(.tertiarySystemBackground); Image(systemName: item.type == "photo" ? "photo.fill" : "play.fill").foregroundStyle(.orange) } } }.frame(width: 82, height: 72).clipShape(RoundedRectangle(cornerRadius: 16))
                }.padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            }
        }
    }
}

struct LibraryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        NavigationStack {
            Group {
                if model.library.isEmpty { ContentUnavailableView("المكتبة فارغة", systemImage: "rectangle.stack", description: Text("الفيديوهات والصور التي تحملها تظهر هنا.")) }
                else { ScrollView { LazyVStack(spacing: 12) { ForEach(model.library) { item in NavigationLink(destination: MediaDetailView(model: model, item: item)) { HStack(spacing: 12) { Image(systemName: ["jpg","jpeg","png","webp"].contains(item.url.pathExtension.lowercased()) ? "photo.fill" : "play.rectangle.fill").font(.title2).foregroundStyle(.orange).frame(width: 56, height: 56).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16)); VStack(alignment: .trailing, spacing: 4) { Text(item.url.lastPathComponent).foregroundStyle(.primary).lineLimit(1); Text(item.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .trailing); Image(systemName: "chevron.left").foregroundStyle(.secondary) }.padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20)) }.buttonStyle(.plain) } }.padding() } }
            .navigationTitle("المكتبة").toolbar { Button { model.refreshLibrary() } label: { Image(systemName: "arrow.clockwise") } }
        }
    }
}

struct MediaDetailView: View {
    @ObservedObject var model: AppModel
    let item: LocalMedia
    var body: some View {
        VStack(spacing: 18) {
            QuickLookCard(url: item.url).frame(maxWidth: .infinity, maxHeight: 360)
            Text(item.url.lastPathComponent).font(.headline).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                ShareLink(item: item.url) { Label("مشاركة", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                Button { Task { await model.saveExistingToPhotos(item.url) } } label: { Label("حفظ بالصور", systemImage: "photo.badge.plus") }.buttonStyle(.borderedProminent).tint(.orange)
            }
            NavigationLink { TrimEditorView(sourceURL: item.url, model: model) } label: { Label("تعديل وقص الفيديو", systemImage: "scissors").frame(maxWidth: .infinity).padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18)) }
            Button(role: .destructive) { model.deleteLocal(item) } label: { Label("حذف من المكتبة", systemImage: "trash") }
            Spacer()
        }.padding().navigationTitle("الوسائط").navigationBarTitleDisplayMode(.inline)
    }
}

struct QuickLookCard: View {
    let url: URL
    var body: some View {
        ZStack { RoundedRectangle(cornerRadius: 26).fill(.thinMaterial); if ["jpg","jpeg","png","webp"].contains(url.pathExtension.lowercased()), let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 22)) } else { VStack(spacing: 12) { Image(systemName: "play.circle.fill").font(.system(size: 72)).foregroundStyle(.orange); Text("فيديو جاهز للتعديل").foregroundStyle(.secondary) } } }
    }
}

struct StudioView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        NavigationStack {
            List {
                Section("أدوات سريعة") {
                    Label("قص بداية ونهاية الفيديو", systemImage: "scissors")
                    Label("حفظ نسخة إلى الصور", systemImage: "photo.on.rectangle")
                    Label("مشاركة إلى Files أو أي تطبيق", systemImage: "square.and.arrow.up")
                }
                Section("اختر فيديو من المكتبة") { ForEach(model.library.filter { ["mp4","mov","m4v"].contains($0.url.pathExtension.lowercased()) }) { item in NavigationLink(item.url.lastPathComponent) { TrimEditorView(sourceURL: item.url, model: model) } } }
            }.navigationTitle("الاستوديو")
        }
    }
}

struct TrimEditorView: View {
    let sourceURL: URL
    @ObservedObject var model: AppModel
    @State private var duration: Double = 1
    @State private var start: Double = 0
    @State private var end: Double = 1
    @State private var exporting = false
    @State private var message = ""
    var body: some View {
        Form {
            Section("القص") {
                Text("من \(time(start)) إلى \(time(end))")
                Slider(value: $start, in: 0...max(0.1, end - 0.1), step: 0.1)
                Slider(value: $end, in: min(duration, start + 0.1)...max(min(duration, start + 0.1), duration), step: 0.1)
            }
            Section { Button { Task { await exportTrim() } } label: { HStack { if exporting { ProgressView() }; Label("حفظ نسخة مقصوصة", systemImage: "scissors") } }.disabled(exporting || end <= start) }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
        }.navigationTitle("قص الفيديو").task { let asset = AVURLAsset(url: sourceURL); if let d = try? await asset.load(.duration) { duration = max(0.1, d.seconds); end = duration } }
    }

    private func time(_ s: Double) -> String { String(format: "%02d:%02d", Int(s)/60, Int(s)%60) }
    private func exportTrim() async {
        exporting = true; defer { exporting = false }
        do {
            let asset = AVURLAsset(url: sourceURL)
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { throw AppError.message("تعذر تجهيز محرر الفيديو.") }
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dst = folder.appendingPathComponent("trimmed-\(Int(Date().timeIntervalSince1970)).mp4")
            export.outputURL = dst; export.outputFileType = .mp4
            export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
            try await export.export(to: dst, as: .mp4)
            model.refreshLibrary(); message = "تم حفظ النسخة المقصوصة في المكتبة."
        } catch { message = error.localizedDescription }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        NavigationStack {
            Form {
                Section("مكان الحفظ الافتراضي") {
                    Picker("مكان الحفظ", selection: Binding(get: { model.saveTarget }, set: { model.setSaveTarget($0) })) { ForEach(SaveTarget.allCases) { Text($0.rawValue).tag($0) } }
                    Text("تقدر تحفظ داخل التطبيق، مباشرة في ألبوم الصور، أو تختار في كل تنزيل.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("المنصات") { Text("TikTok • YouTube • X • Instagram • Facebook • روابط الويب المباشرة") }
                Section("عن التطبيق") { LabeledContent("الإصدار", value: "0.7 Studio"); Text("التحميل يخضع لتوفر الوسائط وقيود كل منصة. استخدمه للمحتوى الذي يحق لك حفظه.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("الإعدادات")
        }
    }
}
