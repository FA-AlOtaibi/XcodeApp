import AVFoundation
import CoreML
import Foundation

final class AISuperResolution {
    enum SRFailure: Error { case modelMissing, reader, writer, noVideo, prediction }
    private let tile = 128

    func process(sourceURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let modelURL = Bundle.main.url(forResource: "PiperSR_2x", withExtension: "mlmodelc") else { throw SRFailure.modelMissing }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        let model = try MLModel(contentsOf: modelURL, configuration: config)

        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw SRFailure.noVideo }
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let oriented = natural.applying(transform)
        let width = Int(abs(oriented.width))
        let height = Int(abs(oriented.height))

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw SRFailure.reader }
        reader.add(readerOutput)

        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("AI_SR_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outURL)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
        let outW = width * 2
        let outH = height * 2
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: outW,
            AVVideoHeightKey: outH,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: min(100_000_000, max(24_000_000, outW * outH * 8))]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outW,
            kCVPixelBufferHeightKey as String: outH,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(writerInput) else { throw SRFailure.writer }
        writer.add(writerInput)
        guard reader.startReading(), writer.startWriting() else { throw SRFailure.reader }
        writer.startSession(atSourceTime: .zero)

        while reader.status == .reading {
            guard let sample = readerOutput.copyNextSampleBuffer(), let pixel = CMSampleBufferGetImageBuffer(sample) else { break }
            while !writerInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            let sr = try upscaleTiled(pixelBuffer: pixel, model: model, width: width, height: height, adaptor: adaptor)
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            guard adaptor.append(sr, withPresentationTime: pts) else { throw SRFailure.writer }
            let p = duration > 0 ? min(0.98, max(0, CMTimeGetSeconds(pts) / duration)) : 0
            progress(p)
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw SRFailure.writer }
        progress(1)
        return outURL
    }

    private func upscaleTiled(pixelBuffer: CVPixelBuffer, model: MLModel, width: Int, height: Int, adaptor: AVAssetWriterInputPixelBufferAdaptor) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw SRFailure.writer }
        var maybeOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeOut)
        guard let out = maybeOut else { throw SRFailure.writer }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(out, [])
        defer {
            CVPixelBufferUnlockBaseAddress(out, [])
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        guard let srcBase = CVPixelBufferGetBaseAddress(pixelBuffer), let dstBase = CVPixelBufferGetBaseAddress(out) else { throw SRFailure.prediction }
        let src = srcBase.assumingMemoryBound(to: UInt8.self)
        let dst = dstBase.assumingMemoryBound(to: UInt8.self)
        let srcBpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dstBpr = CVPixelBufferGetBytesPerRow(out)
        let plane = tile * tile
        let outTile = tile * 2
        let outPlane = outTile * outTile

        var ty = 0
        while ty < height {
            var tx = 0
            while tx < width {
                let arr = try MLMultiArray(shape: [1, 3, NSNumber(value: tile), NSNumber(value: tile)], dataType: .float32)
                for y in 0..<tile {
                    let sy = min(height - 1, ty + y)
                    let row = src.advanced(by: sy * srcBpr)
                    for x in 0..<tile {
                        let sx = min(width - 1, tx + x)
                        let i = sx * 4
                        let pos = y * tile + x
                        arr[pos] = NSNumber(value: Float(row[i + 2]) / 255)
                        arr[plane + pos] = NSNumber(value: Float(row[i + 1]) / 255)
                        arr[2 * plane + pos] = NSNumber(value: Float(row[i]) / 255)
                    }
                }

                let provider = try MLDictionaryFeatureProvider(dictionary: ["x": MLFeatureValue(multiArray: arr)])
                let prediction = try model.prediction(from: provider)
                guard let name = model.modelDescription.outputDescriptionsByName.keys.first,
                      let result = prediction.featureValue(for: name)?.multiArrayValue else { throw SRFailure.prediction }

                let validW = min(tile, width - tx) * 2
                let validH = min(tile, height - ty) * 2
                for y in 0..<validH {
                    let dy = ty * 2 + y
                    let row = dst.advanced(by: dy * dstBpr)
                    for x in 0..<validW {
                        let dx = tx * 2 + x
                        let pos = y * outTile + x
                        let r = max(0, min(1, result[pos].floatValue))
                        let g = max(0, min(1, result[outPlane + pos].floatValue))
                        let b = max(0, min(1, result[2 * outPlane + pos].floatValue))
                        let i = dx * 4
                        row[i] = UInt8(b * 255)
                        row[i + 1] = UInt8(g * 255)
                        row[i + 2] = UInt8(r * 255)
                        row[i + 3] = 255
                    }
                }
                tx += tile
            }
            ty += tile
        }
        return out
    }
}
