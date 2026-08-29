import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private enum T { static let olive = Color(red: 0.27, green: 0.33, blue: 0.18) }

struct RootView: View {
    @ObservedObject var model: AppModel; @State private var tab = 0
    var body: some View {
        TabView(selection:$tab) {
            HomeView(model:model).tabItem{Label("تحميل",systemImage:"arrow.down.circle.fill")}.tag(0)
            LibraryView(model:model).tabItem{Label("المكتبة",systemImage:"folder.fill")}.tag(1)
            DownloadsView(model:model).tabItem{Label("التنزيلات",systemImage:"list.bullet.rectangle")}.tag(2)
            SettingsView(model:model).tabItem{Label("الإعدادات",systemImage:"gearshape.fill")}.tag(3)
        }.tint(T.olive).overlay(alignment:.top){if let n=model.notice{NoticeBanner(notice:n).padding(.top,8)}}.onAppear{model.purgeExpiredTrash()}
    }
}

struct NoticeBanner: View { let notice: Notice; var body: some View { Label(notice.text,systemImage:notice.style == .success ? "checkmark.circle.fill" : notice.style == .error ? "exclamationmark.circle.fill" : "info.circle.fill").font(.subheadline.weight(.semibold)).padding(.horizontal,16).padding(.vertical,11).background(.ultraThinMaterial,in:Capsule()).shadow(radius:8,y:3) } }

struct HomeView: View {
    @ObservedObject var model: AppModel; @State private var details=false
    var body: some View { NavigationStack { ScrollView { VStack(spacing:20) {
        HStack{VStack(alignment:.leading){Text("مُحمّل").font(.system(size:39,weight:.bold,design:.rounded));Text("نزّل. رتّب. استخدم.").font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"arrow.down").font(.title2.bold()).foregroundStyle(T.olive).frame(width:52,height:52).background(T.olive.opacity(0.11),in:RoundedRectangle(cornerRadius:17))}
        HStack{TextField("ألصق رابطًا",text:$model.input).textInputAutocapitalization(.never).autocorrectionDisabled();Image(systemName:"link").foregroundStyle(.secondary)}.padding(17).background(T.olive.opacity(0.10),in:RoundedRectangle(cornerRadius:22))
        HStack(spacing:10){Button{model.input=UIPasteboard.general.string ?? ""}label:{Label("لصق",systemImage:"doc.on.clipboard").frame(maxWidth:.infinity).padding(.vertical,14).background(.thinMaterial,in:RoundedRectangle(cornerRadius:18))};Button{Task{await model.resolve();if !model.results.isEmpty{details=true}}}label:{HStack{if model.isResolving{ProgressView().tint(.white)};Text(model.isResolving ? "تحليل…":"متابعة").fontWeight(.semibold);Image(systemName:"arrow.left")}.frame(maxWidth:.infinity).padding(.vertical,14).foregroundStyle(.white).background(T.olive,in:RoundedRectangle(cornerRadius:18))}.disabled(model.input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.isResolving)}
        PlatformStrip()
        if !model.library.isEmpty{VStack(alignment:.leading,spacing:10){HStack{Text("الأخيرة").font(.headline);Spacer();Text("\(model.library.count) ملف").font(.caption).foregroundStyle(.secondary)};ForEach(model.library.prefix(3)){i in NavigationLink{MediaDetailView(model:model,item:i)}label:{CompactMediaRow(item:i,model:model)}.buttonStyle(.plain)}}}
    }.padding(20)}.background(Color(uiColor:.systemGroupedBackground).ignoresSafeArea()).navigationDestination(isPresented:$details){ResolveDetailsView(model:model)} } }
}

struct PlatformStrip: View { var body: some View { HStack(spacing:21){ForEach([("play.rectangle.fill","YouTube"),("music.note","TikTok"),("camera.fill","Instagram"),("xmark","X")],id:\.1){x in VStack(spacing:7){Image(systemName:x.0).font(.title3).frame(width:48,height:48).background(.thinMaterial,in:Circle());Text(x.1).font(.caption).foregroundStyle(.secondary)}}}.frame(maxWidth:.infinity) } }

