import SwiftUI
import AVFoundation
import Speech
import CoreMedia
import CoreVideo
import SwiftMP3

extension AppModel {
    func translateVideoToSRT(_ item: LocalMedia, targetLanguage: String) async {
        guard item.isVideo || item.isAudio else { show("اختر فيديو أو ملف صوتي", .info); return }
        do {
            let auth = await speechAuthorization()
            guard auth == .authorized else { throw AppError.message("يلزم السماح بالتعرف على الكلام") }
            let candidates = [Locale(identifier: "ar-SA"), Locale(identifier: "en-US")]
            var best: SFSpeechRecognitionResult?
            for locale in candidates {
                if let r = try? await recognizeSpeech(item.url, locale: locale),
                   best == nil || r.bestTranscription.formattedString.count > (best?.bestTranscription.formattedString.count ?? 0) { best = r }
            }
            guard let result = best, !result.bestTranscription.segments.isEmpty else { throw AppError.message("لم أتمكن من التعرف على الكلام") }
            let groups = subtitleGroups(result.bestTranscription.segments)
            var srt = ""
            for (index, g) in groups.enumerated() {
                let translated = try await translateText(g.text, to: targetLanguage)
                srt += "\(index + 1)\n\(srtTime(g.start)) --> \(srtTime(g.end))\n\(translated)\n\n"
            }
            let lang = targetLanguage == "ar" ? "ar" : "en"
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-\(lang).srt")
            try srt.write(to: tmp, atomically: true, encoding: .utf8)
            _ = try persist(tmp, tmp.lastPathComponent)
            refreshStorage(); show("تم إنشاء ترجمة SRT", .success)
        } catch { show(error is AppError ? readable(error) : "تعذر ترجمة الفيديو", .error) }
    }

