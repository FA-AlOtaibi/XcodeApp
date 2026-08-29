import SwiftUI
import AVFoundation
import UIKit

extension AppModel {
    func extractAudio(from item: LocalMedia) async {
        guard item.isVideo else { show("هذه الميزة للفيديو فقط", .info); return }
        do {
            let asset = AVURLAsset(url: item.url)
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw AppError.message("تعذر تجهيز الصوت") }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-audio.m4a")
            try? FileManager.default.removeItem(at: tmp)
            export.outputURL = tmp
            export.outputFileType = .m4a
            await export.export()
            guard export.status == .completed else { throw export.error ?? AppError.message("فشل استخراج الصوت") }
            _ = try persist(tmp, tmp.lastPathComponent)
            refreshStorage(); show("تم استخراج الصوت", .success)
        } catch { show("تعذر استخراج الصوت", .error) }
    }

    func compress720(from item: LocalMedia) async {
        guard item.isVideo else { show("هذه الميزة للفيديو فقط", .info); return }
        do {
            let asset = AVURLAsset(url: item.url)
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { throw AppError.message("تعذر تجهيز الضغط") }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-720p.mp4")
            try? FileManager.default.removeItem(at: tmp)
            export.outputURL = tmp
            export.outputFileType = .mp4
            await export.export()
            guard export.status == .completed else { throw export.error ?? AppError.message("فشل الضغط") }
            _ = try persist(tmp, tmp.lastPathComponent)
            refreshStorage(); show("تم إنشاء نسخة أخف", .success)
        } catch { show("تعذر ضغط الفيديو", .error) }
    }

    func privacyCleanCopy(from item: LocalMedia) async {
        do {
            if item.isImage {
                guard let image = UIImage(contentsOfFile: item.url.path), let data = image.jpegData(compressionQuality: 0.94) else { throw AppError.message("تعذر قراءة الصورة") }
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-clean.jpg")
                try data.write(to: tmp)
                _ = try persist(tmp, tmp.lastPathComponent)
            } else if item.isVideo {
                let asset = AVURLAsset(url: item.url)
                guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { throw AppError.message("تعذر تجهيز الفيديو") }
                export.metadata = []
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-clean.mp4")
                try? FileManager.default.removeItem(at: tmp)
                export.outputURL = tmp; export.outputFileType = .mp4
                await export.export()
                guard export.status == .completed else { throw export.error ?? AppError.message("فشل التنظيف") }
                _ = try persist(tmp, tmp.lastPathComponent)
            } else { show("التنظيف متاح للصور والفيديو", .info); return }
            refreshStorage(); show("تم إنشاء نسخة بدون بيانات وصفية", .success)
        } catch { show("تعذر تنظيف الملف", .error) }
    }

    func contactSheet(from item: LocalMedia) async {
        guard item.isVideo else { show("هذه الميزة للفيديو فقط", .info); return }
        do {
            let asset = AVURLAsset(url: item.url)
            let duration = try await asset.load(.duration).seconds
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 520, height: 520)
            var images: [UIImage] = []
            for i in 0..<9 {
                let second = max(0, duration * Double(i + 1) / 10.0)
                let result = try await generator.image(at: CMTime(seconds: second, preferredTimescale: 600)).image
                images.append(UIImage(cgImage: result))
            }
            let cell = CGSize(width: 360, height: 360)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: cell.width * 3, height: cell.height * 3))
            let sheet = renderer.image { _ in
                UIColor.black.setFill(); UIRectFill(CGRect(origin: .zero, size: CGSize(width: cell.width * 3, height: cell.height * 3)))
                for (index, image) in images.enumerated() {
                    let row = index / 3, col = index % 3
                    let rect = CGRect(x: CGFloat(col) * cell.width, y: CGFloat(row) * cell.height, width: cell.width, height: cell.height)
                    image.draw(in: rect.insetBy(dx: 2, dy: 2))
                }
            }
            guard let data = sheet.jpegData(compressionQuality: 0.9) else { throw AppError.message("تعذر إنشاء اللوحة") }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-frames.jpg")
            try data.write(to: tmp); _ = try persist(tmp, tmp.lastPathComponent)
            refreshStorage(); show("تم إنشاء لوحة 9 لقطات", .success)
        } catch { show("تعذر إنشاء اللقطات", .error) }
    }

    func grabMiddleFrame(from item: LocalMedia) async {
        guard item.isVideo else { return }
        do {
            let asset = AVURLAsset(url: item.url)
            let duration = try await asset.load(.duration).seconds
            let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
            let cg = try await generator.image(at: CMTime(seconds: duration / 2, preferredTimescale: 600)).image
            guard let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.95) else { throw AppError.message("تعذر استخراج اللقطة") }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-frame.jpg")
            try data.write(to: tmp); _ = try persist(tmp, tmp.lastPathComponent)
            refreshStorage(); show("تم حفظ لقطة من منتصف الفيديو", .success)
        } catch { show("تعذر استخراج اللقطة", .error) }
    }

    func autoRename(_ item: LocalMedia) {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let kind = item.isVideo ? "Video" : item.isImage ? "Photo" : item.isAudio ? "Audio" : "File"
        renameLocal(item, to: "\(kind)_\(formatter.string(from: item.createdAt))")
    }
}

struct MediaLabView: View {
    @ObservedObject var model: AppModel
    @State private var selected: LocalMedia?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("المعمل").font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("أدوات سريعة تعمل على جهازك بدون رفع ملفاتك").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)

                    if let selected {
                        LocalThumb(item: selected).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 24))
                        HStack { Text(selected.url.deletingPathExtension().lastPathComponent).font(.headline).lineLimit(1); Spacer(); Button("تغيير") { self.selected = nil } }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            LabAction(title: "استخراج الصوت", icon: "waveform", enabled: selected.isVideo) { run { await model.extractAudio(from: selected) } }
                            LabAction(title: "نسخة 720p", icon: "arrow.down.right.and.arrow.up.left", enabled: selected.isVideo) { run { await model.compress720(from: selected) } }
                            LabAction(title: "تنظيف الخصوصية", icon: "shield.lefthalf.filled", enabled: selected.isVideo || selected.isImage) { run { await model.privacyCleanCopy(from: selected) } }
                            LabAction(title: "لقطة وسطية", icon: "photo", enabled: selected.isVideo) { run { await model.grabMiddleFrame(from: selected) } }
                            LabAction(title: "لوحة 9 لقطات", icon: "square.grid.3x3", enabled: selected.isVideo) { run { await model.contactSheet(from: selected) } }
                            LabAction(title: "اسم مرتب", icon: "textformat", enabled: true) { model.autoRename(selected) }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "wand.and.stars.inverse").font(.system(size: 46)).foregroundStyle(.secondary)
                            Text("اختر ملفًا من مكتبتك").font(.headline)
                            Text("الصوت، الضغط، تنظيف البيانات، استخراج اللقطات والمزيد").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.padding(.vertical, 34)
                        ForEach(model.library.prefix(12)) { item in
                            Button { selected = item } label: { CompactMediaRow(item: item, model: model) }.buttonStyle(.plain)
                        }
                    }
                    if busy { ProgressView("جارٍ تنفيذ العملية…").padding(.top, 8) }
                }.padding(20)
            }.navigationTitle("المعمل").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func run(_ op: @escaping () async -> Void) { busy = true; Task { await op(); busy = false } }
}

struct LabAction: View {
    let title: String; let icon: String; let enabled: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(16).frame(minHeight: 104).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35)
    }
}
