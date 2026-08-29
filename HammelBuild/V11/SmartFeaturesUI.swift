import SwiftUI
import UniformTypeIdentifiers

struct SmartToolsView: View {
    @ObservedObject var model: AppModel
    let item: LocalMedia
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var shareURL: URL?
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            List {
                if item.isVideo {
                    Section("الترجمة") {
                        action("ترجمة عربية داخل الفيديو", "captions.bubble") { await model.burnSubtitlesV3(item, target:"ar") }
                        action("ترجمة ثنائية عربي + إنجليزي", "character.bubble") { await model.burnSubtitlesV3(item, target:"ar", bilingual:true) }
                    }
                    Section("تحسين الفيديو") {
                        action("Smart Clip — أفضل اللحظات", "sparkles.rectangle.stack") { await model.smartClipV3(item) }
                        action("حذف الصمت تلقائيًا", "waveform.slash") { await model.removeSilenceV3(item) }
                        action("Auto Reframe — تتبع الشخص 9:16", "person.crop.rectangle") { await model.autoReframeV3(item) }
                        action("أفضل 6 صور غلاف", "photo.stack") { await model.thumbnailMakerV3(item) }
                    }
                    Section("الصوت") {
                        action("تنظيف الضوضاء والهمهمة", "waveform.badge.minus") { await model.cleanAudioV3(item) }
                        action("رفع وضوح الكلام مع إبقاء الموسيقى", "person.wave.2") { await model.boostSpeechV3(item) }
                        action("حذف الموسيقى وإبقاء الكلام", "mic.fill") { await model.separateWithDemucs(from:item, keepVoice:true) }
                        action("حذف الكلام وإبقاء الموسيقى", "music.note") { await model.separateWithDemucs(from:item, keepVoice:false) }
                    }
                }
                Section("مشاركة ذكية") {
                    ForEach(SmartSharePreset.allCases) { preset in
                        Button { runShare(preset) } label: { Label("تجهيز لـ \(preset.rawValue)", systemImage:preset == .snapchat ? "camera" : preset == .whatsapp ? "message" : "xmark") }
                    }
                }
                Section("الخصوصية والتنظيم") {
                    Button { model.moveToVaultV3(item); dismiss() } label: { Label("نقل إلى خزنة Face ID", systemImage:"lock.shield") }
                    Button { Task { await model.privacyCleanCopy(from:item) } } label: { Label("تنظيف بيانات الخصوصية", systemImage:"shield") }
                }
            }
            .navigationTitle("أدوات ذكية")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if busy { ZStack { Color.black.opacity(0.12).ignoresSafeArea(); ProgressView().controlSize(.large).padding(28).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:22)) } } }
        }
        .sheet(isPresented:$showShare) { if let shareURL { ActivityShareView(items:[shareURL]) } }
    }

    private func action(_ title:String,_ icon:String,_ work:@escaping () async -> Void)->some View {
        Button { busy=true; Task { await work(); busy=false } } label: { Label(title,systemImage:icon) }.disabled(busy)
    }
    private func runShare(_ preset:SmartSharePreset){busy=true;Task{do{shareURL=try await model.smartShareV3(item,preset:preset);showShare=true}catch{model.show(model.readable(error),.error)};busy=false}}
}

struct DownloadRulesView: View {
    @ObservedObject var model: AppModel
    @State private var rules = DownloadRuleSet()
    var body: some View {
        Form {
            Section { Toggle("تشغيل قواعد التنزيل",isOn:$rules.enabled);Toggle("بدء التنزيل تلقائيًا بعد لصق الرابط",isOn:$rules.autoDownload) }
            Section("YouTube") {
                Picker("الجودة الافتراضية",selection:$rules.youtubeQuality){ForEach(["720p","1080p","1440p","2160p"],id:\.self){Text($0).tag($0)}}
                Toggle("حفظ مباشرة في الصور",isOn:$rules.saveYouTubeToPhotos)
            }
            Section("TikTok") { Toggle("حفظ مباشرة في الصور",isOn:$rules.saveTikTokToPhotos) }
            Section("مجلد المراقبة") { Toggle("ضغط الفيديو تلقائيًا إلى 720p",isOn:$rules.watchCompress720);Toggle("تنظيف Metadata تلقائيًا",isOn:$rules.watchCleanMetadata) }
        }
        .navigationTitle("قواعد التنزيل")
        .onAppear{rules=model.downloadRulesV3}
        .onChange(of:rules){_,v in model.downloadRulesV3=v}
    }
}

