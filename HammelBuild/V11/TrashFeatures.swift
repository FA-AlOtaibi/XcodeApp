import SwiftUI
import Foundation

extension AppModel {
    func trashFolder() -> URL { FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("Hammel-Trash",isDirectory:true) }
    func moveToTrash(_ item:LocalMedia){do{let fm=FileManager.default;let f=trashFolder();try fm.createDirectory(at:f,withIntermediateDirectories:true);let stamp=Int(Date().timeIntervalSince1970);let safe=item.url.lastPathComponent.replacingOccurrences(of:"__",with:"_");var dst=f.appendingPathComponent("trash-\(stamp)__\(safe)");var n=2;while fm.fileExists(atPath:dst.path){dst=f.appendingPathComponent("trash-\(stamp)-\(n)__\(safe)");n += 1};try fm.moveItem(at:item.url,to:dst);favoritePaths.remove(item.url.path);UserDefaults.standard.set(Array(favoritePaths),forKey:"favorites");refreshStorage();show("نُقل إلى سلة المهملات",.success)}catch{show("تعذر نقل الملف إلى السلة",.error)}}
    func trashItems()->[LocalMedia]{purgeExpiredTrash();let fm=FileManager.default;let f=trashFolder();try? fm.createDirectory(at:f,withIntermediateDirectories:true);let urls=(try? fm.contentsOfDirectory(at:f,includingPropertiesForKeys:[.creationDateKey,.fileSizeKey])) ?? [];return urls.filter{!$0.hasDirectoryPath}.map{let v=try? $0.resourceValues(forKeys:[.creationDateKey,.fileSizeKey]);return LocalMedia(url:$0,createdAt:v?.creationDate ?? .distantPast,size:Int64(v?.fileSize ?? 0))}.sorted{deletionDate(for:$0.url)>deletionDate(for:$1.url)}}
    func restoreFromTrash(_ item:LocalMedia){do{let name=originalTrashName(item.url);let f=mediaFolder();try FileManager.default.createDirectory(at:f,withIntermediateDirectories:true);var dst=f.appendingPathComponent(name);var n=2;while FileManager.default.fileExists(atPath:dst.path){let b=(name as NSString).deletingPathExtension,e=(name as NSString).pathExtension;dst=f.appendingPathComponent(e.isEmpty ? "\(b)-\(n)":"\(b)-\(n).\(e)");n += 1};try FileManager.default.moveItem(at:item.url,to:dst);refreshStorage();show("تم استرجاع الملف",.success)}catch{show("تعذر استرجاع الملف",.error)}}
    func deleteTrashPermanently(_ item:LocalMedia){try? FileManager.default.removeItem(at:item.url);show("تم الحذف نهائيًا",.success)}
    func emptyTrash(){let fm=FileManager.default;let f=trashFolder();if let u=try? fm.contentsOfDirectory(at:f,includingPropertiesForKeys:nil){u.forEach{try? fm.removeItem(at:$0)}};show("تم إفراغ سلة المهملات",.success)}
    func purgeExpiredTrash(){let fm=FileManager.default;let f=trashFolder();guard let u=try? fm.contentsOfDirectory(at:f,includingPropertiesForKeys:nil)else{return};let cutoff=Date().addingTimeInterval(-15*86400);for x in u where deletionDate(for:x)<cutoff{try? fm.removeItem(at:x)}}
    func trashRemainingText(_ item:LocalMedia)->String{let age=Date().timeIntervalSince(deletionDate(for:item.url));let d=max(0,15-Int(age/86400));return d==0 ? "سيُحذف قريبًا":"يبقى \(d) يوم"}
    private func deletionDate(for url:URL)->Date{let n=url.lastPathComponent;guard n.hasPrefix("trash-"),let m=n.range(of:"__")else{return (try? url.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? Date()};let raw=String(n[n.index(n.startIndex,offsetBy:6)..<m.lowerBound]);let ep=raw.split(separator:"-").first.flatMap{Double($0)} ?? Date().timeIntervalSince1970;return Date(timeIntervalSince1970:ep)}
    private func originalTrashName(_ url:URL)->String{let n=url.lastPathComponent;guard let m=n.range(of:"__")else{return n};return String(n[m.upperBound...])}
}

struct TrashView: View {
    @ObservedObject var model:AppModel; @State private var items:[LocalMedia]=[]; @State private var confirm=false
    var body: some View { ScrollView{LazyVStack(spacing:10){if items.isEmpty{ContentUnavailableView("السلة فارغة",systemImage:"trash",description:Text("المحذوفات تبقى 15 يومًا")).padding(.top,70)}else{HStack{Text("تُحذف تلقائيًا بعد 15 يومًا").font(.caption).foregroundStyle(.secondary);Spacer();Button("إفراغ",role:.destructive){confirm=true}};ForEach(items){i in HStack(spacing:10){LocalThumb(item:i).frame(width:54,height:48).clipShape(RoundedRectangle(cornerRadius:11));VStack(alignment:.leading,spacing:3){Text(display(i.url)).font(.subheadline.weight(.semibold)).lineLimit(1);Text("\(model.formattedBytes(i.size)) • \(model.trashRemainingText(i))").font(.caption2).foregroundStyle(.secondary)};Spacer();Menu{Button("استرجاع",systemImage:"arrow.uturn.backward"){model.restoreFromTrash(i);reload()};Button("حذف نهائي",systemImage:"trash",role:.destructive){model.deleteTrashPermanently(i);reload()}}label:{Image(systemName:"ellipsis").frame(width:36,height:36)}}.padding(8).background(.thinMaterial,in:RoundedRectangle(cornerRadius:15))}}}.padding(15)}.navigationTitle("سلة المهملات").navigationBarTitleDisplayMode(.inline).onAppear{reload()}.confirmationDialog("حذف جميع الملفات نهائيًا؟",isPresented:$confirm){Button("حذف الكل",role:.destructive){model.emptyTrash();reload()}} }
    private func reload(){items=model.trashItems()}; private func display(_ u:URL)->String{let n=u.lastPathComponent;guard let r=n.range(of:"__")else{return n};return String(n[r.upperBound...])}
}

struct MediaQuickActionsSheet: View {
    @ObservedObject var model:AppModel; let item:LocalMedia; @Environment(\.dismiss) private var dismiss; @State private var busy=false; @State private var share=false
    var body: some View { NavigationStack{VStack(spacing:12){
        HStack(spacing:10){LocalThumb(item:item).frame(width:48,height:44).clipShape(RoundedRectangle(cornerRadius:10));VStack(alignment:.leading,spacing:2){Text(item.url.deletingPathExtension().lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1);Text(model.formattedBytes(item.size)).font(.caption2).foregroundStyle(.secondary)};Spacer();Button{dismiss()}label:{Image(systemName:"xmark.circle.fill").font(.title2).foregroundStyle(.secondary)}}
        HStack(spacing:7){
            if item.isVideo{NavigationLink{MediaEditorView(sourceURL:item.url,model:model)}label:{CompactTool(title:"تعديل",icon:"slider.horizontal.3")}.buttonStyle(.plain)}
            Menu{
                if item.isVideo{
                    Button("حذف الموسيقى وإبقاء الكلام",systemImage:"mic.fill"){run{await model.separateCenterAudioFast(from:item,keepVoice:true)}}
                    Button("حذف الكلام وإبقاء الموسيقى",systemImage:"music.note"){run{await model.separateCenterAudioFast(from:item,keepVoice:false)}}
                    Button("استخراج الصوت M4A",systemImage:"waveform"){run{await model.extractAudio(from:item)}}
                    Button("كتم صوت الفيديو",systemImage:"speaker.slash"){run{await model.muteVideo(item)}}
                    Button("تحويل إلى نغمة رنين",systemImage:"bell.fill"){run{await model.makeRingtone(item)}}
                    Button("تحويل إلى MP3",systemImage:"music.note.list"){model.showUnsupportedAI("تحويل MP3")}
                } else if item.isAudio {
                    Button("تحويل إلى نغمة رنين",systemImage:"bell.fill"){run{await model.makeRingtone(item)}}
                }
            }label:{CompactTool(title:"الصوت",icon:"waveform")}
            Menu{
                if item.isVideo{
                    Button("تحويل إلى GIF",systemImage:"photo.stack"){run{await model.videoToGIF(item)}}
                    Button("ضغط / نسخة 720p",systemImage:"arrow.down.right.and.arrow.up.left"){run{await model.compress720(from:item)}}
                    Button("تدوير 90°",systemImage:"rotate.right"){run{await model.rotateVideo90(item)}}
                    Button("لقطة وسطية",systemImage:"photo"){run{await model.grabMiddleFrame(from:item)}}
                    Button("لوحة 9 لقطات",systemImage:"square.grid.3x3"){run{await model.contactSheet(from:item)}}
                    Button("ترجمة الفيديو",systemImage:"captions.bubble"){model.showUnsupportedAI("ترجمة الفيديو")}
                    Button("عكس الفيديو",systemImage:"backward.end"){model.showUnsupportedAI("عكس الفيديو")}
                }
                if item.ext=="gif"{Button("GIF إلى فيديو",systemImage:"film"){run{await model.gifToVideo(item)}}}
                if item.isImage{Button("إزالة الخلفية",systemImage:"person.crop.rectangle.badge.minus"){run{await model.removeImageBackground(item)}}}
                if item.isImage || item.isVideo{Button("تنظيف الخصوصية",systemImage:"shield"){run{await model.privacyCleanCopy(from:item)}}}
                Button("إنشاء نسخة",systemImage:"doc.on.doc"){model.duplicateMedia(item)}
                Button("تغيير الصيغة",systemImage:"arrow.triangle.2.circlepath"){model.showUnsupportedAI("تغيير الصيغة")}
            }label:{CompactTool(title:"أدوات",icon:"wand.and.stars")}
            Menu{
                if item.isImage || item.isVideo{Button("حفظ في الصور",systemImage:"photo.badge.plus"){run{await model.saveExistingToPhotos(item.url)}};Button("Snapchat",systemImage:"paperplane"){model.prepareForSnapchat(item);share=true}}
                ShareLink(item:item.url){Label("مشاركة للتطبيقات",systemImage:"square.and.arrow.up")}
            }label:{CompactTool(title:"مشاركة",icon:"square.and.arrow.up")}
        }
        HStack(spacing:8){Button{model.autoRename(item);dismiss()}label:{Label("اسم مرتب",systemImage:"textformat").font(.caption).frame(maxWidth:.infinity).padding(.vertical,9).background(.thinMaterial,in:RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain);Button(role:.destructive){model.moveToTrash(item);dismiss()}label:{Label("حذف",systemImage:"trash").font(.caption).frame(maxWidth:.infinity).padding(.vertical,9).background(Color.red.opacity(0.10),in:RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain)}
        if busy{HStack(spacing:7){ProgressView();Text("جارٍ المعالجة…").font(.caption).foregroundStyle(.secondary)}}
        Text("أدوات الفصل الصوتي الحالية محلية وسريعة؛ أفضل نتيجة عندما يكون الكلام في منتصف الستيريو.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }.padding(14).navigationBarHidden(true)}.presentationDetents([.height(250),.medium]).presentationDragIndicator(.visible).sheet(isPresented:$share){ActivityShareView(items:[item.url])} }
    private func run(_ op:@escaping()->Void){busy=true;op();DispatchQueue.main.asyncAfter(deadline:.now()+0.2){busy=false}}
    private func run(_ op:@escaping() async->Void){busy=true;Task{await op();busy=false}}
}

struct CompactTool: View { let title:String;let icon:String;var body: some View{VStack(spacing:4){Image(systemName:icon).font(.headline);Text(title).font(.caption2.weight(.medium)).lineLimit(1)}.frame(maxWidth:.infinity).frame(height:52).background(.thinMaterial,in:RoundedRectangle(cornerRadius:13))} }
