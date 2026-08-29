import Foundation
import AVFoundation
import UIKit
import Vision
import CoreImage

extension AppModel {
    func duplicateMedia(_ item: LocalMedia) {
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("copy-\(UUID().uuidString).\(item.ext)")
            try? FileManager.default.removeItem(at: tmp)
            try FileManager.default.copyItem(at: item.url, to: tmp)
            _ = try persist(tmp, "\(item.url.deletingPathExtension().lastPathComponent)-copy.\(item.ext)")
            refreshStorage(); show("تم إنشاء نسخة", .success)
        } catch { show("تعذر إنشاء نسخة", .error) }
    }

    func muteVideo(_ item: LocalMedia) async {
        guard item.isVideo else { show("اختر فيديو", .info); return }
        do {
            let asset = AVURLAsset(url: item.url)
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw AppError.message("لا يوجد فيديو") }
            let composition = AVMutableComposition()
            guard let dst = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AppError.message("تعذر تجهيز الفيديو") }
            let duration = try await asset.load(.duration)
            try dst.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
            dst.preferredTransform = try await videoTrack.load(.preferredTransform)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-muted.mp4")
            try? FileManager.default.removeItem(at: tmp)
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw AppError.message("تعذر تجهيز التصدير") }
            export.outputURL = tmp; export.outputFileType = .mp4
            await export.export()
            guard export.status == .completed else { throw export.error ?? AppError.message("فشل التصدير") }
            _ = try persist(tmp, tmp.lastPathComponent); refreshStorage(); show("تم كتم صوت الفيديو", .success)
        } catch { show("تعذر كتم الفيديو", .error) }
    }

    func rotateVideo90(_ item: LocalMedia) async {
        guard item.isVideo else { show("اختر فيديو", .info); return }
        do {
            let asset = AVURLAsset(url: item.url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw AppError.message("لا يوجد فيديو") }
            let composition = AVMutableComposition()
            let duration = try await asset.load(.duration)
            guard let dstV = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AppError.message("تعذر تجهيز الفيديو") }
            try dstV.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
            let natural = try await track.load(.naturalSize)
            let base = try await track.load(.preferredTransform)
            dstV.preferredTransform = base.concatenating(CGAffineTransform(rotationAngle: .pi / 2))
            if let audio = try await asset.loadTracks(withMediaType: .audio).first,
               let dstA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try dstA.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audio, at: .zero)
            }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-rotated.mp4")
            try? FileManager.default.removeItem(at: tmp)
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw AppError.message("تعذر تجهيز التدوير") }
            export.outputURL = tmp; export.outputFileType = .mp4
            await export.export()
            guard export.status == .completed else { throw export.error ?? AppError.message("فشل تدوير الفيديو") }
            _ = natural // keeps the source size loaded and validated
            _ = try persist(tmp, tmp.lastPathComponent); refreshStorage(); show("تم تدوير الفيديو", .success)
        } catch { show("تعذر تدوير الفيديو", .error) }
    }

    func makeRingtone(_ item: LocalMedia) async {
        guard item.isVideo || item.isAudio else { show("اختر فيديو أو صوت", .info); return }
        do {
            let asset = AVURLAsset(url: item.url)
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw AppError.message("تعذر تجهيز النغمة") }
            let full = try await asset.load(.duration)
            export.timeRange = CMTimeRange(start: .zero, duration: CMTimeMinimum(full, CMTime(seconds: 30, preferredTimescale: 600)))
            let m4a = FileManager.default.temporaryDirectory.appendingPathComponent("ring-\(UUID().uuidString).m4a")
            try? FileManager.default.removeItem(at: m4a)
            export.outputURL = m4a; export.outputFileType = .m4a
            await export.export()
            guard export.status == .completed else { throw export.error ?? AppError.message("فشل إنشاء النغمة") }
            let m4r = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-ringtone.m4r")
            try? FileManager.default.removeItem(at: m4r)
            try FileManager.default.moveItem(at: m4a, to: m4r)
            _ = try persist(m4r, m4r.lastPathComponent); refreshStorage(); show("تم إنشاء نغمة 30 ثانية", .success)
        } catch { show("تعذر إنشاء النغمة", .error) }
    }

    func removeImageBackground(_ item: LocalMedia) async {
        guard item.isImage, let ui = UIImage(contentsOfFile: item.url.path), let ci = CIImage(image: ui) else { show("اختر صورة", .info); return }
        do {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: ci)
            try handler.perform([request])
            guard let observation = request.results?.first else { throw AppError.message("لم يتم العثور على عنصر واضح") }
            let maskBuffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
            let mask = CIImage(cvPixelBuffer: maskBuffer)
            let transparent = CIImage(color: .clear).cropped(to: ci.extent)
            guard let filter = CIFilter(name: "CIBlendWithMask") else { throw AppError.message("تعذر تجهيز الخلفية") }
            filter.setValue(ci, forKey: kCIInputImageKey)
            filter.setValue(transparent, forKey: kCIInputBackgroundImageKey)
            filter.setValue(mask, forKey: kCIInputMaskImageKey)
            guard let out = filter.outputImage else { throw AppError.message("تعذر إنشاء الصورة") }
            let context = CIContext()
            guard let cg = context.createCGImage(out, from: out.extent), let data = UIImage(cgImage: cg).pngData() else { throw AppError.message("تعذر حفظ الصورة") }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-no-bg.png")
            try data.write(to: tmp)
            _ = try persist(tmp, tmp.lastPathComponent); refreshStorage(); show("تمت إزالة الخلفية", .success)
        } catch { show("تعذر إزالة الخلفية من هذه الصورة", .error) }
    }

    func showUnsupportedAI(_ title: String) {
        show("\(title) يحتاج نموذج AI منفصل وسيتم ربطه بمحرك محلي/سحابي بدل نتيجة وهمية", .info)
    }
}
