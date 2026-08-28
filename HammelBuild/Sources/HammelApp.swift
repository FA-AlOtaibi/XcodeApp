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
}

@MainActor
final class AppModel: ObservableObject {
    @Published var input = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var results: [DownloadMedia] = []
    @Published var downloaded: [URL] = []
    @Published var activeEngine = "جاهز"

    func resolve() async {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = URL(string: value), source.scheme?.hasPrefix("http") == true else {
            error = "الصق رابطًا صحيحًا من TikTok أو Instagram أو YouTube أو Facebook."
            return
        }

        isLoading = true
        error = nil
        results = []
        activeEngine = "جاري التحليل…"
        defer { isLoading = false }

        do {
            if isTikTok(source) {
                let media = try await resolveTikTokDirect(source)
                guard !media.isEmpty else { throw AppError.message("لم أجد فيديو قابلًا للتنزيل في رابط TikTok هذا.") }
                results = media
                activeEngine = "TikTok مباشر"
                return
            }

            let engines = try await discoverEngines()
            guard !engines.isEmpty else {
                throw AppError.message("TikTok يعمل مباشرة. بقية المنصات تحتاج محركًا متاحًا، ولم أجد واحدًا الآن.")
            }
            var lastError: Error = AppError.message("تعذر جلب المحتوى.")
            for engine in engines.prefix(8) {
                do {
                    let media = try await resolveViaCobalt(source: source, engine: engine)
                    if !media.isEmpty {
                        activeEngine = engine.host ?? "محرك متاح"
                        results = media
                        return
                    }
                } catch { lastError = error }
            }
            throw lastError
        } catch {
            self.error = readable(error)
            activeEngine = "تعذر الجلب"
        }
    }

    private func isTikTok(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("tiktok.com") || host.contains("tiktokv.com")
    }

    private func resolveTikTokDirect(_ source: URL) async throws -> [DownloadMedia] {
        var request = URLRequest(url: source)
        request.timeoutInterval = 25
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("ar-SA,ar;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw AppError.message("TikTok لم يرجع صفحة قابلة للتحليل.")
        }

        var jsonObjects: [Any] = []
        let scriptPatterns = [
            #"<script[^>]*id=[\"']__UNIVERSAL_DATA_FOR_REHYDRATION__[\"'][^>]*>(.*?)</script>"#,
            #"<script[^>]*id=[\"']SIGI_STATE[\"'][^>]*>(.*?)</script>"#
        ]

        for pattern in scriptPatterns {
            if let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
               let match = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html) {
                let raw = String(html[range])
                if let d = raw.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) {
                    jsonObjects.append(obj)
                }
            }
        }

        // Some TikTok responses embed the video object directly in the HTML.
        if jsonObjects.isEmpty,
           let re = try? NSRegularExpression(pattern: #"\{\"ItemModule\".*?\}\}\}"#, options: [.dotMatchesLineSeparators]),
           let match = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range, in: html),
           let d = String(html[range]).data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) {
            jsonObjects.append(obj)
        }

        for root in jsonObjects {
            if let play = firstURLString(in: root, preferredKeys: ["playAddr", "playAddrH264", "playAddrBytevc1"]),
               let videoURL = URL(string: play) {
                let thumbRaw = firstURLString(in: root, preferredKeys: ["cover", "originCover", "dynamicCover"])
                let thumb = thumbRaw.flatMap(URL.init(string:))
                let id = firstString(in: root, keys: ["id", "itemId", "aweme_id"]) ?? UUID().uuidString
                let author = firstString(in: root, keys: ["uniqueId", "nickname", "authorName"]) ?? "tiktok"
                let safeAuthor = sanitize(author)
                return [DownloadMedia(url: videoURL, filename: "\(safeAuthor)-\(id).mp4", type: "video", thumb: thumb)]
            }
        }

        // Last-resort extraction for pages that serialize playAddr as escaped JSON text.
        let patterns = [
            #"\"playAddr\"\s*:\s*\"([^\"]+)\""#,
            #"\"playAddrH264\"\s*:\s*\"([^\"]+)\""#
        ]
        for pattern in patterns {
            if let re = try? NSRegularExpression(pattern: pattern),
               let match = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: html) {
                var raw = String(html[r])
                raw = raw.replacingOccurrences(of: "\\u002F", with: "/")
                    .replacingOccurrences(of: "\\/", with: "/")
                    .replacingOccurrences(of: "\\u0026", with: "&")
                if let u = URL(string: raw) {
                    return [DownloadMedia(url: u, filename: "tiktok-video.mp4", type: "video", thumb: nil)]
                }
            }
        }

        throw AppError.message("تعذر استخراج فيديو TikTok مباشرة. قد يكون الفيديو خاصًا أو TikTok غيّر تنسيق الصفحة مؤقتًا.")
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

    private func discoverEngines() async throws -> [URL] {
        guard let listURL = URL(string: "https://instances.cobalt.best/api/instances.json") else { return [] }
        var req = URLRequest(url: listURL)
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let urls: [URL] = raw.compactMap { item in
            let value = (item["api"] as? String) ?? (item["url"] as? String)
            guard var s = value?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            if !s.hasPrefix("http") { s = "https://" + s }
            while s.hasSuffix("/") { s.removeLast() }
            guard let u = URL(string: s), u.host != "api.cobalt.tools" else { return nil }
            return u
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
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.badServerResponse) }
        let status = json["status"] as? String ?? ""
        switch status {
        case "redirect", "tunnel":
            guard let raw = json["url"] as? String, let u = URL(string: raw) else { return [] }
            let name = (json["filename"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return [DownloadMedia(url: u, filename: (name?.isEmpty == false ? name! : defaultFilename(for: u)), type: "video", thumb: nil)]
        case "picker":
            var items: [DownloadMedia] = []
            for (index, item) in (json["picker"] as? [[String: Any]] ?? []).enumerated() {
                guard let raw = item["url"] as? String, let u = URL(string: raw) else { continue }
                let kind = item["type"] as? String ?? "media"
                items.append(DownloadMedia(url: u, filename: "media-\(index + 1).\(fileExtension(kind: kind, url: u))", type: kind, thumb: (item["thumb"] as? String).flatMap(URL.init(string:))))
            }
            return items
        default:
            throw AppError.message("المحرك لم يستطع جلب هذا الرابط.")
        }
    }

    func download(_ item: DownloadMedia) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            var req = URLRequest(url: item.url)
            req.timeoutInterval = 60
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
            req.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
            let (temp, response) = try await URLSession.shared.download(for: req)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var filename = sanitize(item.filename)
            if (filename as NSString).pathExtension.isEmpty { filename += ".mp4" }
            var destination = folder.appendingPathComponent(filename)
            var n = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                let base = (filename as NSString).deletingPathExtension
                let ext = (filename as NSString).pathExtension
                destination = folder.appendingPathComponent("\(base)-\(n).\(ext)")
                n += 1
            }
            try FileManager.default.moveItem(at: temp, to: destination)
            downloaded.insert(destination, at: 0)
        } catch { self.error = readable(error) }
    }

    private func defaultFilename(for url: URL) -> String { url.lastPathComponent.isEmpty ? "video.mp4" : url.lastPathComponent }
    private func fileExtension(kind: String, url: URL) -> String { if !url.pathExtension.isEmpty { return url.pathExtension }; return kind == "photo" ? "jpg" : (kind == "gif" ? "gif" : "mp4") }
    private func sanitize(_ value: String) -> String { let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>"); let clean = value.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines); return clean.isEmpty ? "media" : String(clean.prefix(120)) }
    private func readable(_ error: Error) -> String { if let e = error as? AppError { return e.text }; if let u = error as? URLError { switch u.code { case .timedOut: return "انتهت مهلة الاتصال. حاول مرة أخرى."; case .notConnectedToInternet: return "لا يوجد اتصال بالإنترنت."; case .cannotFindHost, .dnsLookupFailed: return "تعذر الوصول إلى الخادم."; default: break } }; return error.localizedDescription }
}