struct ResolveDetailsView: View {
    @ObservedObject var model: AppModel; @State private var selected:DownloadMedia?; @State private var name=""; @State private var save:SaveTarget = .app
    private var current:DownloadMedia?{selected ?? model.results.first}; private var job:DownloadJob?{guard let c=current else{return nil};return model.jobs.first{$0.item.url==c.url}}; private var busy:Bool{job?.state == .downloading || job?.state == .waiting}
    var body: some View { ScrollView { VStack(spacing:18){
        if let f=model.results.first{PreviewRemote(item:f).frame(height:230).clipShape(RoundedRectangle(cornerRadius:24));HStack{VStack(alignment:.leading){Text((f.filename as NSString).deletingPathExtension).font(.headline).lineLimit(2);Text("\(f.platform.rawValue) • \(model.results.count>1 ? "\(model.results.count) خيارات":f.type)").font(.caption).foregroundStyle(.secondary)};Spacer()}}
        if model.results.count>1{VStack(alignment:.leading,spacing:9){Text(model.results.first?.platform == .youtube ? "اختر الجودة":"اختر العنصر").font(.headline);ForEach(model.results){m in Button{guard !busy else{return};selected=m;name=(m.filename as NSString).deletingPathExtension}label:{HStack{VStack(alignment:.leading){Text(m.quality).fontWeight(.semibold);if let s=m.estimatedSize{Text(model.formattedBytes(s)).font(.caption2).foregroundStyle(.secondary)}};Spacer();if selected?.id==m.id{Image(systemName:"checkmark.circle.fill").foregroundStyle(T.olive)}}.padding(13).background(.thinMaterial,in:RoundedRectangle(cornerRadius:16))}.buttonStyle(.plain)}}}
        TextField("اسم الملف",text:$name).padding(14).background(.thinMaterial,in:RoundedRectangle(cornerRadius:16)).disabled(busy)
        Picker("الحفظ",selection:$save){Text("المكتبة").tag(SaveTarget.app);Text("الصور").tag(SaveTarget.photos)}.pickerStyle(.segmented).disabled(busy)
        Button{guard let c=current else{return};Task{await model.enqueueSmart(c,filename:name.isEmpty ? nil:name,target:save)}}label:{HStack{if busy{ProgressView().tint(.white)};Label(busy ? "جارٍ التحميل":"بدء التحميل",systemImage:"arrow.down.to.line").font(.headline)}.frame(maxWidth:.infinity).padding(.vertical,16).foregroundStyle(.white).background(T.olive,in:RoundedRectangle(cornerRadius:20))}.disabled(busy)
        if let j=job{DownloadProgressCard(job:j)}
    }.padding(20)}.navigationTitle("التفاصيل").navigationBarTitleDisplayMode(.inline).onAppear{selected=model.results.first;name=model.results.first.map{($0.filename as NSString).deletingPathExtension} ?? "";save=model.saveTarget == .ask ? .app:model.saveTarget} }
}

struct DownloadProgressCard: View { let job:DownloadJob; var body: some View { let p=Int(max(0,min(1,job.progress))*100);VStack(spacing:10){HStack{Text(job.state == .done ? "اكتمل التنزيل":job.state == .failed ? (job.error ?? "تعذر إكمال العملية"):"جارٍ التنزيل…").font(.subheadline.weight(.semibold));Spacer();if job.state == .downloading{Text("\(p)%").monospacedDigit()}};ProgressView(value:job.state == .done ? 1:job.progress).tint(T.olive)}.padding(15).background(.thinMaterial,in:RoundedRectangle(cornerRadius:18)) } }
struct PreviewRemote: View { let item:DownloadMedia; var body: some View { ZStack{Color.black;if let t=item.thumb{AsyncImage(url:t){p in if let im=p.image{im.resizable().scaledToFill()}else{ProgressView().tint(.white)}}}else{Image(systemName:item.type == "photo" ? "photo.fill":"play.fill").font(.system(size:48)).foregroundStyle(.white.opacity(0.8))}} } }

