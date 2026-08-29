import Foundation
import AVFoundation

@MainActor
final class YTCompanionStore {
    static let shared = YTCompanionStore()
    private var audioByVideo: [String: URL] = [:]
    func setAudio(_ audio: URL, for video: URL) { audioByVideo[video.absoluteString] = audio }
    func audio(for video: URL) -> URL? { audioByVideo[video.absoluteString] }
}

extension AppModel {
    func enqueueSmart(_ item: DownloadMedia, filename: String? = nil, target: SaveTarget? = nil) async {
        guard let audioURL = YTCompanionStore.shared.audio(for: item.url) else {
            await enqueue(item, filename: filename, target: target)
            return
        }

        let chosen = target ?? saveTarget
        guard chosen != .ask else { return }
        let job = DownloadJob(item: item)
        jobs.insert(job, at: 0)
        let jobID = job.id
        smartJob(jobID, .downloading, 0.05)

        do {
            let videoTmp = try await smartDownload(item.url, referer: item.referer)
            smartJob(jobID, .downloading, 0.42)
            let audioTmp = try await smartDownload(audioURL, referer: "https://www.youtube.com/")
            smartJob(jobID, .downloading, 0.72)

            let desired = filename?.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = (desired?.isEmpty == false ? desired! : (item.filename as NSString).deletingPathExtension)
            let mergedTmp = FileManager.default.temporaryDirectory.appendingPathComponent("mux-\(UUID().uuidString).mp4")
            try await mux(video: videoTmp, audio: audioTmp, output: mergedTmp)
            smartJob(jobID, .downloading, 0.94)
            let saved = try persist(mergedTmp, "\(base).mp4")
            try? FileManager.default.removeItem(at: videoTmp)
            try? FileManager.default.removeItem(at: audioTmp)
            if chosen == .photos { await saveExistingToPhotos(saved) }
            smartJob(jobID, .done, 1)
            refreshStorage()
            show(chosen == .photos ? "تم تنزيل الجودة العالية وحفظها في الصور" : "تم تنزيل الجودة العالية", .success)
        } catch {
            smartJob(jobID, .failed, 0, readable(error))
            show("تعذر دمج الجودة العالية، جرّب جودة أخرى", .error)
        }
    }

    private func smartJob(_ id: UUID, _ state: DownloadState, _ progress: Double, _ error: String? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = state; jobs[index].progress = progress; jobs[index].error = error
    }

    private func smartDownload(_ url: URL, referer: String?) async throws -> URL {
        var req = URLRequest(url: url); req.timeoutInterval = 240
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
        let (tmp, response) = try await URLSession.shared.download(for: req)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("part-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.moveItem(at: tmp, to: dst)
        return dst
    }

    private func mux(video: URL, audio: URL, output: URL) async throws {
        let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audio)
        let composition = AVMutableComposition()
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AppError.message("تعذر قراءة مسار الفيديو") }
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
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw AppError.message("تعذر تجهيز الدمج") }
        exporter.outputURL = output; exporter.outputFileType = .mp4
        await exporter.export()
        guard exporter.status == .completed else { throw exporter.error ?? AppError.message("فشل دمج الصوت والفيديو") }
    }
}
