import SwiftUI
import AVKit
import AVFoundation
import UIKit

struct LocalThumb: View {
    let item: LocalMedia
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
            if let image { Image(uiImage:image).resizable().scaledToFill() }
            else if item.isAudio { Image(systemName:"waveform").font(.title).foregroundStyle(.secondary) }
            else { Image(systemName:item.isVideo ? "play.fill" : "doc.fill").font(.title).foregroundStyle(.secondary) }
        }.task { if item.isImage { image = UIImage(contentsOfFile:item.url.path) } else if item.isVideo { image = await thumbnail(item.url) } }
    }
    private func thumbnail(_ url:URL) async -> UIImage? { let a=AVURLAsset(url:url);let g=AVAssetImageGenerator(asset:a);g.appliesPreferredTrackTransform=true;return try? await g.image(at:.zero).image.map(UIImage.init(cgImage:)) }
}

private extension CGImage { var image: CGImage { self } }

struct MediaDetailView: View {
    @ObservedObject var model: AppModel
    let item: LocalMedia
    @State private var name="";@State private var showRename=false;@State private var showDelete=false
    var body: some View {
        ScrollView {
            VStack(spacing:18){
                MediaPreview(item:item).frame(maxWidth:.infinity).frame(height:380).clipShape(RoundedRectangle(cornerRadius:24))
                HStack { VStack(alignment:.leading,spacing:4){Text(item.url.deletingPathExtension().lastPathComponent).font(.title3.bold()).lineLimit(2);Text(model.formattedBytes(item.size)).font(.caption).foregroundStyle(.secondary)};Spacer();Button{model.toggleFavorite(item)}label:{Image(systemName:model.isFavorite(item) ? "heart.fill":"heart").font(.title3).foregroundStyle(model.isFavorite(item) ? .red:.secondary)} }
                HStack(spacing:10){ShareLink(item:item.url){Label("مشاركة",systemImage:"square.and.arrow.up").frame(maxWidth:.infinity)}.buttonStyle(.borderedProminent);Button{showRename=true}{Label("إعادة تسمية",systemImage:"pencil").frame(maxWidth:.infinity)}.buttonStyle(.bordered)}
                if item.isImage || item.isVideo { Button{Task{await model.saveExistingToPhotos(item.url)}}label:{Label("حفظ في الصور",systemImage:"photo.badge.plus").frame(maxWidth:.infinity).padding(14).background(.thinMaterial,in:RoundedRectangle(cornerRadius:17))} }
                if item.isVideo { NavigationLink{MediaEditorView(sourceURL:item.url,model:model)}label:{Label("تعديل الفيديو",systemImage:"slider.horizontal.3").frame(maxWidth:.infinity).padding(14).background(.thinMaterial,in:RoundedRectangle(cornerRadius:17))} }
                Button("حذف الملف",role:.destructive){showDelete=true}.padding(.top,4)
            }.padding(20)
        }
        .navigationTitle("التفاصيل").navigationBarTitleDisplayMode(.inline)
        .onAppear{model.clearTransientState();name=item.url.deletingPathExtension().lastPathComponent}
        .alert("إعادة تسمية",isPresented:$showRename){TextField("الاسم",text:$name);Button("حفظ"){model.renameLocal(item,to:name)};Button("إلغاء",role:.cancel){}}
        .confirmationDialog("حذف هذا الملف؟",isPresented:$showDelete){Button("حذف",role:.destructive){model.deleteLocal(item)}}
    }
}

struct MediaPreview: View {
    let item:LocalMedia
    @State private var player:AVPlayer?
    var body:some View { ZStack { Color.black; if item.isImage,let img=UIImage(contentsOfFile:item.url.path){Image(uiImage:img).resizable().scaledToFit()} else if item.isVideo || item.isAudio { if let player { VideoPlayer(player:player) } else { ProgressView().tint(.white) } } else {Image(systemName:"doc.fill").font(.system(size:52)).foregroundStyle(.white.opacity(0.8))} }.task{if item.isVideo || item.isAudio{let p=AVPlayer(url:item.url);player=p}}.onDisappear{player?.pause();player=nil} }
}