    private func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
    }

    private func recognizeSpeech(_ url: URL, locale: Locale) async throws -> SFSpeechRecognitionResult {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { throw AppError.message("التعرف على الكلام غير متاح") }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let error, !finished { finished = true; continuation.resume(throwing: error) }
                else if let result, result.isFinal, !finished { finished = true; continuation.resume(returning: result) }
            }
        }
    }

    private struct SubtitleGroup { let start: Double; let end: Double; let text: String }
    private func subtitleGroups(_ segments: [SFTranscriptionSegment]) -> [SubtitleGroup] {
        var output:[SubtitleGroup]=[]; var start=0.0; var end=0.0; var words:[String]=[]
        for seg in segments {
            if words.isEmpty { start = seg.timestamp }
            words.append(seg.substring); end = seg.timestamp + seg.duration
            if end-start >= 4.2 || words.count >= 10 { output.append(.init(start:start,end:end,text:words.joined(separator:" "))); words.removeAll(keepingCapacity:true) }
        }
        if !words.isEmpty { output.append(.init(start:start,end:end,text:words.joined(separator:" "))) }
        return output
    }

    private func translateText(_ text:String,to target:String) async throws -> String {
        guard var parts = URLComponents(string:"https://translate.googleapis.com/translate_a/single") else { return text }
        parts.queryItems = [URLQueryItem(name:"client",value:"gtx"),URLQueryItem(name:"sl",value:"auto"),URLQueryItem(name:"tl",value:target),URLQueryItem(name:"dt",value:"t"),URLQueryItem(name:"q",value:text)]
        guard let url=parts.url else{return text}; var req=URLRequest(url:url); req.timeoutInterval=20
        let (data,response)=try await URLSession.shared.data(for:req)
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode),let json=try JSONSerialization.jsonObject(with:data) as? [Any],let rows=json.first as? [Any] else{return text}
        let translated=rows.compactMap{($0 as? [Any])?.first as? String}.joined(); return translated.isEmpty ? text:translated
    }

    private func srtTime(_ value:Double)->String { let ms=max(0,Int(value*1000)); return String(format:"%02d:%02d:%02d,%03d",ms/3_600_000,(ms/60_000)%60,(ms/1000)%60,ms%1000) }

    func convertToMP3(_ item:LocalMedia) async {
        guard item.isVideo || item.isAudio else { show("اختر فيديو أو ملف صوتي",.info); return }
        do {
            let asset=AVURLAsset(url:item.url)
            guard let track=try await asset.loadTracks(withMediaType:.audio).first else{throw AppError.message("لا يوجد صوت في الملف")}
            let reader=try AVAssetReader(asset:asset)
            let settings:[String:Any]=[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMIsFloatKey:true,AVLinearPCMBitDepthKey:32,AVLinearPCMIsNonInterleaved:false,AVSampleRateKey:44_100,AVNumberOfChannelsKey:2]
            let output=AVAssetReaderTrackOutput(track:track,outputSettings:settings); guard reader.canAdd(output) else{throw AppError.message("تعذر تجهيز الصوت")}; reader.add(output); guard reader.startReading() else{throw reader.error ?? AppError.message("تعذر قراءة الصوت")}
            let encoder=MP3Encoder(options:MP3EncoderOptions(sampleRate:44_100,bitrateKbps:192,mode:.stereo,quality:3)); var session=encoder.newSession(); var encoded=Data()
            while reader.status == .reading, let sample=output.copyNextSampleBuffer(){ guard let block=CMSampleBufferGetDataBuffer(sample) else{continue}; let length=CMBlockBufferGetDataLength(block); var bytes=Data(count:length); let status=bytes.withUnsafeMutableBytes{raw in CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:length,destination:raw.baseAddress!)}; guard status==kCMBlockBufferNoErr else{continue}; let floats:[Float]=bytes.withUnsafeBytes{Array($0.bindMemory(to:Float.self))}; encoded.append(session.encode(samples:floats)) }
            encoded.append(session.flush()); var final=Data(); final.append(session.generateXingHeader()); final.append(encoded)
            let tmp=FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent).mp3"); try final.write(to:tmp,options:.atomic); _=try persist(tmp,tmp.lastPathComponent); refreshStorage(); show("تم التحويل إلى MP3",.success)
        } catch { show("تعذر التحويل إلى MP3",.error) }
    }

    func reverseVideo(_ item:LocalMedia) async {
        guard item.isVideo else{show("اختر فيديو",.info);return}
        do {
            let asset=AVURLAsset(url:item.url); let duration=try await asset.load(.duration).seconds; guard duration>0,duration<=180 else{throw AppError.message("العكس متاح للمقاطع حتى 3 دقائق")}
            let generator=AVAssetImageGenerator(asset:asset); generator.appliesPreferredTrackTransform=true; generator.requestedTimeToleranceBefore=CMTime(seconds:0.02,preferredTimescale:600); generator.requestedTimeToleranceAfter=CMTime(seconds:0.02,preferredTimescale:600)
            let first=try await generator.image(at:.zero).image; let width=max(2,first.width-first.width%2); let height=max(2,first.height-first.height%2); let fps=20.0; let frames=max(1,Int(duration*fps))
            let tmp=FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-reverse.mp4"); try? FileManager.default.removeItem(at:tmp)
            let writer=try AVAssetWriter(outputURL:tmp,fileType:.mp4); let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:6_000_000]]); input.expectsMediaDataInRealTime=false
            let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height]); guard writer.canAdd(input) else{throw AppError.message("تعذر تجهيز العكس")}; writer.add(input); writer.startWriting(); writer.startSession(atSourceTime:.zero)
            for i in 0..<frames { while !input.isReadyForMoreMediaData{try await Task.sleep(for:.milliseconds(4))}; let sourceSec=max(0,duration-Double(i+1)/fps); let image=try await generator.image(at:CMTime(seconds:sourceSec,preferredTimescale:600)).image; guard let pool=adaptor.pixelBufferPool else{continue}; var pixel:CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil,pool,&pixel); guard let pixel else{continue}; drawImage(image,into:pixel,width:width,height:height); adaptor.append(pixel,withPresentationTime:CMTime(seconds:Double(i)/fps,preferredTimescale:600)) }
            input.markAsFinished(); await writer.finishWriting(); guard writer.status == .completed else{throw writer.error ?? AppError.message("فشل عكس الفيديو")}; _=try persist(tmp,tmp.lastPathComponent); refreshStorage(); show("تم عكس الفيديو",.success)
        } catch { show(readable(error),.error) }
    }

    private func drawImage(_ cg:CGImage,into pixel:CVPixelBuffer,width:Int,height:Int){CVPixelBufferLockBaseAddress(pixel,[]);defer{CVPixelBufferUnlockBaseAddress(pixel,[])};guard let base=CVPixelBufferGetBaseAddress(pixel),let ctx=CGContext(data:base,width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)else{return};ctx.interpolationQuality = .high;ctx.draw(cg,in:CGRect(x:0,y:0,width:width,height:height))}

    func cropVideo(_ item:LocalMedia,aspect:Double,label:String) async {
        guard item.isVideo else{return}
        do {
            let asset=AVURLAsset(url:item.url); guard let source=try await asset.loadTracks(withMediaType:.video).first else{throw AppError.message("لا يوجد فيديو")}; let duration=try await asset.load(.duration); let natural=try await source.load(.naturalSize); let preferred=try await source.load(.preferredTransform); let transformed=CGRect(origin:.zero,size:natural).applying(preferred).standardized; let oriented=CGSize(width:abs(transformed.width),height:abs(transformed.height))
            var render=oriented; if oriented.width/oriented.height>aspect{render.width=oriented.height*aspect}else{render.height=oriented.width/aspect}; render.width=floor(render.width/2)*2; render.height=floor(render.height/2)*2; let cropX=max(0,(oriented.width-render.width)/2); let cropY=max(0,(oriented.height-render.height)/2)
            let composition=AVMutableComposition(); guard let dstV=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else{throw AppError.message("تعذر تجهيز الفيديو")}; try dstV.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:source,at:.zero); if let audio=try await asset.loadTracks(withMediaType:.audio).first,let dstA=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid){try dstA.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:audio,at:.zero)}
            let instruction=AVMutableVideoCompositionInstruction();instruction.timeRange=CMTimeRange(start:.zero,duration:duration);let layer=AVMutableVideoCompositionLayerInstruction(assetTrack:dstV);let normalize=preferred.concatenating(CGAffineTransform(translationX:-transformed.minX,y:-transformed.minY));layer.setTransform(normalize.concatenating(CGAffineTransform(translationX:-cropX,y:-cropY)),at:.zero);instruction.layerInstructions=[layer];let vc=AVMutableVideoComposition();vc.instructions=[instruction];vc.renderSize=render;vc.frameDuration=CMTime(value:1,timescale:30)
            let tmp=FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-\(label).mp4");try? FileManager.default.removeItem(at:tmp);guard let export=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality)else{throw AppError.message("تعذر التصدير")};export.videoComposition=vc;export.outputURL=tmp;export.outputFileType = .mp4;await export.export();guard export.status == .completed else{throw export.error ?? AppError.message("فشل قص الحدود")};_=try persist(tmp,tmp.lastPathComponent);refreshStorage();show("تم قص حدود الفيديو",.success)
        } catch { show("تعذر قص حدود الفيديو",.error) }
    }

    func addTextOverlay(_ item:LocalMedia,text:String) async {
        guard item.isVideo,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        do {
            let asset=AVURLAsset(url:item.url);guard let source=try await asset.loadTracks(withMediaType:.video).first else{throw AppError.message("لا يوجد فيديو")};let duration=try await asset.load(.duration);let natural=try await source.load(.naturalSize);let preferred=try await source.load(.preferredTransform);let rect=CGRect(origin:.zero,size:natural).applying(preferred).standardized;let render=CGSize(width:abs(rect.width),height:abs(rect.height));let composition=AVMutableComposition();guard let dstV=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)else{throw AppError.message("تعذر تجهيز الفيديو")};try dstV.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:source,at:.zero);if let audio=try await asset.loadTracks(withMediaType:.audio).first,let dstA=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid){try dstA.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:audio,at:.zero)}
            let instruction=AVMutableVideoCompositionInstruction();instruction.timeRange=CMTimeRange(start:.zero,duration:duration);let layerInstruction=AVMutableVideoCompositionLayerInstruction(assetTrack:dstV);layerInstruction.setTransform(preferred.concatenating(CGAffineTransform(translationX:-rect.minX,y:-rect.minY)),at:.zero);instruction.layerInstructions=[layerInstruction];let vc=AVMutableVideoComposition();vc.instructions=[instruction];vc.renderSize=render;vc.frameDuration=CMTime(value:1,timescale:30)
            let videoLayer=CALayer();videoLayer.frame=CGRect(origin:.zero,size:render);let parent=CALayer();parent.frame=videoLayer.frame;parent.addSublayer(videoLayer);let textLayer=CATextLayer();textLayer.string=text;textLayer.alignmentMode = .center;textLayer.foregroundColor=UIColor.white.cgColor;textLayer.backgroundColor=UIColor.black.withAlphaComponent(0.45).cgColor;textLayer.cornerRadius=12;textLayer.fontSize=max(28,render.width*0.045);textLayer.contentsScale=UIScreen.main.scale;textLayer.frame=CGRect(x:render.width*0.08,y:render.height*0.08,width:render.width*0.84,height:render.height*0.12);parent.addSublayer(textLayer);vc.animationTool=AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer:videoLayer,in:parent)
            let tmp=FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent)-text.mp4");try? FileManager.default.removeItem(at:tmp);guard let export=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality)else{throw AppError.message("تعذر التصدير")};export.videoComposition=vc;export.outputURL=tmp;export.outputFileType = .mp4;await export.export();guard export.status == .completed else{throw export.error ?? AppError.message("فشل إضافة النص")};_=try persist(tmp,tmp.lastPathComponent);refreshStorage();show("تمت إضافة النص على الفيديو",.success)
        } catch { show("تعذر إضافة النص",.error) }
    }

    func changeVideoFormat(_ item:LocalMedia,toMov:Bool) async {
        guard item.isVideo else{return};do{let asset=AVURLAsset(url:item.url);let ext=toMov ? "mov":"mp4";let type:AVFileType=toMov ? .mov:.mp4;let tmp=FileManager.default.temporaryDirectory.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent).\(ext)");try? FileManager.default.removeItem(at:tmp);guard let export=AVAssetExportSession(asset:asset,presetName:AVAssetExportPresetHighestQuality)else{throw AppError.message("تعذر التحويل")};export.outputURL=tmp;export.outputFileType=type;await export.export();guard export.status == .completed else{throw export.error ?? AppError.message("فشل التحويل")};_=try persist(tmp,tmp.lastPathComponent);refreshStorage();show("تم تغيير صيغة الفيديو",.success)}catch{show("تعذر تغيير الصيغة",.error)}
    }
}

