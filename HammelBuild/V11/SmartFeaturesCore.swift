import Foundation
import SwiftUI
import LocalAuthentication
import UniformTypeIdentifiers

struct DownloadRuleSet: Codable, Equatable {
    var enabled = false
    var autoDownload = false
    var youtubeQuality = "1080p"
    var saveYouTubeToPhotos = false
    var saveTikTokToPhotos = false
    var watchCompress720 = false
    var watchCleanMetadata = true
}

struct DownloadHistoryRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let sourceURL: String
    let platform: String
    let quality: String
    let filename: String
    let savedPath: String
    let date: Date
}

enum SmartSharePreset: String, CaseIterable, Identifiable {
    case snapchat = "Snapchat"
    case whatsapp = "WhatsApp"
    case x = "X"
    var id: String { rawValue }
}

extension AppModel {
    var downloadRulesV3: DownloadRuleSet {
        get {
            guard let data = UserDefaults.standard.data(forKey: "downloadRulesV3"),
                  let value = try? JSONDecoder().decode(DownloadRuleSet.self, from: data) else { return DownloadRuleSet() }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: "downloadRulesV3") }
            objectWillChange.send()
        }
    }

    var downloadHistoryV3: [DownloadHistoryRecord] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "downloadHistoryV3"),
                  let value = try? JSONDecoder().decode([DownloadHistoryRecord].self, from: data) else { return [] }
            return value
        }
        set {
            let trimmed = Array(newValue.prefix(250))
            if let data = try? JSONEncoder().encode(trimmed) { UserDefaults.standard.set(data, forKey: "downloadHistoryV3") }
            objectWillChange.send()
        }
    }

    func recordDownloadHistoryV3(item: DownloadMedia, sourceURL: String, savedURL: URL) {
        guard !sourceURL.isEmpty else { return }
        var list = downloadHistoryV3
        let row = DownloadHistoryRecord(id: UUID(), sourceURL: sourceURL, platform: item.platform.rawValue, quality: item.quality, filename: savedURL.lastPathComponent, savedPath: savedURL.path, date: Date())
        list.removeAll { $0.sourceURL == sourceURL && $0.quality == item.quality && $0.filename == savedURL.lastPathComponent }
        list.insert(row, at: 0)
        downloadHistoryV3 = list
    }

    func clearHistoryV3() { downloadHistoryV3 = []; show("تم مسح سجل التنزيل", .success) }

    func bestMediaForRuleV3(_ media: [DownloadMedia], platform: PlatformKind) -> DownloadMedia? {
        guard !media.isEmpty else { return nil }
        let rules = downloadRulesV3
        if platform == .youtube {
            let target = qualityNumberV3(rules.youtubeQuality)
            let sorted = media.sorted { qualityNumberV3($0.quality) > qualityNumberV3($1.quality) }
            return sorted.first(where: { qualityNumberV3($0.quality) <= target && $0.hasAudio })
                ?? sorted.first(where: { qualityNumberV3($0.quality) <= target })
                ?? sorted.first
        }
        return media.first
    }

    func applyDownloadRulesIfNeededV3(source: URL) async {
        let rules = downloadRulesV3
        guard rules.enabled, rules.autoDownload, !results.isEmpty else { return }
        let platform = detect(source)
        guard let chosen = bestMediaForRuleV3(results, platform: platform) else { return }
        let target: SaveTarget = (platform == .youtube && rules.saveYouTubeToPhotos) || (platform == .tiktok && rules.saveTikTokToPhotos) ? .photos : .app
        await enqueueSmart(chosen, target: target)
    }

    private func qualityNumberV3(_ text: String) -> Int {
        let digits = text.filter(\.isNumber)
        return Int(digits) ?? 0
    }

    func redownloadHigherQualityV3(_ record: DownloadHistoryRecord) async {
        guard let source = URL(string: record.sourceURL) else { show("الرابط الأصلي غير صالح", .error); return }
        show("جارٍ البحث عن جودة أعلى…", .info)
        do {
            let media: [DownloadMedia]
            switch detect(source) {
            case .youtube: media = try await resolveYouTubeV2(source)
            case .tiktok: media = try await resolveTikTok(source)
            case .x: media = try await resolveX(source)
            case .instagram: media = try await resolveMeta(source, .instagram)
            case .facebook: media = try await resolveMeta(source, .facebook)
            case .generic: media = try await resolveMeta(source, .generic)
            }
            let old = qualityNumberV3(record.quality)
            let better = media.filter { qualityNumberV3($0.quality) > old }.sorted { qualityNumberV3($0.quality) > qualityNumberV3($1.quality) }.first
            guard let better else { show("لا توجد جودة أعلى متاحة", .info); return }
            input = record.sourceURL
            await enqueueSmart(better, target: .app)
        } catch { show(readable(error), .error) }
    }

    func vaultFolderV3() -> URL {
        let url = mediaFolder().appendingPathComponent("PrivateVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func vaultItemsV3() -> [LocalMedia] {
        let keys: Set<URLResourceKey> = [.creationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: vaultFolderV3(), includingPropertiesForKeys: Array(keys))) ?? []
        return urls.filter { !$0.hasDirectoryPath }.map {
            let v = try? $0.resourceValues(forKeys: keys)
            return LocalMedia(url: $0, createdAt: v?.creationDate ?? .distantPast, size: Int64(v?.fileSize ?? 0))
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func moveToVaultV3(_ item: LocalMedia) {
        let dst = uniqueDestinationV3(folder: vaultFolderV3(), filename: item.url.lastPathComponent)
        do { try FileManager.default.moveItem(at: item.url, to: dst); refreshStorage(); show("تم النقل إلى الخزنة", .success) }
        catch { show("تعذر النقل إلى الخزنة", .error) }
    }

    func restoreFromVaultV3(_ item: LocalMedia) {
        let dst = uniqueDestinationV3(folder: mediaFolder(), filename: item.url.lastPathComponent)
        do { try FileManager.default.moveItem(at: item.url, to: dst); refreshStorage(); show("تمت الاستعادة من الخزنة", .success) }
        catch { show("تعذر استعادة الملف", .error) }
    }

    func authenticateVaultV3() async -> Bool {
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) || context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "فتح خزنة مُحمّل") }
        catch { return false }
    }

    func watchFolderV3() -> URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Hammel Watch", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func addToWatchFolderV3(_ source: URL) {
        let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
        let dst = uniqueDestinationV3(folder: watchFolderV3(), filename: source.lastPathComponent)
        do { try FileManager.default.copyItem(at: source, to: dst); show("تمت الإضافة لمجلد المراقبة", .success); Task { await processWatchFolderV3() } }
        catch { show("تعذر إضافة الملف", .error) }
    }

    func processWatchFolderV3() async {
        let rules = downloadRulesV3
        let urls = (try? FileManager.default.contentsOfDirectory(at: watchFolderV3(), includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])) ?? []
        for url in urls where !url.hasDirectoryPath {
            let v = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let item = LocalMedia(url: url, createdAt: v?.creationDate ?? Date(), size: Int64(v?.fileSize ?? 0))
            do {
                var processedURL = url
                if item.isVideo && rules.watchCompress720 {
                    processedURL = try await exportPresetV3(item.url, preset: AVAssetExportPreset1280x720, suffix: "watch-720")
                } else {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString).\(item.ext)")
                    try FileManager.default.copyItem(at: url, to: tmp); processedURL = tmp
                }
                if rules.watchCleanMetadata && item.isVideo {
                    let clean = try await exportMetadataCleanV3(processedURL)
                    if processedURL != url { try? FileManager.default.removeItem(at: processedURL) }
                    processedURL = clean
                }
                _ = try persist(processedURL, url.lastPathComponent)
                try? FileManager.default.removeItem(at: url)
            } catch { continue }
        }
        refreshStorage()
    }

    private func exportPresetV3(_ source: URL, preset: String, suffix: String) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else { throw AppError.message("تعذر تجهيز المعالجة") }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(suffix).mp4")
        try? FileManager.default.removeItem(at: out); exporter.outputURL = out; exporter.outputFileType = .mp4
        await exporter.export(); guard exporter.status == .completed else { throw exporter.error ?? AppError.message("فشل التصدير") }
        return out
    }

    private func exportMetadataCleanV3(_ source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { throw AppError.message("تعذر تجهيز التنظيف") }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("clean-\(UUID().uuidString).mp4")
        exporter.metadata = []; exporter.outputURL = out; exporter.outputFileType = .mp4
        await exporter.export(); guard exporter.status == .completed else { throw exporter.error ?? AppError.message("فشل التنظيف") }
        return out
    }

    private func uniqueDestinationV3(folder: URL, filename: String) -> URL {
        var dst = folder.appendingPathComponent(filename); var n = 2
        let base = (filename as NSString).deletingPathExtension, ext = (filename as NSString).pathExtension
        while FileManager.default.fileExists(atPath: dst.path) {
            dst = folder.appendingPathComponent(ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"); n += 1
        }
        return dst
    }
}
