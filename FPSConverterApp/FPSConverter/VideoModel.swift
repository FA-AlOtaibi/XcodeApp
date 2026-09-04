import AVFoundation
import Combine
import Foundation
import Photos

@MainActor
final class VideoModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case simple = "Fast"
        case smooth = "Smooth"
        var id: String { rawValue }
    }

    enum Quality: String, CaseIterable, Identifiable {
        case enhanced = "Enhanced"
        case twoK = "2K"
        case fourK = "4K"
        var id: String { rawValue }
    }

    enum UpscaleEngine: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case ai = "AI Super Resolution"
        var id: String { rawValue }
    }

    struct Info {
        let url: URL
        let name: String
        let duration: Double
        let fps: Double
        let width: Int
        let height: Int
        let bytes: Int64
        var durationText: String {
            let s = max(0, Int(duration.rounded()))
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        var resolutionText: String { "\(width)×\(height)" }
        var fpsText: String { fps > 0 ? String(format: "%.1f FPS", fps) : "Unknown FPS" }
    }

    @Published var input: Info?
    @Published var output: Info?
    @Published var targetFPS = 60
    @Published var mode: Mode = .smooth
    @Published var quality: Quality = .fourK
    @Published var upscaleEngine: UpscaleEngine = .ai
    @Published var isProcessing = false
    @Published var stageText = ""
    @Published var progress: Double = 0
    @Published var errorText: String?
    @Published var showSaved = false
    @Published var noticeText: String?
    @Published var savedLibraryItem: LibraryStore.Item?

    let fpsOptions = [24, 30, 60, 120]

    func inspect(url: URL) async -> Info? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        do {
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let oriented = natural.applying(transform)
            let duration = CMTimeGetSeconds(try await asset.load(.duration))
            let fps = Double(try await track.load(.nominalFrameRate))
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            return Info(url: url,
                        name: url.lastPathComponent,
                        duration: duration.isFinite ? duration : 0,
                        fps: fps,
                        width: max(2, Int(abs(oriented.width))),
                        height: max(2, Int(abs(oriented.height))),
                        bytes: bytes)
        } catch { return nil }
    }

    func setInput(url: URL) async {
        errorText = nil
        noticeText = nil
        output = nil
        savedLibraryItem = nil
        progress = 0
        input = await inspect(url: url)
        if input == nil { errorText = "This video could not be opened. Try MP4 or MOV." }
    }

    func convert(library: LibraryStore) async {
        guard let input else { return }
        isProcessing = true
        output = nil
        savedLibraryItem = nil
        errorText = nil
        noticeText = nil
        progress = 0.01

        var motionTemp: URL?
        var aiTemp: URL?
        defer {
            isProcessing = false
            if let motionTemp { try? FileManager.default.removeItem(at: motionTemp) }
            if let aiTemp { try? FileManager.default.removeItem(at: aiTemp) }
        }

        var workingURL = input.url
        var aiApplied = false
        var completedBase = 0.0

        // Smooth mode now uses true motion-compensated interpolation instead of cross-fading frames.
        if mode == .smooth, input.fps > 0, Double(targetFPS) > input.fps + 0.5 {
            stageText = "Motion-compensated interpolation"
            do {
                let interpolator = MotionInterpolator()
                let generated = try await interpolator.interpolate(sourceURL: input.url, targetFPS: targetFPS) { p in
                    Task { @MainActor in self.progress = min(0.28, 0.02 + p * 0.26) }
                }
                workingURL = generated
                motionTemp = generated
                completedBase = 0.28
            } catch {
                noticeText = "The advanced motion engine was unavailable for this clip, so ScreenFlow kept exact frame timing without frame blending."
                completedBase = 0.04
            }
        }

        if upscaleEngine == .ai {
            stageText = "Real-ESRGAN detail recovery"
            do {
                let sr = AISuperResolution()
                let start = completedBase
                let span = start >= 0.25 ? 0.42 : 0.58
                let generated = try await sr.process(sourceURL: workingURL) { p in
                    Task { @MainActor in self.progress = min(0.74, start + p * span) }
                }
                workingURL = generated
                aiTemp = generated
                aiApplied = true
                completedBase = max(completedBase + span, 0.62)
            } catch {
                let previous = noticeText.map { $0 + " " } ?? ""
                noticeText = previous + "Real-ESRGAN could not run on this clip, so the high-quality native enhancer was used automatically."
                completedBase = max(completedBase, 0.08)
            }
        }

        do {
            let result = try await render(sourceURL: workingURL,
                                          original: input,
                                          aiApplied: aiApplied,
                                          baseProgress: completedBase)
            try await finish(result: result, library: library)
        } catch {
            // Final compatibility retry: original source, stable native renderer, exact cadence.
            let previous = noticeText.map { $0 + " " } ?? ""
            noticeText = previous + "ScreenFlow retried the final render with the compatibility path."
            progress = 0.06
            stageText = "Compatibility render"
            do {
                let fallback = try await render(sourceURL: input.url,
                                                original: input,
                                                aiApplied: false,
                                                baseProgress: 0,
                                                forceCompatibility: true)
                try await finish(result: fallback, library: library)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                errorText = message.isEmpty ? "This clip could not be encoded on this iPhone." : message
            }
        }
    }

    private func render(sourceURL: URL,
                        original: Info,
                        aiApplied: Bool,
                        baseProgress: Double,
                        forceCompatibility: Bool = false) async throws -> URL {
        let processor = NativeVideoProcessor()
        let base = min(0.78, baseProgress)
        return try await processor.process(
            sourceURL: sourceURL,
            audioSourceURL: original.url,
            targetFPS: targetFPS,
            quality: nativeQuality,
            mode: .fast,
            referenceDisplaySize: CGSize(width: original.width, height: original.height),
            aiSource: aiApplied && !forceCompatibility
        ) { p, stage in
            Task { @MainActor in
                self.progress = min(0.98, base + p * (1.0 - base))
                self.stageText = stage
            }
        }
    }

    private func finish(result: URL, library: LibraryStore) async throws {
        guard let resultInfo = await inspect(url: result) else {
            try? FileManager.default.removeItem(at: result)
            throw NativeVideoProcessor.ProcessorError.export
        }
        stageText = "Saving to Library"
        progress = 0.99
        do {
            let item = try library.add(sourceURL: result, info: resultInfo)
            savedLibraryItem = item
            output = await inspect(url: library.url(for: item))
            try? FileManager.default.removeItem(at: result)
        } catch {
            output = resultInfo
            noticeText = "The export finished, but it could not be copied into the app Library. You can still save or share it."
        }
        progress = 1
        stageText = "Done"
    }

    private var nativeQuality: NativeVideoProcessor.OutputQuality {
        switch quality {
        case .enhanced: return .enhanced
        case .twoK: return .twoK
        case .fourK: return .fourK
        }
    }

    func saveToPhotos() {
        guard let url = output?.url else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, _ in
                Task { @MainActor in self.showSaved = success }
            }
        }
    }
}
