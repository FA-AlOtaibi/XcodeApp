import Foundation
import AVFoundation
import UIKit

final class VideoMediaProcessor {
    enum MediaError: LocalizedError {
        case unreadable
        var errorDescription: String? { "تعذر قراءة الفيديو أو استخراج صوته." }
    }

    func process(url: URL) async throws -> (frames: [Data], sound: MediaSoundProfile?) {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = max(0.1, CMTimeGetSeconds(duration))
        let frames = try await extractFrames(asset: asset, duration: seconds)
        let sound = try? await extractSoundProfile(asset: asset, duration: seconds)
        return (frames, sound)
    }

    private func extractFrames(asset: AVAsset, duration: Double) async throws -> [Data] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1100, height: 1100)
        let count = min(8, max(4, Int(duration / 2.0)))
        let times = (0..<count).map { index -> NSValue in
            let fraction = Double(index + 1) / Double(count + 1)
            return NSValue(time: CMTime(seconds: duration * fraction, preferredTimescale: 600))
        }
        return try await withCheckedThrowingContinuation { continuation in
            var output = [Data]()
            var failures = 0
            let lock = NSLock()
            generator.generateCGImagesAsynchronously(forTimes: times) { _, cgImage, _, result, _ in
                lock.lock(); defer { lock.unlock() }
                if result == .succeeded, let cgImage {
                    let image = UIImage(cgImage: cgImage)
                    if let data = ImageCompressor.jpegData(from: image) { output.append(data) }
                } else { failures += 1 }
                if output.count + failures == times.count {
                    if output.isEmpty { continuation.resume(throwing: MediaError.unreadable) }
                    else { continuation.resume(returning: output) }
                }
            }
        }
    }

    private func extractSoundProfile(asset: AVAsset, duration: Double) async throws -> MediaSoundProfile {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            return MediaSoundProfile(durationSeconds: duration, rms: 0, peak: 0, zeroCrossingRate: 0, dominantPulseHz: nil, note: "الفيديو لا يحتوي على مسار صوتي قابل للقراءة.")
        }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MediaError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw MediaError.unreadable }

        var samples = [Float]()
        let maxSamples = 44100 * 12
        while reader.status == .reading, samples.count < maxSamples, let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { ptr in
                if let base = ptr.baseAddress { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base) }
            }
            data.withUnsafeBytes { raw in
                let floatBuffer = raw.bindMemory(to: Float.self)
                let take = min(floatBuffer.count, maxSamples - samples.count)
                samples.append(contentsOf: floatBuffer.prefix(take))
            }
        }
        guard samples.count > 100 else { throw MediaError.unreadable }

        var sumSquares = 0.0
        var peak = 0.0
        var zeroCrossings = 0
        var previous = samples[0]
        var envelope = [Double]()
        let window = 1024
        for (i, value) in samples.enumerated() {
            let v = Double(value)
            sumSquares += v * v
            peak = max(peak, abs(v))
            if (value >= 0) != (previous >= 0) { zeroCrossings += 1 }
            previous = value
            if i % window == 0, i + window <= samples.count {
                var local = 0.0
                for j in i..<(i + window) { local += abs(Double(samples[j])) }
                envelope.append(local / Double(window))
            }
        }
        let rms = sqrt(sumSquares / Double(samples.count))
        let zcr = Double(zeroCrossings) / Double(samples.count)
        let pulse = estimatePulseHz(envelope: envelope, assumedSampleRate: 44100.0 / Double(window))
        return MediaSoundProfile(
            durationSeconds: duration,
            rms: rms,
            peak: peak,
            zeroCrossingRate: zcr,
            dominantPulseHz: pulse,
            note: "هذه خصائص رقمية تقريبية للصوت وليست تشخيصًا ميكانيكيًا مستقلًا؛ تُدمج مع لقطات الفيديو والأعراض."
        )
    }

    private func estimatePulseHz(envelope: [Double], assumedSampleRate: Double) -> Double? {
        guard envelope.count > 20 else { return nil }
        let mean = envelope.reduce(0, +) / Double(envelope.count)
        let x = envelope.map { $0 - mean }
        var bestLag = 0
        var best = 0.0
        let minLag = max(2, Int(assumedSampleRate / 12.0))
        let maxLag = min(x.count / 2, Int(assumedSampleRate / 0.7))
        guard minLag < maxLag else { return nil }
        for lag in minLag...maxLag {
            var score = 0.0
            for i in 0..<(x.count - lag) { score += x[i] * x[i + lag] }
            if score > best { best = score; bestLag = lag }
        }
        guard bestLag > 0, best > 0 else { return nil }
        return assumedSampleRate / Double(bestLag)
    }
}