struct TranslationChoiceSheet:View{@ObservedObject var model:AppModel;let item:LocalMedia;@Environment(\.dismiss)private var dismiss;@State private var busy=false;var body:some View{NavigationStack{List{Button("ترجمة إلى العربية"){run("ar")};Button("Translate to English"){run("en")};if busy{HStack{ProgressView();Text("جارٍ التعرف والترجمة…")}}}.navigationTitle("ترجمة الفيديو")}.presentationDetents([.height(220),.medium])}private func run(_ lang:String){busy=true;Task{await model.translateVideoToSRT(item,targetLanguage:lang);busy=false;dismiss()}}}

struct TextOverlaySheet:View{@ObservedObject var model:AppModel;let item:LocalMedia;@Environment(\.dismiss)private var dismiss;@State private var text="";@State private var busy=false;var body:some View{NavigationStack{VStack(spacing:16){TextField("اكتب النص الذي سيظهر على الفيديو",text:$text,axis:.vertical).lineLimit(2...5).padding(14).background(.thinMaterial,in:RoundedRectangle(cornerRadius:15));Button{busy=true;Task{await model.addTextOverlay(item,text:text);busy=false;dismiss()}}label:{HStack{if busy{ProgressView()};Text("إضافة النص")}.frame(maxWidth:.infinity).padding(14)}.buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty||busy);Spacer()}.padding(16).navigationTitle("الكتابة على الفيديو")}.presentationDetents([.medium])}}

