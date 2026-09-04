import AVFoundation
import CoreImage
import CoreML
import Foundation

final class AISuperResolution {
    enum SRFailure: Error {
        case modelMissing
        case modelLoad
        case reader
        case writer
        case noVideo
        case prediction
    }

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func process(sourceURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let modelURL = Bundle.main.url(forResource: "PiperSR_2x", withExtension: "mlmodelc") else {
            throw SRFailure.modelMissing
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        let model = try MLModel(contentsOf: modelURL, configuration: config)

        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw SRFailure.noVideo }
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let oriented = naturalSize.applying(transform)
        let width = Int(abs(oriented.width))
        let height = Int(abs(oriented.height))

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw SRFailure.reader }
        reader.add(readerOutput)

        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("AI_SR_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outURL)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
        let outWidth = width * 2
        let outHeight = height * 2
        let bitrate = min(100_000_000, max(20_000_000, outWidth * outHeight * 8))
        let writerSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: outWidth,
            AVVideoHeightKey: outHeight,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate]
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
        writerInput.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outWidth,
            kCVPixelBufferHeightKey as String: outHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: attrs)
        guard writer.canAdd(writerInput) else { throw SRFailure.writer }
        writer.add(writerInput)

        guard reader.startReading(), writer.startWriting() else { throw SRFailure.reader }
        writer.startSession(atSourceTime: .zero)

        while reader.status == .reading {
            autoreleasepool {
                guard let sample = readerOutput.copyNextSampleBuffer(),
                      let pixel = CMSampleBufferGetImageBuffer(sample) else { return }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)

                while !writerInput.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.002)
                }

                do {
                    let sr = try self.upscale(pixelBuffer: pixel, model: model, width: width, height: height, adaptor: adaptor)
                    adaptor.append(sr, withPresentationTime: pts)
                    let p = duration > 0 ? min(0.96, max(0, CMTimeGetSeconds(pts) / duration)) : 0
                    progress(p)
                } catch {
                    reader.cancelReading()
                    writer.cancelWriting()
                }
            }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw SRFailure.writer }
        progress(1)
        return outURL
    }

    private func upscale(pixelBuffer: CVPixelBuffer, model: MLModel, width: Int, height: Int, adaptor: AVAssetWriterInputPixelBufferAdaptor) throws -> CVPixelBuffer {
        let shape: [NSNumber] = [1, 3, NSNumber(value: height), NSNumber(value: width)]
        let inputArray = try MLMultiArray(shape: shape, dataType: .float32)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { throw SRFailure.prediction }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let plane = width * height

        for y in 0..<height {
            let row = ptr.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let i = x * 4
                let b = Float(row[i]) / 255.0
                let g = Float(row[i + 1]) / 255.0
                let r = Float(row[i + 2]) / 255.0
                let pos = y * width + x
                inputArray[pos] = NSNumber(value: r)
                inputArray[plane + pos] = NSNumber(value: g)
                inputArray[2 * plane + pos] = NSNumber(value: b)
            }
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: inputArray)])
        let prediction = try model.prediction(from: provider)
        guard let name = model.modelDescription.outputDescriptionsByName.keys.first,
              let outArray = prediction.featureValue(for: name)?.multiArrayValue else { throw SRFailure.prediction }

        guard let pool = adaptor.pixelBufferPool else { throw SRFailure.writer }
        var maybeOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeOut)
        guard let out = maybeOut else { throw SRFailure.writer }

        let outW = width * 2
        let outH = height * 2
        let outPlane = outW * outH
        CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []) }
        guard let outBase = CVPixelBufferGetBaseAddress(out) else { throw SRFailure.writer }
        let outBpr = CVPixelBufferGetBytesPerRow(out)
        let dst = outBase.assumingMemoryBound(to: UInt8.self)

        for y in 0..<outH {
            let row = dst.advanced(by: y * outBpr)
            for x in 0..<outW {
                let pos = y * outW + x
                let r = max(0, min(1, outArray[pos].floatValue))
                let g = max(0, min(1, outArray[outPlane + pos].floatValue))
                let b = max(0, min(1, outArray[2 * outPlane + pos].floatValue))
                let i = x * 4
                row[i] = UInt8(b * 255)
                row[i + 1] = UInt8(g * 255)
                row[i + 2] = UInt8(r * 255)
                row[i + 3] = 255
            }
        }
        return out
    }
}
