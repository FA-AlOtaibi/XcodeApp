import AVFoundation
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
            return Info(url: url, name: url.lastPathComponent,
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
        defer { isProcessing = false }

        var sourceForNative = input.url
        var aiTemporary: URL?
        var aiApplied = false

        if upscaleEngine == .ai {
            stageText = "AI detail recovery"
            do {
                let sr = AISuperResolution()
                let generated = try await sr.process(sourceURL: input.url) { p in
                    Task { @MainActor in self.progress = min(0.32, p * 0.32) }
                }
                sourceForNative = generated
                aiTemporary = generated
                aiApplied = true
            } catch {
                noticeText = "AI detail recovery was not available for this clip, so ScreenFlow switched to the native enhancer automatically."
                progress = 0.03
            }
        }

        do {
            let result = try await render(sourceURL: sourceForNative, quality: nativeQuality, baseProgress: aiApplied ? 0.32 : 0.0)
            if let aiTemporary { try? FileManager.default.removeItem(at: aiTemporary) }
            try await finish(result: result, library: library)
        } catch {
            // One automatic recovery pass: use the original source and the stable native renderer.
            if let aiTemporary { try? FileManager.default.removeItem(at: aiTemporary) }
            noticeText = "The first render path was not supported by this clip, so ScreenFlow retried it with the compatibility renderer."
            progress = 0.04
            stageText = "Compatibility render"
            do {
                let fallback = try await render(sourceURL: input.url, quality: nativeQuality, baseProgress: 0.0, forceFast: true)
                try await finish(result: fallback, library: library)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                errorText = message.isEmpty ? "This clip could not be encoded on this device." : message
            }
        }
    }

    private func render(sourceURL: URL,
                        quality: NativeVideoProcessor.OutputQuality,
                        baseProgress: Double,
                        forceFast: Bool = false) async throws -> URL {
        let processor = NativeVideoProcessor()
        return try await processor.process(
            sourceURL: sourceURL,
            targetFPS: targetFPS,
            quality: quality,
            mode: forceFast ? .fast : (mode == .smooth ? .smooth : .fast)
        ) { p, stage in
            Task { @MainActor in
                self.progress = min(0.98, baseProgress + p * (1.0 - baseProgress))
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
