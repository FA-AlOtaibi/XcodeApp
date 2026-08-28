import SwiftUI
import Foundation
import UIKit

@main
struct HammelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().environment(\.layoutDirection, .rightToLeft)
        }
    }
}

struct DownloadMedia: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let filename: String
    let type: String
    let thumb: URL?
    let referer: String?
}

enum PlatformKind: String {
    case tiktok = "TikTok"
    case youtube = "YouTube"
    case x = "X"
    case instagram = "Instagram"
    case facebook = "Facebook"
    case generic = "Web"
}

enum AppError: Error {
    case message(String)
    var text: String {
        if case let .message(v) = self { return v }
        return "حدث خطأ غير معروف."
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var input = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var results: [DownloadMedia] = []
    @Published var downloaded: [URL] = []
    @Published var activeEngine = "جاهز"
    @Published var detectedPlatform = "تلقائي"

    private let safariUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"

    func resolve() async {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = URL(string: value), source.scheme?.hasPrefix("http") == true else {
            error = "الصق رابطًا صحيحًا من TikTok أو Instagram أو YouTube أو X أو Facebook."
            return
        }

        isLoading = true
        error = nil
        results = []
        let platform = detectPlatform(source)
        detectedPlatform = platform.rawValue
        activeEngine = "جاري تحليل \(platform.rawValue)…"
        defer { isLoading = false }

        do {
            var media: [DownloadMedia] = []

            switch platform {
            case .tiktok:
                media = try await resolveTikTokDirect(source)
                activeEngine = "TikTok مباشر"

            case .youtube:
                media = try await resolveYouTubeDirect(source)
                activeEngine = "YouTube مباشر"

            case .x:
                media = try await resolveXDirect(source)
                activeEngine = "X مباشر"

            case .instagram:
                do {
                    media = try await resolveInstagramDirect(source)
                    activeEngine = "Instagram مباشر"
                } catch {
                    media = try await resolveWithFallbacks(source)
                }

            case .facebook:
                do {
                    media = try await resolveFacebookDirect(source)
                    activeEngine = "Facebook مباشر"
                } catch {
                    media = try await resolveWithFallbacks(source)
                }

            case .generic:
                do {
                    media = try await resolveGenericPage(source)
                    activeEngine = "استخراج مباشر من الصفحة"
                } catch {
                    media = try await resolveWithFallbacks(source)
                }
            }

            guard !media.isEmpty else {
                throw AppError.message("لم أجد وسائط قابلة للتنزيل في هذا الرابط.")
            }
            results = media
        } catch {
            self.error = readable(error)
            activeEngine = "تعذر الجلب"
        }
    }

    private func detectPlatform(_ url: URL) -> PlatformKind {
        let host = (url.host ?? "").lowercased()
        if host.contains("tiktok.com") || host.contains("tiktokv.com") { return .tiktok }
        if host.contains("youtube.com") || host.contains("youtu.be") { return .youtube }
        if host == "x.com" || host.hasSuffix(".x.com") || host.contains("twitter.com") { return .x }
        if host.contains("instagram.com") { return .instagram }
        if host.contains("facebook.com") || host.contains("fb.watch") { return .facebook }
        return .generic
    }

    // MARK: - TikTok

    private func resolveTikTokDirect(_ source: URL) async throws -> [DownloadMedia] {
        let (html, finalURL) = try await fetchHTML(source, referer: "https://www.tiktok.com/")

        var jsonObjects: [Any] = []
        let scriptPatterns = [
            #"<script[^>]*id=[\"']__UNIVERSAL_DATA_FOR_REHYDRATION__[\"'][^>]*>(.*?)</script>"#,
            #"<script[^>]*id=[\"']SIGI_STATE[\"'][^>]*>(.*?)</script>"#
        ]
        for pattern in scriptPatterns {
            if let raw = regexFirst(html, pattern: pattern),
               let d = raw.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) {
                jsonObjects.append(obj)
            }
        }

        for root in jsonObjects {
            if let play = firstURLString(in: root, preferredKeys: ["playAddr", "playAddrH264", "playAddrBytevc1"]),
               let videoURL = URL(string: play) {
                let thumbRaw = firstURLString(in: root, preferredKeys: ["cover", "originCover", "dynamicCover"])
                let thumb = thumbRaw.flatMap(URL.init(string:))
                let id = firstString(in: root, keys: ["id", "itemId", "aweme_id"]) ?? UUID().uuidString
                let author = firstString(in: root, keys: ["uniqueId", "nickname", "authorName"]) ?? "tiktok"
                return [DownloadMedia(url: videoURL, filename: "\(sanitize(author))-\(id).mp4", type: "video", thumb: thumb, referer: "https://www.tiktok.com/")]
            }
        }

        for pattern in [#"\"playAddr\"\s*:\s*\"([^\"]+)\""#, #"\"playAddrH264\"\s*:\s*\"([^\"]+)\""#] {
            if let raw0 = regexFirst(html, pattern: pattern) {
                let raw = decodeEscapedURL(raw0)
                if let u = URL(string: raw) {
                    return [DownloadMedia(url: u, filename: "tiktok-video.mp4", type: "video", thumb: nil, referer: finalURL.absoluteString)]
                }
            }
        }
        throw AppError.message("تعذر استخراج فيديو TikTok. قد يكون الفيديو خاصًا أو غير متاح في منطقتك.")
    }