struct MediaEditorView: View {
    let sourceURL:URL
    @ObservedObject var model:AppModel
    @State private var duration=1.0;@State private var start=0.0;@State private var end=1.0;@State private var speed=1.0;@State private var muted=false;@State private var exporting=false
    var body:some View {
        ScrollView { VStack(spacing:18){
            let temp = LocalMedia(url:sourceURL,createdAt:Date(),size:0)
            MediaPreview(item:temp).frame(height:280).clipShape(RoundedRectangle(cornerRadius:22))
            VStack(alignment:.leading,spacing:12){Text("القص").font(.headline);HStack{Text(fmt(start));Spacer();Text(fmt(end))};Slider(value:$start,in:0...max(0.1,end-0.1),step:0.1);Slider(value:$end,in:min(duration,start+0.1)...max(duration,min(duration,start+0.1)),step:0.1)}.padding(16).background(.thinMaterial,in:RoundedRectangle(cornerRadius:18))
            VStack(alignment:.leading,spacing:12){Text("السرعة").font(.headline);Picker("السرعة",selection:$speed){Text("0.5×").tag(0.5);Text("1×").tag(1.0);Text("1.5×").tag(1.5);Text("2×").tag(2.0)}.pickerStyle(.segmented);Toggle("كتم الصوت",isOn:$muted)}.padding(16).background(.thinMaterial,in:RoundedRectangle(cornerRadius:18))
            Button{export()}label:{HStack{if exporting{ProgressView()};Label("حفظ نسخة",systemImage:"square.and.arrow.down")}.frame(maxWidth:.infinity).padding(15).foregroundStyle(.white).background(Color(red:0.28,green:0.34,blue:0.18),in:RoundedRectangle(cornerRadius:18))}.disabled(exporting || end<=start)
        }.padding(20)}.navigationTitle("تعديل الفيديو").navigationBarTitleDisplayMode(.inline).task{let a=AVURLAsset(url:sourceURL);if let d=try? await a.load(.duration){duration=max(0.1,d.seconds);end=duration}}
    }
    private func fmt(_ s:Double)->String{String(format:"%02d:%02d",Int(s)/60,Int(s)%60)}
    private func export(){
        exporting=true
        Task {
            do {
                let asset=AVURLAsset(url:sourceURL);let composition=AVMutableComposition();let range=CMTimeRange(start:CMTime(seconds:start,preferredTimescale:600),end:CMTime(seconds:end,preferredTimescale:600))
                if let srcV=try await asset.loadTracks(withMediaType:.video).first,let dstV=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid){try dstV.insertTimeRange(range,of:srcV,at:.zero);dstV.preferredTransform=try await srcV.load(.preferredTransform)}
                if !muted,let srcA=try await asset.loadTracks(withMediaType:.audio).first,let dstA=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid){try dstA.insertTimeRange(range,of:srcA,at:.zero)}
                let original=CMTime(seconds:end-start,preferredTimescale:600);let scaled=CMTime(seconds:(end-start)/speed,preferredTimescale:600);composition.scaleTimeRange(CMTimeRange(start:.zero,duration:original),toDuration:scaled)
                guard let exp=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality) else{throw AppError.message("تعذر تجهيز التعديل")}
                let tmp=FileManager.default.temporaryDirectory.appendingPathComponent("edited-\(Int(Date().timeIntervalSince1970)).mp4");try? FileManager.default.removeItem(at:tmp);exp.outputURL=tmp;exp.outputFileType=.mp4
                await exp.export();if exp.status != .completed{throw exp.error ?? AppError.message("فشل التصدير")};_ = try model.persist(tmp,tmp.lastPathComponent);model.refreshStorage();model.show("تم حفظ النسخة المعدلة",.success)
            } catch { model.show("تعذر حفظ التعديل",.error) }
            exporting=false
        }
    }
}
