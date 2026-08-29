import Foundation
import SwiftUI
import AVFoundation
import Speech
import Vision
import CoreImage
import UIKit

private struct CaptionV3 { let start: Double; let end: Double; let source: String; let translated: String }
private struct EnergyBlockV3 { let start: Double; let end: Double; let rms: Float }

extension AppModel {
    // MARK: Burned subtitles / bilingual subtitles
    func burnSubtitlesV3(_ item: LocalMedia, target: String = "ar", bilingual: Bool = false) async {
        guard item.isVideo else { show("اختر فيديو", .info); return }
        show("جارٍ إنشاء الترجمة ودمجها…", .info)
        do {
            let captions = try await captionsV3(item, target: target)
            guard !captions.isEmpty else { throw AppError.message("لم أجد كلامًا واضحًا في المقطع") }
            let asset = AVURLAsset(url: item.url)
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw AppError.message("لا يوجد فيديو") }
            let duration = try await asset.load(.duration)
            let natural = try await videoTrack.load(.naturalSize)
            let preferred = try await videoTrack.load(.preferredTransform)
            let rect = CGRect(origin: .zero, size: natural).applying(preferred).standardized
            let render = CGSize(width: abs(rect.width), height: abs(rect.height))
            let composition = AVMutableComposition()
            guard let dstV = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AppError.message("تعذر تجهيز الفيديو") }
            try dstV.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
            if let srcA = try await asset.loadTracks(withMediaType: .audio).first,
               let dstA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try dstA.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: srcA, at: .zero)
            }
            let instruction = AVMutableVideoCompositionInstruction(); instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: dstV)
            layerInstruction.setTransform(preferred.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY)), at: .zero)
            instruction.layerInstructions = [layerInstruction]
            let vc = AVMutableVideoComposition(); vc.renderSize = render; vc.frameDuration = CMTime(value: 1, timescale: 30); vc.instructions = [instruction]
            let videoLayer = CALayer(); videoLayer.frame = CGRect(origin: .zero, size: render)
            let parent = CALayer(); parent.frame = videoLayer.frame; parent.addSublayer(videoLayer)
            for cap in captions {
                let text = bilingual ? "\(cap.source)\n\(cap.translated)" : cap.translated
                let layer = CATextLayer(); layer.string = text; layer.alignmentMode = .center; layer.isWrapped = true
                layer.foregroundColor = UIColor.white.cgColor; layer.backgroundColor = UIColor.black.withAlphaComponent(0.58).cgColor
                layer.cornerRadius = max(8, render.width * 0.015); layer.fontSize = max(24, render.width * 0.045); layer.contentsScale = 2
                let h = bilingual ? render.height * 0.16 : render.height * 0.11
                layer.frame = CGRect(x: render.width * 0.07, y: render.height * 0.07, width: render.width * 0.86, height: h)
                layer.opacity = 0
                let anim = CAKeyframeAnimation(keyPath: "opacity")
                anim.values = [0, 1, 1, 0]; anim.keyTimes = [0, 0.02, 0.98, 1]
                anim.beginTime = AVCoreAnimationBeginTimeAtZero + cap.start; anim.duration = max(0.15, cap.end - cap.start); anim.isRemovedOnCompletion = false; anim.fillMode = .both
                layer.add(anim, forKey: "caption"); parent.addSublayer(layer)
            }
            vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
            let suffix = bilingual ? "bilingual" : "subtitles-\(target)"
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-\(suffix).mp4")
            try? FileManager.default.removeItem(at: out)
            guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw AppError.message("تعذر تجهيز التصدير") }
            exporter.videoComposition = vc; exporter.outputURL = out; exporter.outputFileType = .mp4
            await exporter.export(); guard exporter.status == .completed else { throw exporter.error ?? AppError.message("فشل دمج الترجمة") }
            _ = try persist(out, out.lastPathComponent); refreshStorage(); show("تم إنشاء فيديو مترجم", .success)
        } catch { show(readable(error), .error) }
    }

    // MARK: Smart clips based on audio energy + visual activity
    func smartClipV3(_ item: LocalMedia, count: Int = 3, clipLength: Double = 9) async {
        guard item.isVideo else { show("اختر فيديو", .info); return }
        show("جارٍ تحليل أفضل اللحظات…", .info)
        do {
            let duration = try await AVURLAsset(url: item.url).load(.duration).seconds
            guard duration > clipLength else { throw AppError.message("المقطع قصير ولا يحتاج Smart Clip") }
            let blocks = try await energyBlocksV3(item.url, block: 0.5)
            var candidates: [(Double, Double)] = []
            var t = 0.0
            while t + clipLength <= duration {
                let local = blocks.filter { $0.start >= t && $0.start < t + clipLength }
                let audio = local.isEmpty ? 0 : Double(local.map(\.rms).reduce(0,+) / Float(local.count))
                let visual = try await visualScoreV3(item.url, at: min(duration - 0.1, t + clipLength/2))
                candidates.append((t, audio * 0.75 + visual * 0.25)); t += max(3, clipLength / 2)
            }
            var selected: [Double] = []
            for c in candidates.sorted(by: { $0.1 > $1.1 }) {
                if selected.allSatisfy({ abs($0 - c.0) > clipLength * 0.8 }) { selected.append(c.0) }
                if selected.count >= count { break }
            }
            for (index, start) in selected.sorted().enumerated() {
                let out = try await exportRangeV3(item.url, start: start, duration: min(clipLength, duration-start), suffix: "smart-\(index+1)")
                _ = try persist(out, out.lastPathComponent)
            }
            refreshStorage(); show("تم إنشاء \(selected.count) مقاطع ذكية", .success)
        } catch { show(readable(error), .error) }
    }

    // MARK: Remove silence
    func removeSilenceV3(_ item: LocalMedia) async {
        guard item.isVideo || item.isAudio else { show("اختر فيديو أو صوت", .info); return }
        show("جارٍ اكتشاف الصمت…", .info)
        do {
            let blocks = try await energyBlocksV3(item.url, block: 0.22)
            guard !blocks.isEmpty else { throw AppError.message("تعذر قراءة الصوت") }
            let noise = blocks.map(\.rms).sorted()[max(0, blocks.count/5)]
            let threshold = max(0.006, noise * 2.8)
            var ranges: [(Double, Double)] = []; var open: Double?; var last = 0.0
            for b in blocks {
                let active = b.rms >= threshold
                if active && open == nil { open = max(0, b.start - 0.12) }
                if active { last = b.end + 0.12 }
                if !active, let s = open, b.start - last > 0.45 { ranges.append((s, max(s+0.05,last))); open = nil }
            }
            if let s = open { ranges.append((s, max(s+0.05,last))) }
            guard !ranges.isEmpty else { throw AppError.message("لم أجد مقاطع صوتية واضحة") }
            let asset = AVURLAsset(url: item.url); let composition = AVMutableComposition(); var cursor = CMTime.zero
            if item.isVideo, let srcV = try await asset.loadTracks(withMediaType: .video).first,
               let dstV = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                dstV.preferredTransform = try await srcV.load(.preferredTransform)
                for r in ranges { let range = CMTimeRange(start: CMTime(seconds:r.0, preferredTimescale:600), end: CMTime(seconds:r.1, preferredTimescale:600)); try dstV.insertTimeRange(range, of: srcV, at: cursor); cursor = cursor + range.duration }
            }
            cursor = .zero
            if let srcA = try await asset.loadTracks(withMediaType: .audio).first,
               let dstA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                for r in ranges { let range = CMTimeRange(start: CMTime(seconds:r.0, preferredTimescale:600), end: CMTime(seconds:r.1, preferredTimescale:600)); try dstA.insertTimeRange(range, of: srcA, at: cursor); cursor = cursor + range.duration }
            }
            let ext = item.isVideo ? "mp4" : "m4a"; let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-no-silence.\(ext)")
            try? FileManager.default.removeItem(at: out)
            let preset = item.isVideo ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A
            guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else { throw AppError.message("تعذر التصدير") }
            exporter.outputURL = out; exporter.outputFileType = item.isVideo ? .mp4 : .m4a
            await exporter.export(); guard exporter.status == .completed else { throw exporter.error ?? AppError.message("فشل إزالة الصمت") }
            _ = try persist(out, out.lastPathComponent); refreshStorage(); show("تم حذف فترات الصمت", .success)
        } catch { show(readable(error), .error) }
    }

    // MARK: Subject-aware 9:16 reframing
    func autoReframeV3(_ item: LocalMedia) async {
        guard item.isVideo else { show("اختر فيديو", .info); return }
        show("جارٍ تتبع الشخص وإعادة التأطير…", .info)
        do {
            let asset = AVURLAsset(url: item.url); let duration = try await asset.load(.duration).seconds
            guard let srcV = try await asset.loadTracks(withMediaType: .video).first else { throw AppError.message("لا يوجد فيديو") }
            let natural = try await srcV.load(.naturalSize); let preferred = try await srcV.load(.preferredTransform)
            let orientedRect = CGRect(origin:.zero,size:natural).applying(preferred).standardized
            let sourceSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
            let targetRatio = 9.0/16.0; let cropWidth = min(sourceSize.width, sourceSize.height * targetRatio)
            let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width:720,height:720)
            var centers: [(Double, CGFloat)] = []; var sec = 0.0; var previous = sourceSize.width/2
            while sec < duration {
                let cg = try await generator.image(at: CMTime(seconds:min(duration-0.05,sec),preferredTimescale:600)).image
                let centerNorm = subjectCenterV3(cg) ?? 0.5
                let desired = CGFloat(centerNorm) * sourceSize.width
                previous = previous * 0.68 + desired * 0.32
                centers.append((sec, previous)); sec += 0.8
            }
            let composition = AVMutableComposition(); let full = try await asset.load(.duration)
            guard let dstV = composition.addMutableTrack(withMediaType:.video, preferredTrackID:kCMPersistentTrackID_Invalid) else { throw AppError.message("تعذر تجهيز الفيديو") }
            try dstV.insertTimeRange(CMTimeRange(start:.zero,duration:full),of:srcV,at:.zero)
            if let srcA = try await asset.loadTracks(withMediaType:.audio).first, let dstA = composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid){try dstA.insertTimeRange(CMTimeRange(start:.zero,duration:full),of:srcA,at:.zero)}
            var instructions:[AVVideoCompositionInstructionProtocol]=[]
            for i in centers.indices {
                let start = centers[i].0, end = i+1 < centers.count ? centers[i+1].0 : duration
                let ins = AVMutableVideoCompositionInstruction(); ins.timeRange = CMTimeRange(start:CMTime(seconds:start,preferredTimescale:600),duration:CMTime(seconds:max(0.05,end-start),preferredTimescale:600))
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack:dstV)
                let x = max(0,min(sourceSize.width-cropWidth,centers[i].1-cropWidth/2))
                let normalize = preferred.concatenating(CGAffineTransform(translationX:-orientedRect.minX,y:-orientedRect.minY)).concatenating(CGAffineTransform(translationX:-x,y:0))
                layer.setTransform(normalize,at:ins.timeRange.start); ins.layerInstructions=[layer]; instructions.append(ins)
            }
            let vc=AVMutableVideoComposition(); vc.instructions=instructions; vc.renderSize=CGSize(width:floor(cropWidth/2)*2,height:floor(sourceSize.height/2)*2); vc.frameDuration=CMTime(value:1,timescale:30)
            let out=FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-reframe-9x16.mp4");try? FileManager.default.removeItem(at:out)
            guard let exporter=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality)else{throw AppError.message("تعذر التصدير")};exporter.videoComposition=vc;exporter.outputURL=out;exporter.outputFileType=.mp4
            await exporter.export();guard exporter.status == .completed else{throw exporter.error ?? AppError.message("فشل إعادة التأطير")};_=try persist(out,out.lastPathComponent);refreshStorage();show("تم إنشاء نسخة 9:16 تتبع الشخص",.success)
        }catch{show(readable(error),.error)}
    }

    // MARK: Audio cleanup: high-pass, noise gate and peak normalization
    func cleanAudioV3(_ item: LocalMedia) async {
        guard item.isVideo || item.isAudio else { show("اختر فيديو أو صوت", .info); return }
        show("جارٍ تنظيف الصوت…", .info)
        do {
            let source = try await audioSourceV3(item)
            let cleaned = try processAudioDSPV3(source, speechBoost: false)
            defer { if source != item.url { try? FileManager.default.removeItem(at: source) }; try? FileManager.default.removeItem(at: cleaned) }
            if item.isVideo {
                let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-clean-audio.mp4")
                try await remuxAudioV3(video:item.url,audio:cleaned,out:out); _ = try persist(out,out.lastPathComponent)
            } else {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-clean.wav"); try FileManager.default.copyItem(at:cleaned,to:tmp); _ = try persist(tmp,tmp.lastPathComponent)
            }
            refreshStorage(); show("تم تنظيف الضوضاء والهمهمة",.success)
        } catch { show(readable(error), .error) }
    }

    // MARK: Speech boost using real Demucs vocal stem mixed over original
    func boostSpeechV3(_ item: LocalMedia) async {
        guard item.isVideo || item.isAudio else { show("اختر فيديو أو صوت", .info); return }
        show("جارٍ رفع وضوح الكلام…", .info)
        do {
            let sourceAudio = try await audioSourceV3(item); defer { if sourceAudio != item.url { try? FileManager.default.removeItem(at: sourceAudio) } }
            let vm = DemucsViewModel(); vm.audioURL = sourceAudio; try await vm.performSeparation(mode:.full)
            guard let vocal = vm.stemURLs[.vocals] else { throw AppError.message("تعذر استخراج مسار الكلام") }
            let mixed = try await mixOriginalAndVoiceV3(original:sourceAudio,vocal:vocal)
            defer { try? FileManager.default.removeItem(at:mixed) }
            if item.isVideo {
                let out=FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-speech-boost.mp4");try await remuxAudioV3(video:item.url,audio:mixed,out:out);_=try persist(out,out.lastPathComponent)
            } else { let out=FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-speech-boost.m4a");try FileManager.default.copyItem(at:mixed,to:out);_=try persist(out,out.lastPathComponent) }
            refreshStorage();show("تم رفع صوت الكلام مع إبقاء الموسيقى",.success)
        }catch{show(readable(error),.error)}
    }

    // MARK: Thumbnail maker
    func thumbnailMakerV3(_ item: LocalMedia) async {
        guard item.isVideo else { show("اختر فيديو", .info); return }
        show("جارٍ اختيار أفضل اللقطات…", .info)
        do {
            let asset=AVURLAsset(url:item.url);let duration=try await asset.load(.duration).seconds;let gen=AVAssetImageGenerator(asset:asset);gen.appliesPreferredTrackTransform=true;gen.maximumSize=CGSize(width:1000,height:1000)
            var scored:[(Double,UIImage)]=[]
            for i in 0..<18 { let t=max(0.01,duration*Double(i+1)/19);let cg=try await gen.image(at:CMTime(seconds:t,preferredTimescale:600)).image;let ui=UIImage(cgImage:cg);let faces=faceCountV3(cg);let contrast=contrastScoreV3(ui);scored.append((Double(faces)*2.5+contrast,ui)) }
            let best=Array(scored.sorted{$0.0>$1.0}.prefix(6));guard !best.isEmpty else{throw AppError.message("تعذر استخراج اللقطات")}
            for (i,pair) in best.enumerated(){guard let data=pair.1.jpegData(compressionQuality:0.94)else{continue};let tmp=FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-cover-\(i+1).jpg");try data.write(to:tmp);_=try persist(tmp,tmp.lastPathComponent)}
            refreshStorage();show("تم إنشاء 6 اقتراحات للغلاف",.success)
        }catch{show(readable(error),.error)}
    }

    // MARK: Visual duplicate finder (perceptual hash)
    func removeVisualDuplicatesV3() async {
        show("جارٍ فحص التشابه البصري…", .info)
        var seen:[UInt64:LocalMedia]=[:];var duplicates:[LocalMedia]=[]
        for item in library where item.isImage || item.isVideo {
            guard let hash=await perceptualHashV3(item) else{continue}
            if let match=seen.first(where:{hammingV3($0.key,hash)<=6 && abs($0.value.size-item.size) < max(2_000_000, item.size/3)}) { duplicates.append(item); _=match }
            else { seen[hash]=item }
        }
        duplicates.forEach{moveToTrash($0)};refreshStorage();show(duplicates.isEmpty ? "لا توجد ملفات متشابهة بصريًا" : "تم نقل \(duplicates.count) ملف متشابه للسلة",.success)
    }

    // MARK: Smart sharing presets
    func smartShareV3(_ item: LocalMedia, preset: SmartSharePreset) async throws -> URL {
        guard item.isVideo else { return item.url }
        let asset=AVURLAsset(url:item.url);let presetName:String
        switch preset { case .snapchat: presetName=AVAssetExportPreset1280x720; case .whatsapp: presetName=AVAssetExportPreset960x540; case .x: presetName=AVAssetExportPreset1920x1080 }
        guard let exporter=AVAssetExportSession(asset:asset,presetName:presetName)else{throw AppError.message("تعذر تجهيز المشاركة")}
        let out=FileManager.default.temporaryDirectory.appendingPathComponent("share-\(preset.rawValue)-\(UUID().uuidString).mp4");exporter.outputURL=out;exporter.outputFileType=.mp4;exporter.metadata=[]
        await exporter.export();guard exporter.status == .completed else{throw exporter.error ?? AppError.message("تعذر تجهيز الملف")};return out
    }

    // MARK: Helpers
    private func captionsV3(_ item:LocalMedia,target:String) async throws->[CaptionV3]{
        let auth=await withCheckedContinuation{c in SFSpeechRecognizer.requestAuthorization{c.resume(returning:$0)}};guard auth == .authorized else{throw AppError.message("اسمح بالتعرف على الكلام")}
        let audio=try await audioSourceV3(item);defer{if audio != item.url{try? FileManager.default.removeItem(at:audio)}};let duration=try await AVURLAsset(url:audio).load(.duration).seconds
        let probe=min(18.0,duration);let probeURL=try await exportAudioChunkV3(audio,start:0,duration:probe);defer{try? FileManager.default.removeItem(at:probeURL)}
        let locales=[Locale(identifier:"en-US"),Locale(identifier:"ar-SA")];var bestLocale=locales[0];var bestCount=0
        for l in locales{if let r=try? await recognizeV3(probeURL,locale:l),r.bestTranscription.formattedString.count>bestCount{bestCount=r.bestTranscription.formattedString.count;bestLocale=l}}
        var output:[CaptionV3]=[];var start=0.0
        while start < duration-0.05{let len=min(19.0,duration-start);let chunk=try await exportAudioChunkV3(audio,start:start,duration:len);defer{try? FileManager.default.removeItem(at:chunk)}
            if let result=try? await recognizeV3(chunk,locale:bestLocale){var words:[SFTranscriptionSegment]=[]
                for seg in result.bestTranscription.segments{words.append(seg);if words.count>=9 || ((words.last?.timestamp ?? 0)+(words.last?.duration ?? 0)-(words.first?.timestamp ?? 0)>3.8){let s=start+(words.first?.timestamp ?? 0);let e=start+(words.last.map{$0.timestamp+$0.duration} ?? 0);let text=words.map(\.substring).joined(separator:" ");let tr=try await translateV3(text,target:target);output.append(CaptionV3(start:s,end:max(s+0.2,e),source:text,translated:tr));words=[]}}
                if !words.isEmpty{let s=start+(words.first?.timestamp ?? 0);let e=start+(words.last.map{$0.timestamp+$0.duration} ?? 0);let text=words.map(\.substring).joined(separator:" ");let tr=try await translateV3(text,target:target);output.append(CaptionV3(start:s,end:max(s+0.2,e),source:text,translated:tr))}}
            start += len
        }
        return output
    }

    private func recognizeV3(_ url:URL,locale:Locale) async throws->SFSpeechRecognitionResult{guard let r=SFSpeechRecognizer(locale:locale),r.isAvailable else{throw AppError.message("التعرف على الكلام غير متاح")};let req=SFSpeechURLRecognitionRequest(url:url);req.shouldReportPartialResults=false;req.taskHint=.dictation;return try await withCheckedThrowingContinuation{c in var done=false;_ = r.recognitionTask(with:req){res,err in if done{return};if let res,res.isFinal{done=true;c.resume(returning:res)}else if let err{done=true;c.resume(throwing:err)}}}}
    private func translateV3(_ text:String,target:String) async throws->String{guard target=="ar" || target=="en" else{return text};var comps=URLComponents(string:"https://translate.googleapis.com/translate_a/single")!;comps.queryItems=[.init(name:"client",value:"gtx"),.init(name:"sl",value:"auto"),.init(name:"tl",value:target),.init(name:"dt",value:"t"),.init(name:"q",value:text)];var req=URLRequest(url:comps.url!);req.timeoutInterval=18;let(data,response)=try await URLSession.shared.data(for:req);guard let h=response as? HTTPURLResponse,(200..<300).contains(h.statusCode),let root=try JSONSerialization.jsonObject(with:data) as? [Any],let rows=root.first as? [Any] else{throw AppError.message("تعذر الترجمة")};let out=rows.compactMap{($0 as? [Any])?.first as? String}.joined();return out.isEmpty ? text:out}
    private func audioSourceV3(_ item:LocalMedia) async throws->URL{guard item.isVideo else{return item.url};let asset=AVURLAsset(url:item.url);guard let ex=AVAssetExportSession(asset:asset,presetName:AVAssetExportPresetAppleM4A)else{throw AppError.message("تعذر استخراج الصوت")};let out=FileManager.default.temporaryDirectory.appendingPathComponent("audio-\(UUID().uuidString).m4a");ex.outputURL=out;ex.outputFileType=.m4a;await ex.export();guard ex.status == .completed else{throw ex.error ?? AppError.message("تعذر استخراج الصوت")};return out}
    private func exportAudioChunkV3(_ source:URL,start:Double,duration:Double) async throws->URL{let asset=AVURLAsset(url:source);guard let ex=AVAssetExportSession(asset:asset,presetName:AVAssetExportPresetAppleM4A)else{throw AppError.message("تعذر تجهيز الصوت")};let out=FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID().uuidString).m4a");ex.timeRange=CMTimeRange(start:CMTime(seconds:start,preferredTimescale:600),duration:CMTime(seconds:duration,preferredTimescale:600));ex.outputURL=out;ex.outputFileType=.m4a;await ex.export();guard ex.status == .completed else{throw ex.error ?? AppError.message("تعذر تجهيز جزء الصوت")};return out}
    private func exportRangeV3(_ source:URL,start:Double,duration:Double,suffix:String) async throws->URL{let asset=AVURLAsset(url:source);guard let ex=AVAssetExportSession(asset:asset,presetName:AVAssetExportPresetHighestQuality)else{throw AppError.message("تعذر تجهيز القص")};let out=FileManager.default.temporaryDirectory.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(suffix).mp4");try? FileManager.default.removeItem(at:out);ex.timeRange=CMTimeRange(start:CMTime(seconds:start,preferredTimescale:600),duration:CMTime(seconds:duration,preferredTimescale:600));ex.outputURL=out;ex.outputFileType=.mp4;await ex.export();guard ex.status == .completed else{throw ex.error ?? AppError.message("فشل القص")};return out}

    private func energyBlocksV3(_ source:URL,block:Double) async throws->[EnergyBlockV3]{let asset=AVURLAsset(url:source);guard let track=try await asset.loadTracks(withMediaType:.audio).first else{throw AppError.message("لا يوجد صوت")};let reader=try AVAssetReader(asset:asset);let settings:[String:Any]=[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMIsFloatKey:true,AVLinearPCMBitDepthKey:32,AVLinearPCMIsNonInterleaved:false,AVSampleRateKey:16000,AVNumberOfChannelsKey:1];let out=AVAssetReaderTrackOutput(track:track,outputSettings:settings);reader.add(out);guard reader.startReading()else{throw reader.error ?? AppError.message("تعذر قراءة الصوت")};let samplesPer=max(1,Int(16000*block));var sum:Double=0;var count=0;var index=0;var blocks:[EnergyBlockV3]=[]
        while let sample=out.copyNextSampleBuffer(){guard let bb=CMSampleBufferGetDataBuffer(sample)else{continue};let length=CMBlockBufferGetDataLength(bb);var data=Data(count:length);data.withUnsafeMutableBytes{raw in if let b=raw.baseAddress{CMBlockBufferCopyDataBytes(bb,atOffset:0,dataLength:length,destination:b)}};data.withUnsafeBytes{raw in for v in raw.bindMemory(to:Float.self){let x=Double(v);sum+=x*x;count+=1;if count>=samplesPer{let rms=Float(sqrt(sum/Double(count)));let s=Double(index)*block;blocks.append(.init(start:s,end:s+block,rms:rms));index+=1;sum=0;count=0}}}}
        if count>0{let s=Double(index)*block;blocks.append(.init(start:s,end:s+block,rms:Float(sqrt(sum/Double(count)))))};return blocks}

    private func visualScoreV3(_ source:URL,at time:Double) async throws->Double{let gen=AVAssetImageGenerator(asset:AVURLAsset(url:source));gen.appliesPreferredTrackTransform=true;gen.maximumSize=CGSize(width:320,height:320);let cg=try await gen.image(at:CMTime(seconds:time,preferredTimescale:600)).image;return Double(faceCountV3(cg))*0.8+contrastScoreV3(UIImage(cgImage:cg))}
    private func subjectCenterV3(_ cg:CGImage)->Double?{let req=VNDetectHumanRectanglesRequest();req.upperBodyOnly=false;let face=VNDetectFaceRectanglesRequest();let h=VNImageRequestHandler(cgImage:cg);try? h.perform([req,face]);if let r=req.results?.max(by:{$0.boundingBox.width*$0.boundingBox.height<$1.boundingBox.width*$1.boundingBox.height})?.boundingBox{return Double(r.midX)};if let r=face.results?.max(by:{$0.boundingBox.width*$0.boundingBox.height<$1.boundingBox.width*$1.boundingBox.height})?.boundingBox{return Double(r.midX)};return nil}
    private func faceCountV3(_ cg:CGImage)->Int{let req=VNDetectFaceRectanglesRequest();let h=VNImageRequestHandler(cgImage:cg);try? h.perform([req]);return req.results?.count ?? 0}
    private func contrastScoreV3(_ image:UIImage)->Double{guard let ci=CIImage(image:image),let f=CIFilter(name:"CIAreaAverage")else{return 0};f.setValue(ci,forKey:kCIInputImageKey);f.setValue(CIVector(cgRect:ci.extent),forKey:kCIInputExtentKey);guard let out=f.outputImage else{return 0};var px=[UInt8](repeating:0,count:4);CIContext().render(out,toBitmap:&px,rowBytes:4,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBA8,colorSpace:nil);let avg=(Double(px[0])+Double(px[1])+Double(px[2]))/765.0;return 1-abs(avg-0.52)}

    private func processAudioDSPV3(_ source:URL,speechBoost:Bool) throws->URL{let file=try AVAudioFile(forReading:source);let format=file.processingFormat;let frames=AVAudioFrameCount(file.length);guard let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:frames)else{throw AppError.message("تعذر تجهيز الصوت")};try file.read(into:buffer);guard let data=buffer.floatChannelData else{throw AppError.message("صيغة الصوت غير مدعومة")};let ch=Int(format.channelCount),n=Int(buffer.frameLength);var peak:Float=0;for c in 0..<ch{var prevX:Float=0,prevY:Float=0;for i in 0..<n{let x=data[c][i];let y=0.985*(prevY+x-prevX);prevX=x;prevY=y;let gated=abs(y)<0.004 ? y*0.18:y;data[c][i]=gated;peak=max(peak,abs(gated))}};let gain=peak>0 ? min(4.0,0.92/peak):1;for c in 0..<ch{for i in 0..<n{data[c][i]*=gain}};let out=FileManager.default.temporaryDirectory.appendingPathComponent("clean-\(UUID().uuidString).wav");let writer=try AVAudioFile(forWriting:out,settings:format.settings);try writer.write(from:buffer);return out}
    private func remuxAudioV3(video:URL,audio:URL,out:URL) async throws{let va=AVURLAsset(url:video),aa=AVURLAsset(url:audio);guard let vsrc=try await va.loadTracks(withMediaType:.video).first,let asrc=try await aa.loadTracks(withMediaType:.audio).first else{throw AppError.message("تعذر تجهيز المسارات")};let comp=AVMutableComposition();let vd=try await va.load(.duration),ad=try await aa.load(.duration),d=CMTimeMinimum(vd,ad);guard let v=comp.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid),let a=comp.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)else{throw AppError.message("تعذر تجهيز المسارات")};try v.insertTimeRange(CMTimeRange(start:.zero,duration:d),of:vsrc,at:.zero);v.preferredTransform=try await vsrc.load(.preferredTransform);try a.insertTimeRange(CMTimeRange(start:.zero,duration:d),of:asrc,at:.zero);try? FileManager.default.removeItem(at:out);guard let ex=AVAssetExportSession(asset:comp,presetName:AVAssetExportPresetHighestQuality)else{throw AppError.message("تعذر التصدير")};ex.outputURL=out;ex.outputFileType=.mp4;await ex.export();guard ex.status == .completed else{throw ex.error ?? AppError.message("فشل التصدير")}}
    private func mixOriginalAndVoiceV3(original:URL,vocal:URL) async throws->URL{let oa=AVURLAsset(url:original),va=AVURLAsset(url:vocal);guard let ot=try await oa.loadTracks(withMediaType:.audio).first,let vt=try await va.loadTracks(withMediaType:.audio).first else{throw AppError.message("تعذر تجهيز الصوت")};let comp=AVMutableComposition();let od=try await oa.load(.duration),vd=try await va.load(.duration),d=CMTimeMinimum(od,vd);guard let o=comp.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid),let v=comp.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)else{throw AppError.message("تعذر تجهيز الصوت")};try o.insertTimeRange(CMTimeRange(start:.zero,duration:d),of:ot,at:.zero);try v.insertTimeRange(CMTimeRange(start:.zero,duration:d),of:vt,at:.zero);let p1=AVMutableAudioMixInputParameters(track:o);p1.setVolume(0.88,at:.zero);let p2=AVMutableAudioMixInputParameters(track:v);p2.setVolume(0.72,at:.zero);let mix=AVMutableAudioMix();mix.inputParameters=[p1,p2];let out=FileManager.default.temporaryDirectory.appendingPathComponent("speechmix-\(UUID().uuidString).m4a");guard let ex=AVAssetExportSession(asset:comp,presetName:AVAssetExportPresetAppleM4A)else{throw AppError.message("تعذر دمج الصوت")};ex.audioMix=mix;ex.outputURL=out;ex.outputFileType=.m4a;await ex.export();guard ex.status == .completed else{throw ex.error ?? AppError.message("فشل دمج الصوت")};return out}
    private func perceptualHashV3(_ item:LocalMedia) async->UInt64?{var image:UIImage?;if item.isImage{image=UIImage(contentsOfFile:item.url.path)}else if item.isVideo{let g=AVAssetImageGenerator(asset:AVURLAsset(url:item.url));g.appliesPreferredTrackTransform=true;g.maximumSize=CGSize(width:64,height:64);if let cg=try? await g.image(at:CMTime(seconds:0.5,preferredTimescale:600)).image{image=UIImage(cgImage:cg)}};guard let image,let cg=image.cgImage else{return nil};let w=9,h=8;var px=[UInt8](repeating:0,count:w*h);guard let ctx=CGContext(data:&px,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue)else{return nil};ctx.draw(cg,in:CGRect(x:0,y:0,width:w,height:h));var hash:UInt64=0;var bit=0;for y in 0..<h{for x in 0..<8{if px[y*w+x]>px[y*w+x+1]{hash|=(1<<UInt64(bit))};bit+=1}};return hash}
    private func hammingV3(_ a:UInt64,_ b:UInt64)->Int{Int((a^b).nonzeroBitCount)}
}