    // MARK: - YouTube direct via InnerTube

    private func resolveYouTubeDirect(_ source: URL) async throws -> [DownloadMedia] {
        guard let videoID = youtubeVideoID(source) else {
            throw AppError.message("لم أتعرف على معرّف فيديو YouTube من الرابط.")
        }

        let clients: [(String, String, String, String)] = [
            ("ANDROID_VR", "1.71.26", "28", "com.google.android.apps.youtube.vr.oculus/1.71.26 (Linux; U; Android 12L) gzip"),
            ("IOS", "21.26.4", "5", "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"),
            ("WEB", "2.20260120.01.00", "1", safariUA)
        ]
        let key = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
        var lastReason = ""

        for client in clients {
            do {
                let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(key)&prettyPrint=false")!
                var req = URLRequest(url: endpoint)
                req.httpMethod = "POST"
                req.timeoutInterval = 25
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue(client.3, forHTTPHeaderField: "User-Agent")
                req.setValue(client.2, forHTTPHeaderField: "X-YouTube-Client-Name")
                req.setValue(client.1, forHTTPHeaderField: "X-YouTube-Client-Version")

                let body: [String: Any] = [
                    "context": ["client": [
                        "clientName": client.0,
                        "clientVersion": client.1,
                        "hl": "en",
                        "gl": "US",
                        "osName": client.0 == "IOS" ? "iPhone" : "Android"
                    ]],
                    "videoId": videoID,
                    "contentCheckOk": true,
                    "racyCheckOk": true,
                    "playbackContext": ["contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]]
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                if let playability = json["playabilityStatus"] as? [String: Any],
                   let status = playability["status"] as? String, status != "OK" {
                    lastReason = (playability["reason"] as? String) ?? status
                    continue
                }

                guard let streaming = json["streamingData"] as? [String: Any] else { continue }
                let details = json["videoDetails"] as? [String: Any]
                let title = sanitize((details?["title"] as? String) ?? "youtube-\(videoID)")
                let thumb = youtubeThumbnail(from: details)

                let progressive = (streaming["formats"] as? [[String: Any]] ?? [])
                    .filter { ($0["url"] as? String)?.hasPrefix("http") == true }
                    .sorted { youtubeFormatScore($0) > youtubeFormatScore($1) }

                if let best = progressive.first,
                   let raw = best["url"] as? String,
                   let url = URL(string: raw) {
                    let quality = (best["qualityLabel"] as? String) ?? "video"
                    return [DownloadMedia(url: url, filename: "\(title)-\(quality).mp4", type: "video", thumb: thumb, referer: "https://www.youtube.com/")]
                }

                let adaptive = (streaming["adaptiveFormats"] as? [[String: Any]] ?? [])
                let directVideos = adaptive.filter {
                    guard let mime = $0["mimeType"] as? String, mime.hasPrefix("video/"), ($0["url"] as? String)?.hasPrefix("http") == true else { return false }
                    return true
                }.sorted { youtubeFormatScore($0) > youtubeFormatScore($1) }

                if let bestVideo = directVideos.first,
                   let raw = bestVideo["url"] as? String,
                   let url = URL(string: raw) {
                    let ext = ((bestVideo["mimeType"] as? String)?.contains("webm") == true) ? "webm" : "mp4"
                    let quality = (bestVideo["qualityLabel"] as? String) ?? "video"
                    return [DownloadMedia(url: url, filename: "\(title)-\(quality).\(ext)", type: "video-only", thumb: thumb, referer: "https://www.youtube.com/")]
                }
            } catch {
                lastReason = error.localizedDescription
            }
        }

        throw AppError.message(lastReason.isEmpty ? "YouTube لم يرجع رابط تنزيل مباشر لهذا الفيديو." : "YouTube: \(lastReason)")
    }

    private func youtubeVideoID(_ url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        if host.contains("youtu.be") {
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? nil : id
        }
        if let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = c.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty { return v }
        let comps = url.pathComponents
        if let i = comps.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }), i + 1 < comps.count {
            return comps[i + 1]
        }
        return nil
    }

