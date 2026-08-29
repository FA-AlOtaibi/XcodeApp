import SwiftUI
import AVFoundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

extension AppModel {
    func extractAudio(from item: LocalMedia) async {
        guard item.isVideo else { show("هذه الميزة للفيديو فقط", .info); return }
        do {
            let asset = AVURLAsset(url: item.url)
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw AppError.message("تعذر تجهيز الصوت") }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-audio.m4a")
            try? FileManager.default.removeItem(at: tmp); export.outputURL = tmp; export.outputFileType = .m4a
            await export.export(); guard export.status == .completed else { throw export.error ?? AppError.message("فشل استخراج الصوت") }
            _ = try persist(tmp, tmp.lastPathComponent); refreshStorage(); show("تم استخراج الصوت", .success)
        } catch { show("تعذر استخراج الصوت", .error) }
    }

    func compress720(from item: LocalMedia) async {
        guard item.isVideo else { show("هذه الميزة للفيديو فقط", .info); return }
        do {
            let asset = AVURLAsset(url: item.url)
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { throw AppError.message("تعذر تجهيز الضغط") }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-720p.mp4")
            try? FileManager.default.removeItem(at: tmp); export.outputURL = tmp; export.outputFileType = .mp4
            await export.export(); guard export.status == .completed else { throw export.error ?? AppError.message("فشل الضغط") }
            _ = try persist(tmp, tmp.lastPathComponent); refreshStorage(); show("تم إنشاء نسخة أخف", .success)
        } catch { show("تعذر ضغط الفيديو", .error) }
    }

    func privacyCleanCopy(from item: LocalMedia) async {
        do {
            if item.isImage {
                guard let image = UIImage(contentsOfFile: item.url.path), let data = image.jpegData(compressionQuality: 0.94) else { throw AppError.message("تعذر قراءة الصورة") }
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-clean.jpg")
                try data.write(to: tmp); _ = try persist(tmp, tmp.lastPathComponent)
            } else if item.isVideo {
                let asset = AVURLAsset(url: item.url)
                guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { throw AppError.message("تعذر تجهيز الفيديو") }
                export.metadata = []
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-clean.mp4")
                try? FileManager.default.removeItem(at: tmp); export.outputURL = tmp; export.outputFileType = .mp4
                await export.export(); guard export.status == .completed else { throw export.error ?? AppError.message("فشل التنظيف") }
                _ = try persist(tmp, tmp.lastPathComponent)
            } else { show("التنظيف متاح للصور والفيديو", .info); return }
            refreshStorage(); show("تم إنشاء نسخة بدون بيانات وصفية", .success)
        } catch { show("تعذر تنظيف الملف", .error) }
    }

    func contactSheet(from item: LocalMedia) async {
        guard item.isVideo else { show("هذه الميزة للفيديو فقط", .info); return }
        do {
            let asset = AVURLAsset(url: item.url); let duration = try await asset.load(.duration).seconds
            let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 520, height: 520)
            var images: [UIImage] = []
            for i in 0..<9 { let second = max(0, duration * Double(i + 1) / 10.0); let result = try await generator.image(at: CMTime(seconds: second, preferredTimescale: 600)).image; images.append(UIImage(cgImage: result)) }
            let cell = CGSize(width: 360, height: 360); let renderer = UIGraphicsImageRenderer(size: CGSize(width: cell.width * 3, height: cell.height * 3))
            let sheet = renderer.image { _ in
                UIColor.black.setFill(); UIRectFill(CGRect(origin: .zero, size: CGSize(width: cell.width * 3, height: cell.height * 3)))
                for (index, image) in images.enumerated() { let rect = CGRect(x: CGFloat(index % 3) * cell.width, y: CGFloat(index / 3) * cell.height, width: cell.width, height: cell.height); image.draw(in: rect.insetBy(dx: 2, dy: 2)) }
            }
            guard let data = sheet.jpegData(compressionQuality: 0.9) else { throw AppError.message("تعذر إنشاء اللوحة") }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-frames.jpg")
            try data.write(to: tmp); _ = try persist(tmp, tmp.lastPathComponent); refreshStorage(); show("تم إنشاء لوحة 9 لقطات", .success)
        } catch { show("تعذر إنشاء اللقطات", .error) }
    }

    func grabMiddleFrame(from item: LocalMedia) async {
        guard item.isVideo else { return }
        do {
            let asset = AVURLAsset(url: item.url); let duration = try await asset.load(.duration).seconds
            let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
            let cg = try await generator.image(at: CMTime(seconds: duration / 2, preferredTimescale: 600)).image
            guard let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.95) else { throw AppError.message("تعذر استخراج اللقطة") }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-frame.jpg")
            try data.write(to: tmp); _ = try persist(tmp, tmp.lastPathComponent); refreshStorage(); show("تم حفظ لقطة من منتصف الفيديو", .success)
        } catch { show("تعذر استخراج اللقطة", .error) }
    }

    func videoToGIF(_ item: LocalMedia) async {
        guard item.isVideo else { show("اختر فيديو", .info); return }
        do {
            let asset = AVURLAsset(url: item.url); let duration = max(0.2, try await asset.load(.duration).seconds)
            let count = min(36, max(8, Int(duration * 6.0))); let delay = duration / Double(count)
            let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 720, height: 720)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent).gif")
            try? FileManager.default.removeItem(at: tmp)
            guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.gif.identifier as CFString, count, nil) else { throw AppError.message("تعذر إنشاء GIF") }
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for i in 0..<count {
                let t = min(duration - 0.01, Double(i) * delay)
                let cg = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
                let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: max(0.04, delay)]] as CFDictionary
                CGImageDestinationAddImage(dest, cg, props)
            }
            guard CGImageDestinationFinalize(dest) else { throw AppError.message("فشل حفظ GIF") }
            _ = try persist(tmp, tmp.lastPathComponent); refreshStorage(); show("تم تحويل الفيديو إلى GIF", .success)
        } catch { show("تعذر التحويل إلى GIF", .error) }
    }

    func gifToVideo(_ item: LocalMedia) async {
        guard item.ext == "gif", let source = CGImageSourceCreateWithURL(item.url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else { show("اختر ملف GIF", .info); return }
        do {
            let width = max(2, first.width), height = max(2, first.height)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-gif.mp4")
            try? FileManager.default.removeItem(at: tmp)
            let writer = try AVAssetWriter(outputURL: tmp, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
            guard writer.canAdd(input) else { throw AppError.message("تعذر تجهيز الفيديو") }; writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
            var current = 0.0
            for index in 0..<CGImageSourceGetCount(source) {
                guard let cg = CGImageSourceCreateImageAtIndex(source, index, nil), let pool = adaptor.pixelBufferPool else { continue }
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(8)) }
                var px: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, pool, &px)
                guard let pixel = px else { continue }; draw(cg, into: pixel, width: width, height: height)
                adaptor.append(pixel, withPresentationTime: CMTime(seconds: current, preferredTimescale: 600)); current += gifDelay(source, index: index)
            }
            input.markAsFinished(); await writer.finishWriting(); guard writer.status == .completed else { throw writer.error ?? AppError.message("فشل إنشاء الفيديو") }
            _ = try persist(tmp, tmp.lastPathComponent); refreshStorage(); show("تم تحويل GIF إلى فيديو", .success)
        } catch { show("تعذر تحويل GIF", .error) }
    }

    // Stereo center processing: useful when vocals are mixed in the center. It is intentionally labeled experimental.
    func separateCenterAudio(from item: LocalMedia, keepVoice: Bool) async {
        guard item.isVideo else { show("اختر فيديو", .info); return }
        do {
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-\(keepVoice ? "voice" : "no-voice").mp4")
            try? FileManager.default.removeItem(at: output)
            try await processStereoVideo(item.url, output: output, keepCenter: keepVoice)
            _ = try persist(output, output.lastPathComponent); refreshStorage()
            show(keepVoice ? "تم إنشاء نسخة تركّز على الصوت البشري" : "تم إنشاء نسخة تقلل الصوت البشري", .success)
        } catch { show("تعذر فصل الصوت؛ تعمل أفضل مع فيديو ستيريو", .error) }
    }

    func autoRename(_ item: LocalMedia) {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let kind = item.isVideo ? "Video" : item.isImage ? "Photo" : item.isAudio ? "Audio" : item.ext == "gif" ? "GIF" : "File"
        renameLocal(item, to: "\(kind)_\(formatter.string(from: item.createdAt))")
    }

    func prepareForSnapchat(_ item: LocalMedia) {
        if item.isImage, let image = UIImage(contentsOfFile: item.url.path) { UIPasteboard.general.image = image }
        else { UIPasteboard.general.url = item.url }
        show("جاهز للمشاركة إلى Snapchat", .success)
    }

    func batchDownloadClipboard() async {
        guard let text = UIPasteboard.general.string else { show("الحافظة فارغة", .info); return }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue); let range = NSRange(text.startIndex..., in: text)
        let urls = detector?.matches(in: text, range: range).compactMap { $0.url }.filter { $0.scheme?.hasPrefix("http") == true } ?? []
        guard !urls.isEmpty else { show("لا توجد روابط في الحافظة", .info); return }; show("تم العثور على \(urls.count) رابط", .info)
        for source in urls.prefix(12) {
            do {
                let media: [DownloadMedia]
                switch detect(source) { case .tiktok: media = try await resolveTikTok(source); case .youtube: media = try await resolveYouTubeV2(source); case .x: media = try await resolveX(source); case .instagram: media = try await resolveMeta(source, .instagram); case .facebook: media = try await resolveMeta(source, .facebook); case .generic: media = try await resolveMeta(source, .generic) }
                if let best = media.first { await enqueueSmart(best, target: .app) }
            } catch { continue }
        }
        show("انتهت دفعة الروابط", .success)
    }

    private func gifDelay(_ source: CGImageSource, index: Int) -> Double {
        guard let p = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any], let gif = p[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        return (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
    }

    private func draw(_ cg: CGImage, into pixel: CVPixelBuffer, width: Int, height: Int) {
        CVPixelBufferLockBaseAddress(pixel, []); defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixel), let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height)); context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private func processStereoVideo(_ source: URL, output: URL, keepCenter: Bool) async throws {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else { throw AppError.message("لا يوجد صوت في الفيديو") }
        let reader = try AVAssetReader(asset: asset)
        let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        let audioOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false])
        reader.add(videoOut); reader.add(audioOut)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let vHint = try await videoTrack.load(.formatDescriptions).first
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: vHint)
        let aDesc = try await audioTrack.load(.formatDescriptions).first
        let asbd = aDesc.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let rate = asbd?.mSampleRate ?? 44100; let channels = max(1, Int(asbd?.mChannelsPerFrame ?? 2))
        let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: min(2, channels), AVEncoderBitRateKey: 192000], sourceFormatHint: nil)
        guard writer.canAdd(videoIn), writer.canAdd(audioIn) else { throw AppError.message("تعذر تجهيز المعالجة") }; writer.add(videoIn); writer.add(audioIn)
        guard writer.startWriting(), reader.startReading() else { throw writer.error ?? reader.error ?? AppError.message("تعذر بدء المعالجة") }; writer.startSession(atSourceTime: .zero)
        while let sample = videoOut.copyNextSampleBuffer() { while !videoIn.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }; if !videoIn.append(sample) { throw writer.error ?? AppError.message("تعذر كتابة الفيديو") } }
        videoIn.markAsFinished()
        while let sample = audioOut.copyNextSampleBuffer() {
            if channels >= 2, let block = CMSampleBufferGetDataBuffer(sample) {
                var lengthAtOffset = 0, totalLength = 0; var dataPointer: UnsafeMutablePointer<Int8>?
                if CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr, let raw = dataPointer {
                    let samples = raw.withMemoryRebound(to: Int16.self, capacity: totalLength / 2) { $0 }; let count = totalLength / 2
                    var i = 0
                    while i + 1 < count {
                        let l = Int32(samples[i]), r = Int32(samples[i + 1]); let value: Int32
                        if keepCenter { value = (l + r) / 2; samples[i] = clamp16(value); samples[i + 1] = clamp16(value) }
                        else { value = (l - r) / 2; samples[i] = clamp16(value); samples[i + 1] = clamp16(-value) }
                        i += channels
                    }
                }
            }
            while !audioIn.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            if !audioIn.append(sample) { throw writer.error ?? AppError.message("تعذر كتابة الصوت") }
        }
        audioIn.markAsFinished(); await writer.finishWriting(); guard writer.status == .completed else { throw writer.error ?? AppError.message("فشلت المعالجة") }
    }

    private func clamp16(_ value: Int32) -> Int16 { Int16(max(Int32(Int16.min), min(Int32(Int16.max), value))) }
}