enum AppError: Error { case message(String); var text: String { if case let .message(v) = self { return v }; return "خطأ" } }

struct ContentView: View {
    @StateObject private var model = AppModel()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 14) {
                        ZStack { RoundedRectangle(cornerRadius: 22).fill(.orange.gradient); Image(systemName: "arrow.down.to.line.compact").font(.system(size: 34, weight: .bold)).foregroundStyle(.white) }.frame(width: 78, height: 78)
                        VStack(alignment: .trailing, spacing: 5) { Text("حمّل").font(.largeTitle.bold()); Text("TikTok • Instagram • YouTube • Facebook").font(.caption).foregroundStyle(.secondary); Text("TikTok مباشر، وبقية المنصات عبر محرك متاح").foregroundStyle(.secondary) }
                        Spacer()
                    }.padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                    VStack(spacing: 12) {
                        HStack { TextField("الصق رابط المنشور هنا", text: $model.input).textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing); Button { if let text = UIPasteboard.general.string { model.input = text } } label: { Image(systemName: "doc.on.clipboard") } }.padding(14).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                        Button { Task { await model.resolve() } } label: { Label("جلب المحتوى", systemImage: "sparkle.magnifyingglass").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(.white).background(.orange.gradient, in: RoundedRectangle(cornerRadius: 17)) }.disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)
                        HStack { Circle().fill(model.activeEngine == "تعذر الجلب" ? .red : .green).frame(width: 8, height: 8); Text("المحرك: \(model.activeEngine)").font(.caption).foregroundStyle(.secondary); Spacer() }
                    }
                    if model.isLoading { ProgressView("جاري التنفيذ…").padding() }
                    if let error = model.error { HStack(alignment: .top, spacing: 10) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(error).font(.footnote).frame(maxWidth: .infinity, alignment: .trailing) }.padding(14).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16)) }
                    if !model.results.isEmpty {
                        VStack(alignment: .trailing, spacing: 10) {
                            Text("المحتوى المتاح").font(.headline).frame(maxWidth: .infinity, alignment: .trailing)
                            ForEach(model.results) { item in
                                HStack(spacing: 12) {
                                    Button { Task { await model.download(item) } } label: { Label("تنزيل", systemImage: "arrow.down.circle.fill") }.buttonStyle(.borderedProminent).tint(.orange)
                                    VStack(alignment: .trailing, spacing: 5) { Text(item.filename).font(.subheadline.bold()).lineLimit(2); Text(item.type.uppercased()).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .trailing)
                                    Group { if let thumb = item.thumb { AsyncImage(url: thumb) { image in image.resizable().scaledToFill() } placeholder: { ProgressView() } } else { ZStack { Color(.tertiarySystemGroupedBackground); Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(.orange) } } }.frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 16))
                                }.padding(12).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                            }
                        }
                    }
                    if !model.downloaded.isEmpty {
                        VStack(alignment: .trailing, spacing: 10) {
                            Text("تم التنزيل").font(.headline).frame(maxWidth: .infinity, alignment: .trailing)
                            ForEach(model.downloaded, id: \.self) { file in HStack { ShareLink(item: file) { Label("مشاركة", systemImage: "square.and.arrow.up") }; Spacer(); Text(file.lastPathComponent).font(.subheadline.bold()).lineLimit(1) }.padding(12).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18)) }
                        }
                    }
                }.padding()
            }.background(Color(.systemGroupedBackground)).navigationTitle("حمّل")
        }
    }
}