struct DownloadsView: View { @ObservedObject var model:AppModel; var body: some View { NavigationStack{ScrollView{LazyVStack(spacing:10){if model.jobs.isEmpty{ContentUnavailableView("لا توجد تنزيلات",systemImage:"arrow.down.circle")}else{ForEach(model.jobs){j in VStack(alignment:.leading,spacing:8){HStack{Text(j.item.filename).font(.subheadline.weight(.semibold)).lineLimit(1);Spacer();Text(j.state.rawValue).font(.caption).foregroundStyle(.secondary)};ProgressView(value:j.progress).tint(T.olive)}.padding(13).background(.thinMaterial,in:RoundedRectangle(cornerRadius:17))}}}.padding(16)}.navigationTitle("التنزيلات")}} }

struct LibraryView: View {
    @ObservedObject var model:AppModel; @State private var search=""; @State private var filter:MediaFilter = .all; @State private var sort:SortMode = .newest; @State private var picker:[PhotosPickerItem]=[]; @State private var fileImport=false; @State private var actionItem:LocalMedia?; @State private var selecting=false; @State private var selected:Set<String>=[]
    private var items:[LocalMedia]{var a=model.library.filter{search.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(search)};switch filter{case .all:break;case .image:a=a.filter{$0.isImage || $0.ext=="gif"};case .video:a=a.filter{$0.isVideo};case .audio:a=a.filter{$0.isAudio};case .document:a=a.filter{!$0.isImage && !$0.isVideo && !$0.isAudio && $0.ext != "gif"}};switch sort{case .newest:a.sort{$0.createdAt>$1.createdAt};case .oldest:a.sort{$0.createdAt<$1.createdAt};case .name:a.sort{$0.url.lastPathComponent<$1.url.lastPathComponent};case .size:a.sort{$0.size>$1.size}};return a}
    var body: some View { NavigationStack{VStack(spacing:0){ScrollView{VStack(spacing:11){
        HStack{TextField("بحث",text:$search).padding(11).background(.thinMaterial,in:RoundedRectangle(cornerRadius:14));Menu{ForEach(SortMode.allCases){s in Button(s.rawValue){sort=s}}}label:{Image(systemName:"arrow.up.arrow.down").frame(width:40,height:40).background(.thinMaterial,in:RoundedRectangle(cornerRadius:12))}}
        ScrollView(.horizontal,showsIndicators:false){HStack(spacing:7){ForEach(MediaFilter.allCases){f in Button(f.rawValue){filter=f}.buttonStyle(.borderedProminent).tint(filter==f ? T.olive:Color.gray.opacity(0.22)).foregroundStyle(filter==f ? .white:.primary)}}}
        HStack(spacing:8){PhotosPicker(selection:$picker,maxSelectionCount:20,matching:.any(of:[.images,.videos])){Label("من الصور",systemImage:"photo.on.rectangle.angled").frame(maxWidth:.infinity)}.buttonStyle(.borderedProminent).tint(T.olive);Button{fileImport=true}label:{Image(systemName:"folder.badge.plus").frame(width:42,height:34)}.buttonStyle(.bordered);NavigationLink{TrashView(model:model)}label:{Image(systemName:"trash.fill").foregroundStyle(.red).frame(width:42,height:34)}.buttonStyle(.bordered)}
        if selecting{HStack{Button(selected.count==items.count && !items.isEmpty ? "إلغاء تحديد الكل":"تحديد الكل"){selected = selected.count==items.count ? []:Set(items.map(\.id))};Spacer();Text("\(selected.count) محدد").font(.caption).foregroundStyle(.secondary)}}
        if items.isEmpty{ContentUnavailableView("المكتبة فارغة",systemImage:"folder")}else{LazyVStack(spacing:5){ForEach(items){i in LibraryCompactRow(model:model,item:i,selecting:selecting,selected:selected.contains(i.id),toggle:{toggle(i)},actions:{actionItem=i})}}}
    }.padding(15)}
    if selecting{HStack{Button("إلغاء"){selecting=false;selected.removeAll()}.frame(maxWidth:.infinity);Button(role:.destructive){deleteSelected()}label:{Label("حذف \(selected.count)",systemImage:"trash")}.frame(maxWidth:.infinity).disabled(selected.isEmpty)}.padding(.horizontal,16).padding(.vertical,9).background(.bar)}
    }.navigationTitle("المكتبة").toolbar{ToolbarItem(placement:.topBarLeading){Button(selecting ? "تم":"تحديد"){selecting.toggle();if !selecting{selected.removeAll()}}}}.onAppear{model.refreshStorage();model.purgeExpiredTrash()}.onChange(of:picker){_,new in Task{for p in new{if let d=try? await p.loadTransferable(type:Data.self){model.importImageData(d,ext:"jpg")}};picker=[]}}.fileImporter(isPresented:$fileImport,allowedContentTypes:[.movie,.image,.audio,.pdf,.data],allowsMultipleSelection:true){r in if case .success(let u)=r{u.forEach(model.importFile)}}.sheet(item:$actionItem){i in MediaQuickActionsSheet(model:model,item:i)}} }
    private func toggle(_ i:LocalMedia){if selected.contains(i.id){selected.remove(i.id)}else{selected.insert(i.id)}}
    private func deleteSelected(){let t=model.library.filter{selected.contains($0.id)};t.forEach{model.moveToTrash($0)};selected.removeAll();selecting=false;model.refreshStorage()}
}

