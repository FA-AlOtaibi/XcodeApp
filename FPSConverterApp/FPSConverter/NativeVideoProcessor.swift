import AVFoundation
import CoreImage
import Foundation

final class NativeVideoProcessor {
    enum MotionMode { case fast, smooth }
    enum OutputQuality { case enhanced, twoK, fourK }
    enum ProcessorError: LocalizedError {
        case noVideo, reader, writer, export
        var errorDescription: String? {
            switch self {
            case .noVideo: return "No readable video track was found."
            case .reader: return "The source video could not be decoded."
            case .writer: return "The processed video could not be encoded."
            case .export: return "The final video could not be finalized."
            }
        }
    }

    private let context = CIContext(options: [.cacheIntermediates: false])

    func process(sourceURL: URL,
                 targetFPS: Int,
                 quality: OutputQuality,
                 mode: MotionMode,
                 progress: @escaping @Sendable (Double, String) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ProcessorError.noVideo }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let oriented = natural.applying(transform)
        let displaySize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let targetSize = outputSize(from: displaySize, quality: quality)

        let temp = FileManager.default.temporaryDirectory
        let videoOnly = temp.appendingPathComponent("native_video_\(UUID().uuidString).mp4")
        let finalURL = temp.appendingPathComponent("ScreenFlow_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: videoOnly)
        try? FileManager.default.removeItem(at: finalURL)

        progress(0.02, "Preparing video")
        var lastError: Error?
        for codec in codecPreference(for: quality, fps: targetFPS) {
            do {
                try await encodeVideo(asset: asset, track: track, transform: transform,
                                      targetSize: targetSize, targetFPS: targetFPS,
                                      mode: mode, codec: codec, outputURL: videoOnly,
                                      progress: progress)
                lastError = nil
                break
            } catch {
                lastError = error
                try? FileManager.default.removeItem(at: videoOnly)
            }
        }
        if let lastError { throw lastError }

        progress(0.93, "Restoring audio")
        do {
            try await attachAudio(processedVideo: videoOnly, original: asset, outputURL: finalURL)
            try? FileManager.default.removeItem(at: videoOnly)
            progress(1, "Done")
            return finalURL
        } catch {
            try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.moveItem(at: videoOnly, to: finalURL)
            progress(1, "Done")
            return finalURL
        }
    }

    private func codecPreference(for quality: OutputQuality, fps: Int) -> [AVVideoCodecType] {
        if quality == .fourK || fps >= 120 { return [.hevc, .h264] }
        return [.h264, .hevc]
    }

    private func outputSize(from source: CGSize, quality: OutputQuality) -> CGSize {
        let sourceLong = max(source.width, source.height)
        let targetLong: CGFloat
        switch quality {
        case .enhanced: targetLong = sourceLong
        case .twoK: targetLong = max(sourceLong, 2560)
        case .fourK: targetLong = max(sourceLong, 3840)
        }
        let scale = targetLong / max(1, sourceLong)
        return CGSize(width: even(source.width * scale), height: even(source.height * scale))
    }

    private func even(_ value: CGFloat) -> CGFloat {
        CGFloat(max(2, Int(value.rounded()) / 2 * 2))
    }

    private func encodeVideo(asset: AVAsset,
                             track: AVAssetTrack,
                             transform: CGAffineTransform,
                             targetSize: CGSize,
                             targetFPS: Int,
                             mode: MotionMode,
                             codec: AVVideoCodecType,
                             outputURL: URL,
                             progress: @escaping @Sendable (Double, String) -> Void) async throws {
        let duration = try await asset.load(.duration)
        let seconds = max(0.001, CMTimeGetSeconds(duration))
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw ProcessorError.reader }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let bitrate = bitrateFor(size: targetSize, fps: targetFPS, codec: codec)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: targetFPS,
            AVVideoMaxKeyFrameIntervalKey: max(targetFPS * 2, 60)
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(targetSize.width),
            AVVideoHeightKey: Int(targetSize.height),
            AVVideoCompressionPropertiesKey: compression
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(targetSize.width),
            kCVPixelBufferHeightKey as String: Int(targetSize.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw ProcessorError.writer }
        writer.add(input)
        guard reader.startReading(), writer.startWriting() else { throw ProcessorError.writer }
        writer.startSession(atSourceTime: .zero)

        guard let first = readerOutput.copyNextSampleBuffer() else { throw ProcessorError.reader }
        var previous = first
        var current = readerOutput.copyNextSampleBuffer()
        var nextOutputSeconds = 0.0
        let step = 1.0 / Double(max(1, targetFPS))