struct DownloadHistoryView: View {
    @ObservedObject var model: AppModel
    @State private var working: UUID?
    var body: some View {
        List {
            if model.downloadHistoryV3.isEmpty { ContentUnavailableView("لا يوجد سجل",systemImage:"clock.arrow.circlepath") }
            ForEach(model.downloadHistoryV3) { row in
                VStack(alignment:.leading,spacing:7){
                    HStack{VStack(alignment:.leading,spacing:3){Text(row.filename).font(.subheadline.weight(.semibold)).lineLimit(1);Text("\(row.platform) • \(row.quality) • \(row.date.formatted(date:.abbreviated,time:.shortened))").font(.caption2).foregroundStyle(.secondary)};Spacer();if working==row.id{ProgressView()}}
                    HStack{Button("نسخ الرابط"){UIPasteboard.general.string=row.sourceURL}.buttonStyle(.bordered);Button("جودة أعلى"){working=row.id;Task{await model.redownloadHigherQualityV3(row);working=nil}}.buttonStyle(.borderedProminent)}
                }.padding(.vertical,4)
            }
        }
        .navigationTitle("سجل المصادر")
        .toolbar{ToolbarItem(placement:.topBarTrailing){Button("مسح",role:.destructive){model.clearHistoryV3()}}}
    }
}

struct VaultViewV3: View {
    @ObservedObject var model: AppModel
    @State private var unlocked=false
    @State private var items:[LocalMedia]=[]
    var body: some View {
        Group {
            if unlocked {
                List(items){item in HStack{LocalThumb(item:item).frame(width:52,height:46).clipShape(RoundedRectangle(cornerRadius:10));VStack(alignment:.leading){Text(item.url.deletingPathExtension().lastPathComponent).lineLimit(1);Text(model.formattedBytes(item.size)).font(.caption2).foregroundStyle(.secondary)};Spacer();Button("استعادة"){model.restoreFromVaultV3(item);reload()}}}
            } else { ContentUnavailableView("الخزنة مقفلة",systemImage:"faceid",description:Text("استخدم Face ID لفتح ملفاتك الخاصة")) }
        }
        .navigationTitle("الخزنة الخاصة")
        .task { unlocked=await model.authenticateVaultV3(); if unlocked{reload()} }
    }
    private func reload(){items=model.vaultItemsV3()}
}

struct WatchFolderViewV3: View {
    @ObservedObject var model: AppModel
    @State private var importer=false
    @State private var files:[URL]=[]
    var body: some View {
        List {
            Section { Button{importer=true}label:{Label("إضافة ملفات للمراقبة",systemImage:"folder.badge.plus")};Button{Task{await model.processWatchFolderV3();reload()}}label:{Label("تشغيل المعالجة الآن",systemImage:"play.fill")} }
            Section("بانتظار المعالجة") { if files.isEmpty{Text("لا توجد ملفات").foregroundStyle(.secondary)};ForEach(files,id:\.path){u in Text(u.lastPathComponent).lineLimit(1)} }
        }
        .navigationTitle("مجلد المراقبة")
        .onAppear{reload()}
        .fileImporter(isPresented:$importer,allowedContentTypes:[.movie,.audio,.image,.data],allowsMultipleSelection:true){result in if case .success(let urls)=result{urls.forEach(model.addToWatchFolderV3);reload()}}
    }
    private func reload(){files=(try? FileManager.default.contentsOfDirectory(at:model.watchFolderV3(),includingPropertiesForKeys:nil)) ?? []}
}

struct QualityComparisonV3: View {
    @ObservedObject var model: AppModel
    let items:[DownloadMedia]
    var body: some View {
        VStack(alignment:.leading,spacing:10){Text("مقارنة الجودة").font(.headline);ForEach(items.prefix(6)){m in HStack{Text(m.quality).fontWeight(.semibold);Spacer();Text(m.estimatedSize.map(model.formattedBytes) ?? "حجم غير معروف").foregroundStyle(.secondary);if m.hasAudio{Image(systemName:"speaker.wave.2.fill").foregroundStyle(.green)}}}.padding(14).background(.thinMaterial,in:RoundedRectangle(cornerRadius:18))
    }
}

struct SmartAutomationHubV3: View {
    @ObservedObject var model:AppModel
    var body:some View{List{NavigationLink{DownloadRulesView(model:model)}label:{Label("قواعد التنزيل",systemImage:"bolt.badge.clock")};NavigationLink{DownloadHistoryView(model:model)}label:{Label("سجل المصادر وإعادة التنزيل",systemImage:"clock.arrow.circlepath")};NavigationLink{WatchFolderViewV3(model:model)}label:{Label("مجلد المراقبة",systemImage:"folder.badge.gearshape")};NavigationLink{VaultViewV3(model:model)}label:{Label("الخزنة الخاصة Face ID",systemImage:"lock.shield")};Button{Task{await model.removeVisualDuplicatesV3()}}label:{Label("البحث عن المقاطع المتشابهة بصريًا",systemImage:"square.on.square")}}.navigationTitle("الأتمتة والذكاء")}
}
