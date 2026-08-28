import SwiftUI
import Foundation
import UIKit

@main
struct HammelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.layoutDirection, .rightToLeft)
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
    @Published var apiURL = UserDefaults.standard.string(forKey: "apiURL") ?? "https://api.cobalt.tools"
    @Published var apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""

    func resolve() async {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = URL(string: value), let scheme = source.scheme, scheme.hasPrefix("http") else {
            error = "الصق رابطًا صحيحًا من TikTok أو Instagram أو YouTube أو Facebook."
            return
        }

        isLoading = true
        error = nil
        results = []
        defer { isLoading = false }

        do {
            var base = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
            while base.hasSuffix("/") { base.removeLast() }
            guard let endpoint = URL(string: base) else { throw URLError(.badURL) }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 45
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty {
                request.setValue("Api-Key \(apiKey)", forHTTPHeaderField: "Authorization")
            }
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
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw NSError(domain: "Hammel", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: text])
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "Hammel", code: 1, userInfo: [NSLocalizedDescriptionKey: "استجابة غير مفهومة من محرك الجلب."])
            }
            let status = json["status"] as? String ?? ""
            switch status {
            case "redirect", "tunnel":
                guard let raw = json["url"] as? String, let mediaURL = URL(string: raw) else {
                    throw NSError(domain: "Hammel", code: 2, userInfo: [NSLocalizedDescriptionKey: "لم يصل رابط التنزيل من المحرك."])
                }
                let name = (json["filename"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                results = [DownloadMedia(url: mediaURL, filename: (name?.isEmpty == false ? name! : defaultFilename(for: mediaURL)), type: "video", thumb: nil)]

            case "picker":
                let picker = json["picker"] as? [[String: Any]] ?? []
                results = picker.enumerated().compactMap { index, item in
                    guard let raw = item["url"] as? String, let mediaURL = URL(string: raw) else { return nil }
                    let kind = item["type"] as? String ?? "media"
                    let thumb = (item["thumb"] as? String).flatMap(URL.init(string:))
                    return DownloadMedia(url: mediaURL, filename: "media-\(index + 1).\(fileExtension(kind: kind, url: mediaURL))", type: kind, thumb: thumb)
                }
                if let audioRaw = json["audio"] as? String, let audioURL = URL(string: audioRaw) {
                    let audioName = (json["audioFilename"] as? String) ?? "audio.mp3"
                    results.append(DownloadMedia(url: audioURL, filename: audioName, type: "audio", thumb: nil))
                }
                if results.isEmpty {
                    throw NSError(domain: "Hammel", code: 3, userInfo: [NSLocalizedDescriptionKey: "لم أجد وسائط قابلة للتنزيل في هذا الرابط."])
                }

            case "error":
                let err = json["error"] as? [String: Any]
                let code = err?["code"] as? String ?? "حدث خطأ من محرك الجلب"
                throw NSError(domain: "Hammel", code: 4, userInfo: [NSLocalizedDescriptionKey: code])

            default:
                throw NSError(domain: "Hammel", code: 5, userInfo: [NSLocalizedDescriptionKey: "حالة غير معروفة من محرك الجلب: \(status)"])
            }
        } catch {
            self.error = readable(error)
        }
    }

    func download(_ item: DownloadMedia) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let (temp, response) = try await URLSession.shared.download(from: item.url)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Hammel", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var filename = sanitize(item.filename)
            if (filename as NSString).pathExtension.isEmpty {
                let ext = item.url.pathExtension.isEmpty ? "mp4" : item.url.pathExtension
                filename += ".\(ext)"
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

    func saveSettings() {
        UserDefaults.standard.set(apiURL, forKey: "apiURL")
        UserDefaults.standard.set(apiKey, forKey: "apiKey")
    }

    private func defaultFilename(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? "video.mp4" : name
    }

    private func fileExtension(kind: String, url: URL) -> String {
        if !url.pathExtension.isEmpty { return url.pathExtension }
        switch kind { case "photo": return "jpg"; case "gif": return "gif"; default: return "mp4" }
    }

    private func sanitize(_ value: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let clean = value.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "media" : String(clean.prefix(120))
    }

    private func readable(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "انتهت مهلة الاتصال بمحرك الجلب. حاول مرة ثانية."
            case .notConnectedToInternet: return "لا يوجد اتصال بالإنترنت."
            default: break
            }
        }
        return error.localizedDescription
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    inputCard
                    if model.isLoading { ProgressView("جاري التنفيذ…").padding() }
                    if let error = model.error { errorCard(error) }
                    if !model.results.isEmpty { resultSection }
                    if !model.downloaded.isEmpty { downloadsSection }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("حمّل")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsSheet(model: model) }
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
                Text("TikTok • Instagram • YouTube • Facebook").font(.caption).foregroundStyle(.secondary)
                Text("الصق الرابط وخذ الوسائط المتاحة من المصدر").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private var inputCard: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("الصق رابط المنشور هنا", text: $model.input)
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
        }
    }

    private var resultSection: some View {
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
                            ZStack { Color(.tertiarySystemGroupedBackground); Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(.orange) }
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

struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("محرك الجلب") {
                    TextField("https://api.example.com", text: $model.apiURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.leading)
                    SecureField("API Key — اختياري", text: $model.apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("للاختبار وضعت api.cobalt.tools افتراضيًا. إذا كان السيرفر يطلب حماية أو مفتاحًا، استخدم Instance خاص بك.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("حول") {
                    LabeledContent("الإصدار", value: "0.3 Test")
                    Text("التطبيق يطلب الملف من المصدر المتاح ولا يضيف علامة مائية من عنده.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("الإعدادات")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { model.saveSettings(); dismiss() }
                }
            }
        }
    }
}
