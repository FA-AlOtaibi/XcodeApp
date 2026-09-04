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
    @Published var quality: Quality = .twoK
    @Published var upscaleEngine: UpscaleEngine = .standard
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
        } catch {
            return nil
        }
    }

    func setInput(url: URL) async {
        errorText = nil
        noticeText = nil
        output = nil
        savedLibraryItem = nil
        progress = 0
        input = await inspect(url: url)
        if input == nil {
            errorText = "This video could not be opened. Try MP4 or MOV."
        }
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

        if upscaleEngine == .ai && quality != .enhanced {
            stageText = "AI Super Resolution"
            do {
                let sr = AISuperResolution()
                let generated = try await sr.process(sourceURL: input.url) { p in
                    Task { @MainActor in
                        self.progress = min(0.28, p * 0.28)
                    }
                }
                sourceForNative = generated
                aiTemporary = generated
            } catch {
                noticeText = "AI Super Resolution was unavailable for this clip, so ScreenFlow automatically continued with the native high-quality scaler."
                sourceForNative = input.url
                progress = 0.02
            }
        }

        let processor = NativeVideoProcessor()
        do {
            let result = try await processor.process(
                sourceURL: sourceForNative,
                targetFPS: targetFPS,
                quality: nativeQuality,
                mode: mode == .smooth ? .smooth : .fast
            ) { p, stage in
                Task { @MainActor in
                    let base = self.upscaleEngine == .ai && aiTemporary != nil ? 0.28 : 0.0
                    self.progress = min(0.99, base + p * (1.0 - base))
                    self.stageText = stage
                }
            }
            if let aiTemporary { try? FileManager.default.removeItem(at: aiTemporary) }

            guard let resultInfo = await inspect(url: result) else {
                try? FileManager.default.removeItem(at: result)
                errorText = "The conversion finished, but the output file could not be verified."
                return
            }

            stageText = "Saving to Library"
            progress = 0.99
            do {
                let item = try library.add(sourceURL: result, info: resultInfo)
                savedLibraryItem = item
                let permanent = library.url(for: item)
                output = await inspect(url: permanent)
                try? FileManager.default.removeItem(at: result)
            } catch {
                output = resultInfo
                noticeText = "The video was converted successfully, but it could not be copied into the app Library. You can still save or share it."
            }
            progress = 1
            stageText = "Done"
        } catch {
            if let aiTemporary { try? FileManager.default.removeItem(at: aiTemporary) }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorText = message.isEmpty ? "The video could not be converted." : message
        }
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
