import Foundation
import AVFoundation

@MainActor
final class YTCompanionStore {
    static let shared = YTCompanionStore()
    private var audioByVideo: [String: URL] = [:]
    func setAudio(_ audio: URL, for video: URL) { audioByVideo[video.absoluteString] = audio }
    func audio(for video: URL) -> URL? { audioByVideo[video.absoluteString] }
}

private final class ProgressFileDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private let progress: (Double) -> Void
    private var session: URLSession?

    init(progress: @escaping (Double) -> Void) {
        self.progress = progress
        super.init()
    }

    func download(_ request: URLRequest) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = request.timeoutInterval
            configuration.timeoutIntervalForResource = max(request.timeoutInterval, 300)
            configuration.httpMaximumConnectionsPerHost = 8
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let ext = downloadTask.response?.suggestedFilename.flatMap { ($0 as NSString).pathExtension }.flatMap { $0.isEmpty ? nil : $0 } ?? "part"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("download-\(UUID().uuidString).\(ext)")
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
            continuation = nil
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
        session.finishTasksAndInvalidate()
        self.session = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, continuation != nil {
            continuation?.resume(throwing: error)
            continuation = nil
            session.invalidateAndCancel()
            self.session = nil
        }
    }
}

extension AppModel {
    func enqueueSmart(_ item: DownloadMedia, filename: String? = nil, target: SaveTarget? = nil) async {
        if jobs.contains(where: { $0.item.url == item.url && ($0.state == .downloading || $0.state == .waiting) }) {
            notice = Notice(text: "هذا الملف قيد التحميل بالفعل", style: .info)
            return
        }

        let chosen = target ?? saveTarget
        guard chosen != .ask else { return }
        let job = DownloadJob(item: item)
        jobs.insert(job, at: 0)
        let jobID = job.id
        smartJob(jobID, .downloading, 0.01)

        do {
            if let audioURL = YTCompanionStore.shared.audio(for: item.url) {
                var lastShown = -1
                let videoTmp = try await smartDownload(item.url, referer: item.referer) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self else { return }
                        let overall = 0.02 + fraction * 0.48
                        self.smartJob(jobID, .downloading, overall)
                        let pct = Int(overall * 100)
                        if pct >= lastShown + 3 { lastShown = pct; self.notice = Notice(text: "تنزيل الفيديو… \(pct)%", style: .info) }
                    }
                }

                lastShown = 49
                let audioTmp = try await smartDownload(audioURL, referer: "https://www.youtube.com/") { [weak self] fraction in
                    Task { @MainActor in
                        guard let self else { return }
                        let overall = 0.50 + fraction * 0.27
                        self.smartJob(jobID, .downloading, overall)
                        let pct = Int(overall * 100)
                        if pct >= lastShown + 3 { lastShown = pct; self.notice = Notice(text: "تنزيل الصوت… \(pct)%", style: .info) }
                    }
                }

                smartJob(jobID, .downloading, 0.80)
                notice = Notice(text: "جاري دمج الصوت مع الفيديو… 80%", style: .info)
                let desired = filename?.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = (desired?.isEmpty == false ? desired! : (item.filename as NSString).deletingPathExtension)
                let mergedTmp = FileManager.default.temporaryDirectory.appendingPathComponent("mux-\(UUID().uuidString).mp4")
                try await mux(video: videoTmp, audio: audioTmp, output: mergedTmp)
                smartJob(jobID, .downloading, 0.96)
                notice = Notice(text: "إنهاء الملف… 96%", style: .info)
                let saved = try persist(mergedTmp, "\(base).mp4")
                try? FileManager.default.removeItem(at: videoTmp)
                try? FileManager.default.removeItem(at: audioTmp)
                if chosen == .photos { await saveExistingToPhotos(saved) }
            } else {
                var lastShown = -1
                let tmp = try await smartDownload(item.url, referer: item.referer) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self else { return }
                        let overall = 0.02 + fraction * 0.94
                        self.smartJob(jobID, .downloading, overall)
                        let pct = Int(overall * 100)
                        if pct >= lastShown + 3 { lastShown = pct; self.notice = Notice(text: "جاري التحميل… \(pct)%", style: .info) }
                    }
                }
                let desired = filename?.trimmingCharacters(in: .whitespacesAndNewlines)
                let final = applyingExtension(from: item.filename, to: (desired?.isEmpty == false ? desired! : item.filename))
                let saved = try persist(tmp, final)
                if chosen == .photos { await saveExistingToPhotos(saved) }
            }

            smartJob(jobID, .done, 1)
            refreshStorage()
            show(chosen == .photos ? "تم التنزيل والحفظ في الصور" : "تم التنزيل", .success)
        } catch {
            smartJob(jobID, .failed, 0, readable(error))
            show(YTCompanionStore.shared.audio(for: item.url) != nil ? "تعذر دمج الجودة العالية، جرّب جودة أخرى" : "تعذر إكمال التحميل", .error)
        }
    }

    private func smartJob(_ id: UUID, _ state: DownloadState, _ progress: Double, _ error: String? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = state
        jobs[index].progress = progress
        jobs[index].error = error
    }

    private func smartDownload(_ url: URL, referer: String?, progress: @escaping (Double) -> Void) async throws -> URL {
        if (url.host ?? "").contains("googlevideo.com"), let accelerated = try? await parallelSmallDownload(url, referer: referer, progress: progress) {
            return accelerated
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 180
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
        let downloader = ProgressFileDownloader(progress: progress)
        return try await downloader.download(req)
    }

    private func parallelSmallDownload(_ url: URL, referer: String?, progress: @escaping (Double) -> Void) async throws -> URL {
        var probe = URLRequest(url: url)
        probe.timeoutInterval = 20
        probe.setValue(ua, forHTTPHeaderField: "User-Agent")
        probe.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        probe.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let referer { probe.setValue(referer, forHTTPHeaderField: "Referer") }
        let (_, probeResponse) = try await URLSession.shared.data(for: probe)
        guard let http = probeResponse as? HTTPURLResponse,
              http.statusCode == 206,
              let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
              let slash = contentRange.lastIndex(of: "/"),
              let total = Int64(contentRange[contentRange.index(after: slash)...]),
              total >= 1_000_000,
              total <= 80_000_000 else { throw URLError(.cannotParseResponse) }

        let parts = total < 8_000_000 ? 3 : 4
        let chunk = Int64(ceil(Double(total) / Double(parts)))
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 180
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)

        var results = Array<Data?>(repeating: nil, count: parts)
        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for index in 0..<parts {
                let start = Int64(index) * chunk
                let end = min(total - 1, start + chunk - 1)
                group.addTask {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 90
                    req.setValue(self.ua, forHTTPHeaderField: "User-Agent")
                    req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                    req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                    if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
                    let (data, response) = try await session.data(for: req)
                    guard let h = response as? HTTPURLResponse, h.statusCode == 206 else { throw URLError(.badServerResponse) }
                    return (index, data)
                }
            }
            var completed = 0
            for try await (index, data) in group {
                results[index] = data
                completed += 1
                progress(Double(completed) / Double(parts))
            }
        }
        session.invalidateAndCancel()

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fast-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmp)
        defer { try? handle.close() }
        for data in results {
            guard let data else { throw URLError(.cannotDecodeContentData) }
            try handle.write(contentsOf: data)
        }
        progress(1)
        return tmp
    }

    private func mux(video: URL, audio: URL, output: URL) async throws {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        let composition = AVMutableComposition()
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AppError.message("تعذر قراءة مسار الفيديو")
        }
        let vDuration = try await videoAsset.load(.duration)
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: vDuration), of: sourceVideo, at: .zero)
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)

        if let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let aDuration = try await audioAsset.load(.duration)
            let duration = CMTimeMinimum(vDuration, aDuration)
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceAudio, at: .zero)
        }

        try? FileManager.default.removeItem(at: output)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw AppError.message("تعذر تجهيز الدمج")
        }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        await exporter.export()
        guard exporter.status == .completed else {
            throw exporter.error ?? AppError.message("فشل دمج الصوت والفيديو")
        }
    }
}