struct LibraryCompactRow: View {
    @ObservedObject var model:AppModel; let item:LocalMedia; let selecting:Bool; let selected:Bool; let toggle:()->Void; let actions:()->Void
    var body: some View { HStack(spacing:9){if selecting{Button(action:toggle){Image(systemName:selected ? "checkmark.circle.fill":"circle").font(.title3).foregroundStyle(selected ? T.olive:.secondary)}};if selecting{Button(action:toggle){content}.buttonStyle(.plain)}else{NavigationLink{MediaDetailView(model:model,item:item)}label:{content}.buttonStyle(.plain)};Spacer(minLength:2);if !selecting{Button(action:actions){Image(systemName:"ellipsis").frame(width:32,height:32)}}}.padding(.horizontal,9).padding(.vertical,5).background(.thinMaterial,in:RoundedRectangle(cornerRadius:14)) }
    private var content: some View { HStack(spacing:9){LocalThumb(item:item).frame(width:48,height:42).clipShape(RoundedRectangle(cornerRadius:9));VStack(alignment:.leading,spacing:2){Text(item.url.deletingPathExtension().lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1);Text(model.formattedBytes(item.size)).font(.caption2).foregroundStyle(.secondary)}} }
}

struct CompactMediaRow: View { let item:LocalMedia; @ObservedObject var model:AppModel; var body: some View { HStack(spacing:12){LocalThumb(item:item).frame(width:62,height:55).clipShape(RoundedRectangle(cornerRadius:13));VStack(alignment:.leading,spacing:4){Text(item.url.lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1);Text(model.formattedBytes(item.size)).font(.caption2).foregroundStyle(.secondary)};Spacer();Image(systemName:"chevron.left").foregroundStyle(.secondary)}.padding(10).background(.thinMaterial,in:RoundedRectangle(cornerRadius:17)) } }

struct SettingsView: View { @ObservedObject var model:AppModel; @State private var confirm=false; var body: some View { NavigationStack{Form{Section("المظهر"){Picker("الوضع",selection:Binding(get:{model.appearance},set:model.setAppearance)){ForEach(AppearanceMode.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented)};Section("الحفظ"){Picker("المكان الافتراضي",selection:Binding(get:{model.saveTarget},set:model.setSaveTarget)){ForEach(SaveTarget.allCases){Text($0.rawValue).tag($0)}}};Section("المساحة"){LabeledContent("المكتبة",value:model.formattedBytes(model.libraryBytes));LabeledContent("الكاش",value:model.formattedBytes(model.cacheBytes));NavigationLink{TrashView(model:model)}label:{Label("سلة المهملات",systemImage:"trash.fill")};Button("حذف الكاش"){model.clearCache()};Button("حذف الملفات المكررة"){model.removeDuplicates()};Button("حذف جميع ملفات التطبيق",role:.destructive){confirm=true}};Section("حول"){Text("مُحمّل 1.7").foregroundStyle(.secondary)}}.navigationTitle("الإعدادات").confirmationDialog("حذف جميع الملفات؟",isPresented:$confirm){Button("حذف الكل",role:.destructive){model.deleteAllAppFiles()}}}} }
