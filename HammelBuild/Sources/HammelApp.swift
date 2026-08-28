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
    @Published var activeEngine = "تلقائي"

    func resolve() async {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = URL(string: value), source.scheme?.hasPrefix("http") == true else {
            error = "الصق رابطًا صحيحًا من TikTok أو Instagram أو YouTube أو Facebook."
            return
        }
        isLoading = true; error = nil; results = []; activeEngine = "جاري اختيار المحرك…"
        defer { isLoading = false }
        do {
            let engines = try await discoverEngines()
            guard !engines.isEmpty else { throw AppError.message("لم أجد محرك تنزيل متاحًا الآن.") }
            var lastError: Error = AppError.message("تعذر جلب المحتوى.")
            for engine in engines.prefix(10) {
                do {
                    let media = try await resolve(source: source, engine: engine)
                    if !media.isEmpty {
                        activeEngine = engine.host ?? "محرك متاح"
                        results = media
                        return
                    }
                } catch { lastError = error }
            }
            throw lastError
        } catch { self.error = readable(error); activeEngine = "غير متصل" }
    }

    private func discoverEngines() async throws -> [URL] {
        guard let listURL = URL(string: "https://instances.cobalt.best/api/instances.json") else { return [] }
        var req = URLRequest(url: listURL); req.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        let urls: [URL] = raw.compactMap { item in
            if let online = item["online"] as? [String: Any], (online["api"] as? Bool) == false { return nil }
            let value = (item["api"] as? String) ?? (item["url"] as? String) ?? (item["protocol"] as? String)
            guard var s = value?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            if !s.hasPrefix("http") { s = "https://" + s }
            while s.hasSuffix("/") { s.removeLast() }
            guard let u = URL(string: s), u.host != "api.cobalt.tools" else { return nil }
            return u
        }
        return Array(NSOrderedSet(array: urls).array.compactMap { $0 as? URL }).shuffled()
    }

    private func resolve(source: URL, engine: URL) async throws -> [DownloadMedia] {
        var request = URLRequest(url: engine)
        request.httpMethod = "POST"; request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "url": source.absoluteString,
            "videoQuality": "1080",
            "downloadMode": "auto",
            "youtubeVideoCodec": "h264",
            "filenameStyle": "pretty",
            "tiktokFullAudio": false,
            "tiktokH265": false,
            "alwaysProxy": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
        let status = json["status"] as? String ?? ""
        switch status {
        case "redirect", "tunnel":
            guard let raw = json["url"] as? String, let u = URL(string: raw) else { throw AppError.message("لم يصل رابط التنزيل.") }
            let name = (json["filename"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return [DownloadMedia(url: u, filename: (name?.isEmpty == false ? name! : defaultFilename(for: u)), type: "video", thumb: nil)]
        case "picker":
            var items: [DownloadMedia] = []
            let picker = json["picker"] as? [[String: Any]] ?? []
            for (index, item) in picker.enumerated() {
                guard let raw = item["url"] as? String, let u = URL(string: raw) else { continue }
                let kind = item["type"] as? String ?? "media"
                let thumb = (item["thumb"] as? String).flatMap(URL.init(string:))
                items.append(DownloadMedia(url: u, filename: "media-\(index + 1).\(fileExtension(kind: kind, url: u))", type: kind, thumb: thumb))
            }
            if let a = json["audio"] as? String, let u = URL(string: a) { items.append(DownloadMedia(url: u, filename: (json["audioFilename"] as? String) ?? "audio.mp3", type: "audio", thumb: nil)) }
            return items
        case "error":
            let code = (json["error"] as? [String: Any])?["code"] as? String ?? "خطأ من محرك الجلب"
            throw AppError.message(code)
        default: throw AppError.message("استجابة غير معروفة من المحرك.")
        }
    }

    func download(_ item: DownloadMedia) async {
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            let (temp, response) = try await URLSession.shared.download(from: item.url)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var filename = sanitize(item.filename)
            if (filename as NSString).pathExtension.isEmpty { filename += "." + (item.url.pathExtension.isEmpty ? "mp4" : item.url.pathExtension) }
            var destination = folder.appendingPathComponent(filename); var n = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                let base = (filename as NSString).deletingPathExtension, ext = (filename as NSString).pathExtension
                destination = folder.appendingPathComponent("\(base)-\(n)\(ext.isEmpty ? "" : ".\(ext)")"); n += 1
            }
            try FileManager.default.moveItem(at: temp, to: destination); downloaded.insert(destination, at: 0)
        } catch { self.error = readable(error) }
    }

    private func defaultFilename(for url: URL) -> String { url.lastPathComponent.isEmpty ? "video.mp4" : url.lastPathComponent }
    private func fileExtension(kind: String, url: URL) -> String { if !url.pathExtension.isEmpty { return url.pathExtension }; return kind == "photo" ? "jpg" : (kind == "gif" ? "gif" : "mp4") }
    private func sanitize(_ value: String) -> String { let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>"); let clean = value.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines); return clean.isEmpty ? "media" : String(clean.prefix(120)) }
    private func readable(_ error: Error) -> String { if let e = error as? AppError { return e.text }; if let u = error as? URLError { if u.code == .timedOut { return "المحركات المتاحة لم تستجب. حاول مرة أخرى." }; if u.code == .notConnectedToInternet { return "لا يوجد اتصال بالإنترنت." } }; return error.localizedDescription }
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
                        VStack(alignment: .trailing, spacing: 5) { Text("حمّل").font(.largeTitle.bold()); Text("TikTok • Instagram • YouTube • Facebook").font(.caption).foregroundStyle(.secondary); Text("الصق الرابط وخذ الوسائط المتاحة من المصدر").foregroundStyle(.secondary) }
                        Spacer()
                    }.padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                    VStack(spacing: 12) {
                        HStack { TextField("الصق رابط المنشور هنا", text: $model.input).textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing); Button { if let text = UIPasteboard.general.string { model.input = text } } label: { Image(systemName: "doc.on.clipboard") } }.padding(14).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                        Button { Task { await model.resolve() } } label: { Label("جلب المحتوى", systemImage: "sparkle.magnifyingglass").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(.white).background(.orange.gradient, in: RoundedRectangle(cornerRadius: 17)) }.disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)
                        HStack { Circle().fill(model.activeEngine == "غير متصل" ? .red : .green).frame(width: 8, height: 8); Text("المحرك: \(model.activeEngine)").font(.caption).foregroundStyle(.secondary); Spacer() }
                    }
                    if model.isLoading { ProgressView("جاري التنفيذ…").padding() }
                    if let error = model.error { HStack(alignment: .top, spacing: 10) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(error).font(.footnote).frame(maxWidth: .infinity, alignment: .trailing) }.padding(14).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16)) }
                    if !model.results.isEmpty {
                        VStack(alignment: .trailing, spacing: 10) {
                            Text("المحتوى المتاح").font(.headline).frame(maxWidth: .infinity, alignment: .trailing)
                            ForEach(model.results) { item in HStack(spacing: 12) { Button { Task { await model.download(item) } } label: { Label("تنزيل", systemImage: "arrow.down.circle.fill") }.buttonStyle(.borderedProminent).tint(.orange); VStack(alignment: .trailing, spacing: 5) { Text(item.filename).font(.subheadline.bold()).lineLimit(2); Text(item.type.uppercased()).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .trailing); Group { if let thumb = item.thumb { AsyncImage(url: thumb) { image in image.resizable().scaledToFill() } placeholder: { ProgressView() } } else { ZStack { Color(.tertiarySystemGroupedBackground); Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(.orange) } } }.frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 16)) }.padding(12).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20)) }
                        }
                    }
                    if !model.downloaded.isEmpty {
                        VStack(alignment: .trailing, spacing: 10) { Text("تم التنزيل").font(.headline).frame(maxWidth: .infinity, alignment: .trailing); ForEach(model.downloaded, id: \.self) { file in HStack { ShareLink(item: file) { Label("مشاركة", systemImage: "square.and.arrow.up") }; Spacer(); Text(file.lastPathComponent).font(.subheadline.bold()).lineLimit(1) }.padding(12).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18)) } }
                    }
                }.padding()
            }.background(Color(.systemGroupedBackground)).navigationTitle("حمّل")
        }
    }
}
