import AVFoundation
import CoreML
import Foundation

final class AISuperResolution {
    enum SRFailure: LocalizedError {
        case modelMissing, unsupportedModel, reader, writer, noVideo, prediction
        var errorDescription: String? {
            switch self {
            case .modelMissing: return "Real-ESRGAN AI model is missing from the app bundle."
            case .unsupportedModel: return "The AI model format is not supported on this iPhone."
            case .reader: return "The source video could not be decoded for AI enhancement."
            case .writer: return "The AI-enhanced video could not be encoded."
            case .noVideo: return "No video track was found."
            case .prediction: return "Real-ESRGAN could not process one of the video frames."
            }
        }
    }

    private let prePad = 10
    private let overlap = 32

    func process(sourceURL: URL,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let modelURL = Bundle.main.url(forResource: "RealESRGAN_x2plus_522_fp16", withExtension: "mlmodelc") else {
            throw SRFailure.modelMissing
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try MLModel(contentsOf: modelURL, configuration: config)

        guard let inputEntry = model.modelDescription.inputDescriptionsByName.first,
              let constraint = inputEntry.value.multiArrayConstraint,
              constraint.shape.count == 4 else { throw SRFailure.unsupportedModel }

        let inputName = inputEntry.key
        let inputShape = constraint.shape.map { $0.intValue }
        let modelH = inputShape[inputShape.count - 2]
        let modelW = inputShape[inputShape.count - 1]
        guard modelW > prePad, modelH > prePad else { throw SRFailure.unsupportedModel }
        let tileW = modelW - prePad
        let tileH = modelH - prePad

        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw SRFailure.noVideo }
        let duration = max(0.001, CMTimeGetSeconds(try await asset.load(.duration)))
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let width = max(2, Int(abs(natural.width)))
        let height = max(2, Int(abs(natural.height)))

        // Avoid creating absurd 8K/12K intermediates. AI is most valuable below native 4K.
        guard max(width, height) <= 2560 else { throw SRFailure.unsupportedModel }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw SRFailure.reader }
        reader.add(readerOutput)

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RealESRGAN_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outURL)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)

        let outW = width * 2
        let outH = height * 2
        let pixels = outW * outH
        let bitrate = min(140_000_000, max(35_000_000, pixels * 9))
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: outW,
            AVVideoHeightKey: outH,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoAllowFrameReorderingKey: true,
                AVVideoMaxKeyFrameIntervalKey: 120
            ]
        ])
        writerInput.expectsMediaDataInRealTime = false
        writerInput.transform = transform

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outW,
            kCVPixelBufferHeightKey as String: outH,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])

        guard writer.canAdd(writerInput) else { throw SRFailure.writer }
        writer.add(writerInput)
        guard reader.startReading(), writer.startWriting() else { throw writer.error ?? SRFailure.writer }
        writer.startSession(atSourceTime: .zero)

        while reader.status == .reading {
            guard let sample = readerOutput.copyNextSampleBuffer(),
                  let pixel = CMSampleBufferGetImageBuffer(sample) else { break }

            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
                if writer.status == .failed { throw writer.error ?? SRFailure.writer }
            }

            let sr = try upscaleTiled(pixelBuffer: pixel,
                                      model: model,
                                      inputName: inputName,
                                      modelW: modelW,
                                      modelH: modelH,
                                      tileW: tileW,
                                      tileH: tileH,
                                      width: width,
                                      height: height,
                                      adaptor: adaptor)
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            guard adaptor.append(sr, withPresentationTime: pts) else { throw writer.error ?? SRFailure.writer }
            progress(min(0.99, max(0, CMTimeGetSeconds(pts) / duration)))
        }

        if reader.status == .failed { throw reader.error ?? SRFailure.reader }
        writerInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? SRFailure.writer }
        progress(1)
        return outURL
    }

    private func starts(total: Int, tile: Int, overlap: Int) -> [Int] {
        if total <= tile { return [0] }
        let stride = max(1, tile - overlap)
        var result: [Int] = []
        var p = 0
        while true {
            if p + tile >= total {
                let last = total - tile
                if result.last != last { result.append(last) }
                break
            }
            result.append(p)
            p += stride
        }
        return result
    }

    private func upscaleTiled(pixelBuffer: CVPixelBuffer,
                              model: MLModel,
                              inputName: String,
                              modelW: Int,
                              modelH: Int,
                              tileW: Int,
                              tileH: Int,
                              width: Int,
                              height: Int,
                              adaptor: AVAssetWriterInputPixelBufferAdaptor) throws -> CVPixelBuffer {
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

        guard let srcBase = CVPixelBufferGetBaseAddress(pixelBuffer),
              let dstBase = CVPixelBufferGetBaseAddress(out) else { throw SRFailure.prediction }
        let src = srcBase.assumingMemoryBound(to: UInt8.self)
        let dst = dstBase.assumingMemoryBound(to: UInt8.self)
        let srcBpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dstBpr = CVPixelBufferGetBytesPerRow(out)

        // Clear destination once; every owned tile region below is then written exactly once.
        memset(dstBase, 0, dstBpr * height * 2)

        let xStarts = starts(total: width, tile: tileW, overlap: overlap)
        let yStarts = starts(total: height, tile: tileH, overlap: overlap)
        let inputPlane = modelW * modelH

        for (yi, y0) in yStarts.enumerated() {
            for (xi, x0) in xStarts.enumerated() {
                let actualW = min(tileW, width - x0)
                let actualH = min(tileH, height - y0)
                let arr = try MLMultiArray(shape: [1, 3, NSNumber(value: modelH), NSNumber(value: modelW)], dataType: .float32)

                // 512px content + 10px edge context expected by this Real-ESRGAN conversion.
                for y in 0..<modelH {
                    let sy = min(height - 1, y0 + min(y, max(0, actualH - 1)))
                    let row = src.advanced(by: sy * srcBpr)
                    for x in 0..<modelW {
                        let sx = min(width - 1, x0 + min(x, max(0, actualW - 1)))
                        let i = sx * 4
                        let pos = y * modelW + x
                        arr[pos] = NSNumber(value: Float(row[i + 2]) / 255.0)
                        arr[inputPlane + pos] = NSNumber(value: Float(row[i + 1]) / 255.0)
                        arr[2 * inputPlane + pos] = NSNumber(value: Float(row[i]) / 255.0)
                    }
                }

                let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: arr)])
                let prediction = try model.prediction(from: provider)
                guard let outputEntry = model.modelDescription.outputDescriptionsByName.first,
                      let result = prediction.featureValue(for: outputEntry.key)?.multiArrayValue,
                      result.shape.count == 4 else { throw SRFailure.prediction }

                let shape = result.shape.map { $0.intValue }
                let resultH = shape[shape.count - 2]
                let resultW = shape[shape.count - 1]
                guard resultW == modelW * 2, resultH == modelH * 2 else { throw SRFailure.unsupportedModel }
                let outPlane = resultW * resultH

                // Give each overlapping tile ownership of the midpoint of its overlap.
                let sourceWriteX0: Int = {
                    guard xi > 0 else { return x0 }
                    let previousEnd = xStarts[xi - 1] + tileW
                    return (previousEnd + x0) / 2
                }()
                let sourceWriteX1: Int = {
                    guard xi + 1 < xStarts.count else { return min(width, x0 + actualW) }
                    let currentEnd = x0 + tileW
                    return (currentEnd + xStarts[xi + 1]) / 2
                }()
                let sourceWriteY0: Int = {
                    guard yi > 0 else { return y0 }
                    let previousEnd = yStarts[yi - 1] + tileH
                    return (previousEnd + y0) / 2
                }()
                let sourceWriteY1: Int = {
                    guard yi + 1 < yStarts.count else { return min(height, y0 + actualH) }
                    let currentEnd = y0 + tileH
                    return (currentEnd + yStarts[yi + 1]) / 2
                }()

                let cropX0 = max(0, sourceWriteX0 - x0)
                let cropX1 = min(actualW, sourceWriteX1 - x0)
                let cropY0 = max(0, sourceWriteY0 - y0)
                let cropY1 = min(actualH, sourceWriteY1 - y0)

                for sy in cropY0..<cropY1 {
                    for subY in 0..<2 {
                        let resultY = sy * 2 + subY
                        let dstY = (y0 + sy) * 2 + subY
                        let dstRow = dst.advanced(by: dstY * dstBpr)
                        for sx in cropX0..<cropX1 {
                            for subX in 0..<2 {
                                let resultX = sx * 2 + subX
                                let dstX = (x0 + sx) * 2 + subX
                                let pos = resultY * resultW + resultX
                                let r = max(0, min(1, result[pos].floatValue))
                                let g = max(0, min(1, result[outPlane + pos].floatValue))
                                let b = max(0, min(1, result[2 * outPlane + pos].floatValue))
                                let i = dstX * 4
                                dstRow[i] = UInt8(b * 255)
                                dstRow[i + 1] = UInt8(g * 255)
                                dstRow[i + 2] = UInt8(r * 255)
                                dstRow[i + 3] = 255
                            }
                        }
                    }
                }
            }
        }
        return out
    }
}