        while let next = current {
            guard let prevBuffer = CMSampleBufferGetImageBuffer(previous),
                  let nextBuffer = CMSampleBufferGetImageBuffer(next) else { throw ProcessorError.reader }
            let prevTime = max(0, CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(previous)))
            let nextTime = max(prevTime + 0.0001, CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(next)))

            while nextOutputSeconds <= nextTime + 0.00001 {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 1_000_000)
                    if writer.status == .failed { throw writer.error ?? ProcessorError.writer }
                }
                let alpha = min(1, max(0, (nextOutputSeconds - prevTime) / max(0.0001, nextTime - prevTime)))
                let image: CIImage
                if mode == .smooth && alpha > 0 && alpha < 1 {
                    image = blendedImage(a: prevBuffer, b: nextBuffer, alpha: alpha, transform: transform)
                } else {
                    image = orientedImage(from: alpha < 0.5 ? prevBuffer : nextBuffer, transform: transform)
                }
                guard let pool = adaptor.pixelBufferPool else { throw ProcessorError.writer }
                var out: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
                guard let pixel = out else { throw ProcessorError.writer }
                let processed = enhancedAndScaled(image, targetSize: targetSize)
                context.render(processed, to: pixel, bounds: CGRect(origin: .zero, size: targetSize), colorSpace: CGColorSpaceCreateDeviceRGB())
                let pts = CMTime(seconds: nextOutputSeconds, preferredTimescale: 60000)
                guard adaptor.append(pixel, withPresentationTime: pts) else { throw writer.error ?? ProcessorError.writer }
                nextOutputSeconds += step
                let p = min(0.90, 0.05 + (nextOutputSeconds / seconds) * 0.85)
                progress(p, mode == .smooth ? "Creating smooth motion" : "Converting frame rate")
            }
            previous = next
            current = readerOutput.copyNextSampleBuffer()
        }

        if let lastBuffer = CMSampleBufferGetImageBuffer(previous) {
            while nextOutputSeconds < seconds {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                guard let pool = adaptor.pixelBufferPool else { throw ProcessorError.writer }
                var out: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
                guard let pixel = out else { throw ProcessorError.writer }
                let processed = enhancedAndScaled(orientedImage(from: lastBuffer, transform: transform), targetSize: targetSize)
                context.render(processed, to: pixel, bounds: CGRect(origin: .zero, size: targetSize), colorSpace: CGColorSpaceCreateDeviceRGB())
                guard adaptor.append(pixel, withPresentationTime: CMTime(seconds: nextOutputSeconds, preferredTimescale: 60000)) else { throw writer.error ?? ProcessorError.writer }
                nextOutputSeconds += step
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ProcessorError.writer }
    }

    private func bitrateFor(size: CGSize, fps: Int, codec: AVVideoCodecType) -> Int {
        let pixels = max(1, size.width * size.height)
        let ratio = pixels / (1920 * 1080)
        let fpsRatio = max(1, Double(fps) / 30.0)
        var mbps = 16.0 * ratio * sqrt(fpsRatio)
        if codec == .hevc { mbps *= 0.80 }
        mbps = min(160, max(12, mbps))
        return Int(mbps * 1_000_000)
    }

    private func orientedImage(from buffer: CVPixelBuffer, transform: CGAffineTransform) -> CIImage {
        let transformed = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
        let e = transformed.extent
        return transformed.transformed(by: CGAffineTransform(translationX: -e.origin.x, y: -e.origin.y))
    }

    private func blendedImage(a: CVPixelBuffer, b: CVPixelBuffer, alpha: Double, transform: CGAffineTransform) -> CIImage {
        let background = orientedImage(from: a, transform: transform)
        let foreground = orientedImage(from: b, transform: transform)
        let faded = foreground.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha))
        ])
        return faded.composited(over: background)
    }

    private func enhancedAndScaled(_ image: CIImage, targetSize: CGSize) -> CIImage {
        var result = image
        if let noise = CIFilter(name: "CINoiseReduction") {
            noise.setValue(result, forKey: kCIInputImageKey)
            noise.setValue(0.015, forKey: "inputNoiseLevel")
            noise.setValue(0.25, forKey: "inputSharpness")
            result = noise.outputImage ?? result
        }
        let scale = targetSize.width / max(1, result.extent.width)
        if let lanczos = CIFilter(name: "CILanczosScaleTransform") {
            lanczos.setValue(result, forKey: kCIInputImageKey)
            lanczos.setValue(scale, forKey: kCIInputScaleKey)
            lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
            result = lanczos.outputImage ?? result
        }
        if let sharp = CIFilter(name: "CISharpenLuminance") {
            sharp.setValue(result, forKey: kCIInputImageKey)
            sharp.setValue(0.22, forKey: kCIInputSharpnessKey)
            result = sharp.outputImage ?? result
        }
        let e = result.extent
        return result.transformed(by: CGAffineTransform(translationX: -e.origin.x, y: -e.origin.y))
    }

    private func attachAudio(processedVideo: URL, original: AVAsset, outputURL: URL) async throws {
        let processed = AVURLAsset(url: processedVideo)
        guard let pv = try await processed.loadTracks(withMediaType: .video).first else { throw ProcessorError.export }
        let composition = AVMutableComposition()
        guard let cv = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ProcessorError.export }
        let videoDuration = try await processed.load(.duration)
        try cv.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: pv, at: .zero)

        if let audio = try await original.loadTracks(withMediaType: .audio).first,
           let ca = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let originalDuration = try await original.load(.duration)
            let dur = CMTimeMinimum(videoDuration, originalDuration)
            try ca.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: audio, at: .zero)
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw ProcessorError.export }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously { continuation.resume() }
        }
        guard exporter.status == .completed else { throw exporter.error ?? ProcessorError.export }
    }
}