struct CropChoiceSheet:View{@ObservedObject var model:AppModel;let item:LocalMedia;@Environment(\.dismiss)private var dismiss;@State private var busy=false;var body:some View{NavigationStack{List{crop("9:16 عمودي",9.0/16.0,"9x16");crop("1:1 مربع",1.0,"square");crop("4:5 منشور",4.0/5.0,"4x5");crop("16:9 أفقي",16.0/9.0,"16x9");if busy{HStack{ProgressView();Text("جارٍ قص الحدود…")}}}.navigationTitle("تقطيع حدود الفيديو")}.presentationDetents([.medium])}private func crop(_ title:String,_ ratio:Double,_ label:String)->some View{Button(title){busy=true;Task{await model.cropVideo(item,aspect:ratio,label:label);busy=false;dismiss()}}.disabled(busy)}}

struct MediaInfoSheet:View{let item:LocalMedia;@State private var duration:Double?;@State private var resolution="—";var body:some View{NavigationStack{List{LabeledContent("الاسم",value:item.url.lastPathComponent);LabeledContent("النوع",value:item.ext.uppercased());LabeledContent("الحجم",value:ByteCountFormatter.string(fromByteCount:item.size,countStyle:.file));LabeledContent("التاريخ",value:item.createdAt.formatted(date:.abbreviated,time:.shortened));if let duration{LabeledContent("المدة",value:format(duration))};if item.isVideo{LabeledContent("الدقة",value:resolution)}}.navigationTitle("معلومات الملف")}.presentationDetents([.medium]).task{guard item.isVideo || item.isAudio else{return};let asset=AVURLAsset(url:item.url);duration=try? await asset.load(.duration).seconds;if item.isVideo{let tracks=try? await asset.loadTracks(withMediaType:.video);if let t=tracks?.first,let size=try? await t.load(.naturalSize),let transform=try? await t.load(.preferredTransform){let r=CGRect(origin:.zero,size:size).applying(transform).standardized;resolution="\(Int(abs(r.width)))×\(Int(abs(r.height)))"}}}}private func format(_ seconds:Double)->String{let s=max(0,Int(seconds));return String(format:"%02d:%02d",s/60,s%60)}}