    private func youtubeFormatScore(_ f: [String: Any]) -> Int {
        let height = f["height"] as? Int ?? 0
        let fps = f["fps"] as? Int ?? 0
        let bitrate = f["bitrate"] as? Int ?? 0
        return height * 1_000_000 + fps * 10_000 + bitrate
    }

    private func youtubeThumbnail(from details: [String: Any]?) -> URL? {
        guard let thumbRoot = details?["thumbnail"] as? [String: Any],
              let thumbs = thumbRoot["thumbnails"] as? [[String: Any]] else { return nil }
        return thumbs.compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }.last
    }

    // MARK: - X / Twitter

    private func resolveXDirect(_ source: URL) async throws -> [DownloadMedia] {
        guard let statusID = xStatusID(source) else {
            throw AppError.message("لم أتعرف على رقم المنشور في رابط X.")
        }
        let user = xUsername(source) ?? "i"
        let endpoint = URL(string: "https://api.fxtwitter.com/\(user)/status/\(statusID)")!
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 20
        req.setValue("Hammel-iOS/0.6", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }

        let tweet = (json["tweet"] as? [String: Any]) ?? (json["status"] as? [String: Any]) ?? json
        let authorObj = tweet["author"] as? [String: Any]
        let author = sanitize((authorObj?["screen_name"] as? String) ?? (authorObj?["username"] as? String) ?? "x")
        var out: [DownloadMedia] = []

        if let media = tweet["media"] as? [String: Any] {
            if let videos = media["videos"] as? [[String: Any]] {
                for (idx, video) in videos.enumerated() {
                    let thumb = ((video["thumbnail_url"] as? String) ?? (video["thumbnail"] as? String)).flatMap(URL.init(string:))
                    var candidates: [(URL, Int)] = []
                    if let variants = video["variants"] as? [[String: Any]] {
                        for v in variants {
                            guard let raw = v["url"] as? String, let u = URL(string: raw), raw.contains(".mp4") else { continue }
                            candidates.append((u, v["bitrate"] as? Int ?? 0))
                        }
                    }
                    if let raw = video["url"] as? String, let u = URL(string: raw) { candidates.append((u, Int.max / 2)) }
                    if let best = candidates.max(by: { $0.1 < $1.1 })?.0 {
                        out.append(DownloadMedia(url: best, filename: "\(author)-\(statusID)-\(idx + 1).mp4", type: "video", thumb: thumb, referer: source.absoluteString))
                    }
                }
            }
            if let photos = media["photos"] as? [[String: Any]] {
                for (idx, p) in photos.enumerated() {
                    if let raw = (p["url"] as? String) ?? (p["media_url_https"] as? String), let u = URL(string: raw) {
                        out.append(DownloadMedia(url: u, filename: "\(author)-\(statusID)-photo-\(idx + 1).jpg", type: "photo", thumb: u, referer: source.absoluteString))
                    }
                }
            }
        }

        if out.isEmpty {
            if let raw = firstURLString(in: tweet, preferredKeys: ["url", "video_url", "media_url_https"]), let u = URL(string: raw), raw.contains("video") || raw.contains(".mp4") {
                out.append(DownloadMedia(url: u, filename: "\(author)-\(statusID).mp4", type: "video", thumb: nil, referer: source.absoluteString))
            }
        }

        guard !out.isEmpty else { throw AppError.message("لم أجد فيديو أو صورة قابلة للتنزيل في منشور X.") }
        return out
    }

    private func xStatusID(_ url: URL) -> String? {
        let comps = url.pathComponents
        if let i = comps.firstIndex(of: "status"), i + 1 < comps.count { return comps[i + 1].split(separator: "?").first.map(String.init) }
        return nil
    }

    private func xUsername(_ url: URL) -> String? {
        let comps = url.pathComponents.filter { $0 != "/" }
        guard let i = comps.firstIndex(of: "status"), i > 0 else { return nil }
        let user = comps[i - 1]
        return user == "i" ? nil : user
    }

    // MARK: - Instagram / Facebook / generic pages

    private func resolveInstagramDirect(_ source: URL) async throws -> [DownloadMedia] {
        let (html, finalURL) = try await fetchHTML(source, referer: "https://www.instagram.com/")
        var out: [DownloadMedia] = []

        let videoPatterns = [
            #"\"video_url\"\s*:\s*\"([^\"]+)\""#,
            #"property=[\"']og:video(?::secure_url)?[\"'][^>]*content=[\"']([^\"']+)"#,
            #"content=[\"']([^\"']+)[\"'][^>]*property=[\"']og:video(?::secure_url)?[\"']"#
        ]
        var seen = Set<String>()
        for p in videoPatterns {
            for raw0 in regexAll(html, pattern: p) {
                let raw = htmlDecode(decodeEscapedURL(raw0))
                guard seen.insert(raw).inserted, let u = URL(string: raw) else { continue }
                out.append(DownloadMedia(url: u, filename: "instagram-\(out.count + 1).mp4", type: "video", thumb: nil, referer: finalURL.absoluteString))
            }
        }

        if out.isEmpty {
            for raw0 in regexAll(html, pattern: #"\"display_url\"\s*:\s*\"([^\"]+)\""#) {
                let raw = htmlDecode(decodeEscapedURL(raw0))
                guard seen.insert(raw).inserted, let u = URL(string: raw) else { continue }
                out.append(DownloadMedia(url: u, filename: "instagram-photo-\(out.count + 1).jpg", type: "photo", thumb: u, referer: finalURL.absoluteString))
            }
        }

        if out.isEmpty { return try await resolveGenericHTML(html, finalURL: finalURL, prefix: "instagram") }
        return Array(out.prefix(20))
    }

    private func resolveFacebookDirect(_ source: URL) async throws -> [DownloadMedia] {
        let (html, finalURL) = try await fetchHTML(source, referer: "https://www.facebook.com/")
        let patterns = [
            #"\"browser_native_hd_url\"\s*:\s*\"([^\"]+)\""#,
            #"\"browser_native_sd_url\"\s*:\s*\"([^\"]+)\""#,
            #"property=[\"']og:video(?::secure_url)?[\"'][^>]*content=[\"']([^\"']+)"#
        ]
        var seen = Set<String>()
        var out: [DownloadMedia] = []
        for p in patterns {
            for raw0 in regexAll(html, pattern: p) {
                let raw = htmlDecode(decodeEscapedURL(raw0))
                guard seen.insert(raw).inserted, let u = URL(string: raw) else { continue }
                out.append(DownloadMedia(url: u, filename: "facebook-video-\(out.count + 1).mp4", type: "video", thumb: nil, referer: finalURL.absoluteString))
            }
        }
        if out.isEmpty { return try await resolveGenericHTML(html, finalURL: finalURL, prefix: "facebook") }
        return Array(out.prefix(10))
    }

    private func resolveGenericPage(_ source: URL) async throws -> [DownloadMedia] {
        let (html, finalURL) = try await fetchHTML(source, referer: nil)
        return try await resolveGenericHTML(html, finalURL: finalURL, prefix: sanitize(finalURL.host ?? "media"))
    }

    private func resolveGenericHTML(_ html: String, finalURL: URL, prefix: String) async throws -> [DownloadMedia] {
        var out: [DownloadMedia] = []
        var seen = Set<String>()
        let videoPatterns = [
            #"property=[\"']og:video(?::secure_url)?[\"'][^>]*content=[\"']([^\"']+)"#,
            #"content=[\"']([^\"']+)[\"'][^>]*property=[\"']og:video(?::secure_url)?[\"']"#,
            #"<video[^>]+src=[\"']([^\"']+)"#,
            #"<source[^>]+src=[\"']([^\"']+)"#
        ]
        for p in videoPatterns {
            for raw0 in regexAll(html, pattern: p) {
                let raw = htmlDecode(raw0)
                guard let u = absolutize(raw, against: finalURL), seen.insert(u.absoluteString).inserted else { continue }
                out.append(DownloadMedia(url: u, filename: "\(prefix)-video-\(out.count + 1).mp4", type: "video", thumb: nil, referer: finalURL.absoluteString))
            }
        }
        if out.isEmpty {
            for p in [#"property=[\"']og:image[\"'][^>]*content=[\"']([^\"']+)"#, #"content=[\"']([^\"']+)[\"'][^>]*property=[\"']og:image[\"']"#] {
                for raw0 in regexAll(html, pattern: p) {
                    let raw = htmlDecode(raw0)
                    guard let u = absolutize(raw, against: finalURL), seen.insert(u.absoluteString).inserted else { continue }
                    out.append(DownloadMedia(url: u, filename: "\(prefix)-image-\(out.count + 1).jpg", type: "photo", thumb: u, referer: finalURL.absoluteString))
                }
            }
        }
        guard !out.isEmpty else { throw AppError.message("الصفحة لا تعرض رابط وسائط مباشر يمكن استخراجه.") }
        return Array(out.prefix(20))
    }

    // MARK: - Cobalt fallback

    private func resolveWithFallbacks(_ source: URL) async throws -> [DownloadMedia] {
        let engines = try await discoverEngines()
        var lastError: Error = AppError.message("لم أجد محركًا بديلًا متاحًا.")
        for engine in engines.prefix(10) {
            do {
                let media = try await resolveViaCobalt(source: source, engine: engine)
                if !media.isEmpty {
                    activeEngine = "محرك احتياطي: \(engine.host ?? "Cobalt")"
                    return media
                }
            } catch { lastError = error }
        }
        throw lastError
    }

    private func discoverEngines() async throws -> [URL] {
        guard let listURL = URL(string: "https://instances.cobalt.best/api/instances.json") else { return [] }
        var req = URLRequest(url: listURL)
        req.timeoutInterval = 10
        req.setValue(safariUA, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var urls: [URL] = []
        for item in raw {
            let value = (item["api"] as? String) ?? (item["url"] as? String)
            guard var s = value?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { continue }
            if !s.hasPrefix("http") { s = "https://" + s }
            while s.hasSuffix("/") { s.removeLast() }
            guard let u = URL(string: s), u.host != "api.cobalt.tools" else { continue }
            urls.append(u)
        }
        return Array(NSOrderedSet(array: urls).array.compactMap { $0 as? URL }).shuffled()
    }

    private func resolveViaCobalt(source: URL, engine: URL) async throws -> [DownloadMedia] {
        var request = URLRequest(url: engine)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "url": source.absoluteString,
            "videoQuality": "1080",
            "downloadMode": "auto",
            "youtubeVideoCodec": "h264",
            "filenameStyle": "pretty",
            "tiktokFullAudio": false,
            "tiktokH265": false,
            "alwaysProxy": false
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.badServerResponse) }
        let status = json["status"] as? String ?? ""
        switch status {
        case "redirect", "tunnel":
            guard let raw = json["url"] as? String, let u = URL(string: raw) else { return [] }
            let name = (json["filename"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return [DownloadMedia(url: u, filename: (name?.isEmpty == false ? name! : defaultFilename(for: u)), type: "video", thumb: nil, referer: source.absoluteString)]
        case "picker":
            var items: [DownloadMedia] = []
            for (index, item) in (json["picker"] as? [[String: Any]] ?? []).enumerated() {
                guard let raw = item["url"] as? String, let u = URL(string: raw) else { continue }
                let kind = item["type"] as? String ?? "media"
                items.append(DownloadMedia(url: u, filename: "media-\(index + 1).\(fileExtension(kind: kind, url: u))", type: kind, thumb: (item["thumb"] as? String).flatMap(URL.init(string:)), referer: source.absoluteString))
            }
            if let audioRaw = json["audio"] as? String, let u = URL(string: audioRaw) {
                items.append(DownloadMedia(url: u, filename: (json["audioFilename"] as? String) ?? "audio.mp3", type: "audio", thumb: nil, referer: source.absoluteString))
            }
            return items
        case "error":
            let code = (json["error"] as? [String: Any])?["code"] as? String ?? "المحرك رفض الرابط"
            throw AppError.message(code)
        default:
            throw AppError.message("المحرك البديل لم يستطع جلب هذا الرابط.")
        }
    }

    // MARK: - Download

    func download(_ item: DownloadMedia) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            var req = URLRequest(url: item.url)
            req.timeoutInterval = 120
            req.setValue(safariUA, forHTTPHeaderField: "User-Agent")
            if let r = item.referer { req.setValue(r, forHTTPHeaderField: "Referer") }
            req.setValue("*/*", forHTTPHeaderField: "Accept")
            let (temp, response) = try await URLSession.shared.download(for: req)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { throw URLError(.badServerResponse) }

            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var filename = sanitizeFilename(item.filename)
            if (filename as NSString).pathExtension.isEmpty {
                filename += "." + (item.url.pathExtension.isEmpty ? defaultExtension(for: item.type) : item.url.pathExtension)
            }
            var destination = folder.appendingPathComponent(filename)
            var n = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                let base = (filename as NSString).deletingPathExtension
                let ext = (filename as NSString).pathExtension
                destination = folder.appendingPathComponent("\(base)-\(n)\(ext.isEmpty ? "" : ".\(ext)")")
                n += 1
            }
            try FileManager.default.moveItem(at: temp, to: destination)
            downloaded.insert(destination, at: 0)
        } catch {
            self.error = readable(error)
        }
    }

    // MARK: - Helpers

    private func fetchHTML(_ url: URL, referer: String?) async throws -> (String, URL) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue(safariUA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("ar-SA,ar;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let encodings: [String.Encoding] = [.utf8, .isoLatin1]
        var html: String?
        for enc in encodings where html == nil { html = String(data: data, encoding: enc) }
        guard let html, !html.isEmpty else { throw URLError(.cannotDecodeContentData) }
        return (html, response.url ?? url)
    }

    private func regexFirst(_ text: String, pattern: String) -> String? {
        regexAll(text, pattern: pattern).first
    }

    private func regexAll(_ text: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: ns).compactMap { m in
            guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    private func decodeEscapedURL(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\u003D", with: "=")
            .replacingOccurrences(of: "\\u0025", with: "%")
    }

    private func htmlDecode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private func absolutize(_ raw: String, against base: URL) -> URL? {
        if let u = URL(string: raw), u.scheme != nil { return u }
        return URL(string: raw, relativeTo: base)?.absoluteURL
    }

    private func firstURLString(in value: Any, preferredKeys: [String]) -> String? {
        if let dict = value as? [String: Any] {
            for key in preferredKeys {
                if let v = dict[key] as? String, v.hasPrefix("http") { return v }
                if let arr = dict[key] as? [String], let v = arr.first(where: { $0.hasPrefix("http") }) { return v }
                if let sub = dict[key] as? [String: Any] {
                    for nested in ["urlList", "UrlList", "url_list"] {
                        if let arr = sub[nested] as? [String], let v = arr.first(where: { $0.hasPrefix("http") }) { return v }
                    }
                }
            }
            for child in dict.values {
                if let found = firstURLString(in: child, preferredKeys: preferredKeys) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstURLString(in: child, preferredKeys: preferredKeys) { return found }
            }
        }
        return nil
    }

    private func firstString(in value: Any, keys: [String]) -> String? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let v = dict[key] as? String, !v.isEmpty { return v }
                if let n = dict[key] as? NSNumber { return n.stringValue }
            }
            for child in dict.values {
                if let found = firstString(in: child, keys: keys) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstString(in: child, keys: keys) { return found }
            }
        }
        return nil
    }

    private func defaultFilename(for url: URL) -> String { url.lastPathComponent.isEmpty ? "video.mp4" : url.lastPathComponent }
    private func fileExtension(kind: String, url: URL) -> String { if !url.pathExtension.isEmpty { return url.pathExtension }; return defaultExtension(for: kind) }
    private func defaultExtension(for type: String) -> String { type.contains("photo") || type.contains("image") ? "jpg" : (type.contains("audio") ? "m4a" : "mp4") }
    private func sanitize(_ value: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let clean = value.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "media" : String(clean.prefix(90))
    }
    private func sanitizeFilename(_ value: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let clean = value.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "media" : String(clean.prefix(140))
    }

    private func readable(_ error: Error) -> String {
        if let e = error as? AppError { return e.text }
        if let u = error as? URLError {
            switch u.code {
            case .timedOut: return "انتهت مهلة الاتصال. حاول مرة أخرى."
            case .notConnectedToInternet: return "لا يوجد اتصال بالإنترنت."
            case .cannotFindHost, .dnsLookupFailed: return "تعذر الوصول إلى الخادم."
            case .secureConnectionFailed: return "تعذر إنشاء اتصال آمن بالخادم."
            default: break
            }
        }
        return error.localizedDescription
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    inputCard
                    if model.isLoading { ProgressView("جاري التنفيذ…").padding() }
                    if let error = model.error { errorCard(error) }
                    if !model.results.isEmpty { resultsSection }
                    if !model.downloaded.isEmpty { downloadsSection }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("حمّل")
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(.orange.gradient)
                Image(systemName: "arrow.down.to.line.compact").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
            }.frame(width: 78, height: 78)
            VStack(alignment: .trailing, spacing: 5) {
                Text("حمّل").font(.largeTitle.bold())
                Text("TikTok • Instagram • YouTube • X • Facebook").font(.caption).foregroundStyle(.secondary)
                Text("الصق الرابط وسيختار التطبيق أفضل طريقة جلب تلقائيًا").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private var inputCard: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("الصق رابط المنشور أو الفيديو هنا", text: $model.input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                Button {
                    if let text = UIPasteboard.general.string { model.input = text }
                } label: { Image(systemName: "doc.on.clipboard") }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))

            Button { Task { await model.resolve() } } label: {
                Label("جلب المحتوى", systemImage: "sparkle.magnifyingglass")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundStyle(.white).background(.orange.gradient, in: RoundedRectangle(cornerRadius: 17))
            }
            .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)

            HStack(spacing: 7) {
                Circle().fill(model.activeEngine == "تعذر الجلب" ? .red : (model.isLoading ? .orange : .green)).frame(width: 8, height: 8)
                Text("\(model.detectedPlatform) • \(model.activeEngine)").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Text("المحتوى المتاح").font(.headline).frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(model.results) { item in
                HStack(spacing: 12) {
                    Button { Task { await model.download(item) } } label: {
                        Label("تنزيل", systemImage: "arrow.down.circle.fill")
                    }.buttonStyle(.borderedProminent).tint(.orange)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(item.filename).font(.subheadline.bold()).lineLimit(2)
                        Text(item.type.uppercased()).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .trailing)
                    Group {
                        if let thumb = item.thumb {
                            AsyncImage(url: thumb) { image in image.resizable().scaledToFill() } placeholder: { ProgressView() }
                        } else {
                            ZStack { Color(.tertiarySystemGroupedBackground); Image(systemName: item.type.contains("photo") ? "photo.fill" : "play.rectangle.fill").font(.title2).foregroundStyle(.orange) }
                        }
                    }.frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private var downloadsSection: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Text("تم التنزيل").font(.headline).frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(model.downloaded, id: \.self) { file in
                HStack {
                    ShareLink(item: file) { Label("مشاركة", systemImage: "square.and.arrow.up") }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(file.lastPathComponent).font(.subheadline.bold()).lineLimit(1)
                        Text("محفوظ داخل التطبيق").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private func errorCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.footnote).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}
