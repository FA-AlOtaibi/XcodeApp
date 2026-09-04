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

    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .priorityRequestLow: false,
        .useSoftwareRenderer: false
    ])

    func process(sourceURL: URL,
                 audioSourceURL: URL? = nil,
                 targetFPS: Int,
                 quality: OutputQuality,
                 mode: MotionMode,
                 referenceDisplaySize: CGSize? = nil,
                 aiSource: Bool = false,
                 progress: @escaping @Sendable (Double, String) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ProcessorError.noVideo }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let oriented = natural.applying(transform)
        let decodedDisplaySize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let sizingReference = referenceDisplaySize ?? decodedDisplaySize
        let targetSize = outputSize(from: sizingReference, quality: quality)

        let temp = FileManager.default.temporaryDirectory
        let videoOnly = temp.appendingPathComponent("screenflow_video_\(UUID().uuidString).mp4")
        let finalURL = temp.appendingPathComponent("ScreenFlow_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: videoOnly)
        try? FileManager.default.removeItem(at: finalURL)

        progress(0.02, aiSource ? "Preserving AI detail" : "Preparing high-quality render")
        var lastError: Error?
        for codec in codecPreference(for: quality, fps: targetFPS) {
            for bitrateScale in [1.0, 0.82, 0.66] {
                do {
                    try await encodeVideo(asset: asset,
                                          track: track,
                                          transform: transform,
                                          targetSize: targetSize,
                                          targetFPS: targetFPS,
                                          codec: codec,
                                          bitrateScale: bitrateScale,
                                          outputURL: videoOnly,
                                          aiSource: aiSource,
                                          progress: progress)
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    try? FileManager.default.removeItem(at: videoOnly)
                }
            }
            if lastError == nil { break }
        }
        if let lastError { throw lastError }

        progress(0.95, "Restoring original audio")
        let audioAsset = AVURLAsset(url: audioSourceURL ?? sourceURL)
        do {
            try await attachAudio(processedVideo: videoOnly, original: audioAsset, outputURL: finalURL)
            try? FileManager.default.removeItem(at: videoOnly)
            progress(1, "Done")
            return finalURL
        } catch {
            // A video-only result is still valid if the source had an unsupported audio format.
            try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.moveItem(at: videoOnly, to: finalURL)
            progress(1, "Done")
            return finalURL
        }
    }

    private func codecPreference(for quality: OutputQuality, fps: Int) -> [AVVideoCodecType] {
        if quality == .fourK || fps >= 60 { return [.hevc, .h264] }
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
                             codec: AVVideoCodecType,
                             bitrateScale: Double,
                             outputURL: URL,
                             aiSource: Bool,
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
        let bitrate = Int(Double(bitrateFor(size: targetSize, fps: targetFPS, codec: codec)) * bitrateScale)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: targetFPS,
            AVVideoMaxKeyFrameIntervalKey: max(targetFPS * 2, 60),
            AVVideoAllowFrameReorderingKey: true
        ]
        if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }

        let settings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(targetSize.width),
            AVVideoHeightKey: Int(targetSize.height),
            AVVideoCompressionPropertiesKey: compression
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        input.mediaTimeScale = 60_000

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(targetSize.width),
            kCVPixelBufferHeightKey as String: Int(targetSize.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        guard writer.canAdd(input) else { throw ProcessorError.writer }
        writer.add(input)
        guard reader.startReading(), writer.startWriting() else { throw writer.error ?? ProcessorError.writer }
        writer.startSession(atSourceTime: .zero)

        guard var previous = readerOutput.copyNextSampleBuffer() else { throw ProcessorError.reader }
        var current = readerOutput.copyNextSampleBuffer()
        var nextOutputIndex: Int64 = 0
        let fps = Int32(max(1, targetFPS))

        while let next = current {
            guard let prevBuffer = CMSampleBufferGetImageBuffer(previous),
                  let nextBuffer = CMSampleBufferGetImageBuffer(next) else { throw ProcessorError.reader }
            let prevTime = max(0, CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(previous)))
            let nextTime = max(prevTime + 0.000_001, CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(next)))

            while Double(nextOutputIndex) / Double(fps) <= nextTime + 0.000_001 {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 750_000)
                    if writer.status == .failed { throw writer.error ?? ProcessorError.writer }
                }

                let outputSeconds = Double(nextOutputIndex) / Double(fps)
                let usePrevious = abs(outputSeconds - prevTime) <= abs(nextTime - outputSeconds)
                let source = usePrevious ? prevBuffer : nextBuffer
                let image = orientedImage(from: source, transform: transform)

                guard let pool = adaptor.pixelBufferPool else { throw ProcessorError.writer }
                var out: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
                guard let pixel = out else { throw ProcessorError.writer }

                let processed = enhancedAndScaled(image, targetSize: targetSize, aiSource: aiSource)
                context.render(processed,
                               to: pixel,
                               bounds: CGRect(origin: .zero, size: targetSize),
                               colorSpace: CGColorSpaceCreateDeviceRGB())
                let pts = CMTime(value: nextOutputIndex, timescale: fps)
                guard adaptor.append(pixel, withPresentationTime: pts) else { throw writer.error ?? ProcessorError.writer }
                nextOutputIndex += 1
                progress(min(0.92, 0.05 + (outputSeconds / seconds) * 0.87),
                         aiSource ? "Encoding AI-enhanced frames" : "Enhancing and encoding frames")
            }
            previous = next
            current = readerOutput.copyNextSampleBuffer()
        }

        if let last = CMSampleBufferGetImageBuffer(previous) {
            while Double(nextOutputIndex) / Double(fps) < seconds - 0.000_001 {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 750_000)
                    if writer.status == .failed { throw writer.error ?? ProcessorError.writer }
                }
                guard let pool = adaptor.pixelBufferPool else { throw ProcessorError.writer }
                var out: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
                guard let pixel = out else { throw ProcessorError.writer }
                let processed = enhancedAndScaled(orientedImage(from: last, transform: transform), targetSize: targetSize, aiSource: aiSource)
                context.render(processed,
                               to: pixel,
                               bounds: CGRect(origin: .zero, size: targetSize),
                               colorSpace: CGColorSpaceCreateDeviceRGB())
                guard adaptor.append(pixel, withPresentationTime: CMTime(value: nextOutputIndex, timescale: fps)) else {
                    throw writer.error ?? ProcessorError.writer
                }
                nextOutputIndex += 1
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ProcessorError.writer }
    }

    private func bitrateFor(size: CGSize, fps: Int, codec: AVVideoCodecType) -> Int {
        let pixelRatio = max(1, size.width * size.height) / CGFloat(1920 * 1080)
        let fpsRatio = max(1.0, Double(fps) / 30.0)
        var mbps = 28.0 * Double(pixelRatio) * sqrt(fpsRatio)
        if codec == .hevc { mbps *= 0.76 }
        mbps = min(220, max(20, mbps))
        return Int(mbps * 1_000_000)
    }

    private func orientedImage(from buffer: CVPixelBuffer, transform: CGAffineTransform) -> CIImage {
        let transformed = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
        let extent = transformed.extent
        return transformed.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
    }

    private func enhancedAndScaled(_ image: CIImage, targetSize: CGSize, aiSource: Bool) -> CIImage {
        var result = image

        if !aiSource, let noise = CIFilter(name: "CINoiseReduction") {
            noise.setValue(result, forKey: kCIInputImageKey)
            noise.setValue(0.006, forKey: "inputNoiseLevel")
            noise.setValue(0.28, forKey: "inputSharpness")
            result = noise.outputImage ?? result
        }

        let scaleX = targetSize.width / max(1, result.extent.width)
        if abs(scaleX - 1) > 0.001, let lanczos = CIFilter(name: "CILanczosScaleTransform") {
            lanczos.setValue(result, forKey: kCIInputImageKey)
            lanczos.setValue(scaleX, forKey: kCIInputScaleKey)
            lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
            result = lanczos.outputImage ?? result
        }

        if aiSource {
            if let sharpen = CIFilter(name: "CISharpenLuminance") {
                sharpen.setValue(result, forKey: kCIInputImageKey)
                sharpen.setValue(0.10, forKey: kCIInputSharpnessKey)
                result = sharpen.outputImage ?? result
            }
        } else {
            if let unsharp = CIFilter(name: "CIUnsharpMask") {
                unsharp.setValue(result, forKey: kCIInputImageKey)
                unsharp.setValue(0.42, forKey: kCIInputIntensityKey)
                unsharp.setValue(0.90, forKey: kCIInputRadiusKey)
                result = unsharp.outputImage ?? result
            }
            if let sharpen = CIFilter(name: "CISharpenLuminance") {
                sharpen.setValue(result, forKey: kCIInputImageKey)
                sharpen.setValue(0.18, forKey: kCIInputSharpnessKey)
                result = sharpen.outputImage ?? result
            }
        }

        let extent = result.extent
        return result.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
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
