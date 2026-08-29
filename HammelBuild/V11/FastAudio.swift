import Foundation
import AVFoundation
import UIKit

extension AppModel {
    func separateCenterAudioFast(from item: LocalMedia, keepVoice: Bool) async {
        guard item.isVideo else { show("اختر فيديو", .info); return }
        let bgTask = beginHammelBackgroundTask(keepVoice ? "عزل الكلام" : "تقليل الصوت البشري")
        defer { endHammelBackgroundTask(bgTask) }

        do {
            notice = Notice(text: keepVoice ? "عزل الكلام…" : "تقليل الصوت البشري…", style: .info)
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-\(keepVoice ? "voice" : "no-voice").mp4")
            try? FileManager.default.removeItem(at: output)
            try await processStereoAudioFast(source: item.url, output: output, keepCenter: keepVoice)
            _ = try persist(output, output.lastPathComponent)
            refreshStorage()
            show(keepVoice ? "تم إنشاء نسخة تركّز على الكلام" : "تم إنشاء نسخة تقلل الصوت البشري", .success)
        } catch {
            show("تعذر فصل الصوت؛ النتيجة تعتمد على مكس الستيريو", .error)
        }
    }

    private func processStereoAudioFast(source: URL, output: URL, keepCenter: Bool) async throws {
        let asset = AVURLAsset(url: source)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
              let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.message("لا يوجد صوت أو فيديو")
        }

        // Process audio only. The original video track is reused untouched, which is much faster
        // than reading and rewriting every video sample.
        let audioTemp = FileManager.default.temporaryDirectory.appendingPathComponent("audio-center-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: audioTemp)

        let reader = try AVAssetReader(asset: asset)
        let audioOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(audioOut) else { throw AppError.message("تعذر قراءة الصوت") }
        reader.add(audioOut)

        let descriptions = try await audioTrack.load(.formatDescriptions)
        let asbd = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let rate = asbd?.mSampleRate ?? 44_100
        let channels = max(1, Int(asbd?.mChannelsPerFrame ?? 2))

        let writer = try AVAssetWriter(outputURL: audioTemp, fileType: .m4a)
        let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: min(2, channels),
            AVEncoderBitRateKey: 160_000
        ])
        audioIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioIn) else { throw AppError.message("تعذر تجهيز الصوت") }
        writer.add(audioIn)
        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? AppError.message("تعذر بدء المعالجة")
        }
        writer.startSession(atSourceTime: .zero)

        while let sample = audioOut.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); writer.cancelWriting(); throw CancellationError() }
            if channels >= 2, let block = CMSampleBufferGetDataBuffer(sample) {
                var lengthAtOffset = 0
                var totalLength = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                if CMBlockBufferGetDataPointer(block,
                                               atOffset: 0,
                                               lengthAtOffsetOut: &lengthAtOffset,
                                               totalLengthOut: &totalLength,
                                               dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
                   let raw = dataPointer {
                    let samples = raw.withMemoryRebound(to: Int16.self, capacity: totalLength / 2) { $0 }
                    let count = totalLength / 2
                    var i = 0
                    while i + 1 < count {
                        let l = Int32(samples[i])
                        let r = Int32(samples[i + 1])
                        if keepCenter {
                            let center = clampAudio((l + r) / 2)
                            samples[i] = center
                            samples[i + 1] = center
                        } else {
                            let side = clampAudio((l - r) / 2)
                            samples[i] = side
                            samples[i + 1] = clampAudio(-Int32(side))
                        }
                        i += channels
                    }
                }
            }

            while !audioIn.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(1))
            }
            guard audioIn.append(sample) else { throw writer.error ?? AppError.message("تعذر كتابة الصوت") }
        }

        audioIn.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? AppError.message("فشل تجهيز الصوت") }

        let processed = AVURLAsset(url: audioTemp)
        guard let processedAudio = try await processed.loadTracks(withMediaType: .audio).first else {
            throw AppError.message("تعذر قراءة الصوت الناتج")
        }

        let composition = AVMutableComposition()
        let videoDuration = try await asset.load(.duration)
        guard let dstV = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let dstA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AppError.message("تعذر تجهيز النتيجة")
        }
        try dstV.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        dstV.preferredTransform = try await videoTrack.load(.preferredTransform)
        let audioDuration = try await processed.load(.duration)
        try dstA.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(videoDuration, audioDuration)), of: processedAudio, at: .zero)

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw AppError.message("تعذر تجهيز النتيجة")
        }
        try? FileManager.default.removeItem(at: output)
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        await exporter.export()
        try? FileManager.default.removeItem(at: audioTemp)
        guard exporter.status == .completed else { throw exporter.error ?? AppError.message("فشل إنشاء الفيديو") }
    }

    private func clampAudio(_ value: Int32) -> Int16 {
        Int16(max(Int32(Int16.min), min(Int32(Int16.max), value)))
    }
}