struct MediaLabView: View {
    @ObservedObject var model: AppModel
    @State private var selected: LocalMedia?
    @State private var busy = false
    @State private var shareURL: URL?
    @State private var showShare = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) { Text("المعمل").font(.system(size: 36, weight: .bold, design: .rounded)); Text("تحويل ومعالجة محلية بدون رفع ملفاتك").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { run { await model.batchDownloadClipboard() } } label: { HStack(spacing: 14) { Image(systemName: "link.badge.plus").font(.title2); VStack(alignment: .leading, spacing: 3) { Text("دفعة روابط من الحافظة").font(.headline); Text("عدة روابط في عملية واحدة").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.left").foregroundStyle(.secondary) }.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20)) }.buttonStyle(.plain)
                    if let selected {
                        LocalThumb(item: selected).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 24))
                        HStack { Text(selected.url.deletingPathExtension().lastPathComponent).font(.headline).lineLimit(1); Spacer(); Button("تغيير") { self.selected = nil } }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            LabAction(title: "فيديو → GIF", icon: "photo.stack", enabled: selected.isVideo) { run { await model.videoToGIF(selected) } }
                            LabAction(title: "GIF → فيديو", icon: "film", enabled: selected.ext == "gif") { run { await model.gifToVideo(selected) } }
                            LabAction(title: "إزالة الصوت البشري", icon: "person.wave.2", enabled: selected.isVideo) { run { await model.separateCenterAudio(from: selected, keepVoice: false) } }
                            LabAction(title: "تقليل الموسيقى / عزل الكلام", icon: "waveform.and.mic", enabled: selected.isVideo) { run { await model.separateCenterAudio(from: selected, keepVoice: true) } }
                            LabAction(title: "إرسال إلى Snapchat", icon: "paperplane", enabled: selected.isImage || selected.isVideo) { model.prepareForSnapchat(selected); shareURL = selected.url; showShare = true }
                            LabAction(title: "استخراج الصوت", icon: "waveform", enabled: selected.isVideo) { run { await model.extractAudio(from: selected) } }
                            LabAction(title: "نسخة 720p", icon: "arrow.down.right.and.arrow.up.left", enabled: selected.isVideo) { run { await model.compress720(from: selected) } }
                            LabAction(title: "تنظيف الخصوصية", icon: "shield.lefthalf.filled", enabled: selected.isVideo || selected.isImage) { run { await model.privacyCleanCopy(from: selected) } }
                            LabAction(title: "لقطة وسطية", icon: "photo", enabled: selected.isVideo) { run { await model.grabMiddleFrame(from: selected) } }
                            LabAction(title: "لوحة 9 لقطات", icon: "square.grid.3x3", enabled: selected.isVideo) { run { await model.contactSheet(from: selected) } }
                            LabAction(title: "اسم مرتب", icon: "textformat", enabled: true) { model.autoRename(selected) }
                        }
                        Text("فصل الصوت تجريبي محليًا ويعمل أفضل عندما يكون الصوت البشري في المنتصف والموسيقى ستيريو.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 12) { Image(systemName: "slider.horizontal.3").font(.system(size: 46)).foregroundStyle(.secondary); Text("اختر ملفًا من مكتبتك").font(.headline); Text("GIF، فصل صوت، ضغط، خصوصية، لقطات ومشاركة").font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical, 24)
                        ForEach(model.library.prefix(16)) { item in Button { selected = item } label: { CompactMediaRow(item: item, model: model) }.buttonStyle(.plain) }
                    }
                    if busy { ProgressView("جارٍ تنفيذ العملية…").padding(.top, 8) }
                }.padding(20)
            }.navigationTitle("المعمل").navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showShare) { if let shareURL { ActivityShareView(items: [shareURL]) } }
    }
    private func run(_ op: @escaping () async -> Void) { busy = true; Task { await op(); busy = false } }
}

struct LabAction: View {
    let title: String; let icon: String; let enabled: Bool; let action: () -> Void
    var body: some View { Button(action: action) { VStack(alignment: .leading, spacing: 14) { Image(systemName: icon).font(.title2); Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading) }.padding(16).frame(minHeight: 104).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20)) }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35) }
}

struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
