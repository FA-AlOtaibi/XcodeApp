import SwiftUI
import UIKit
import PhotosUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @State private var mode: AYNMode = .see
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var compareItems: [PhotosPickerItem] = []
    @State private var compareImages: [Data] = []
    @State private var isLoading = false
    @State private var question = ""
    @State private var technicianText = ""
    @State private var newProfileName = ""
    @State private var showProfiles = false
    @State private var showOBD = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, Color(red: 0.018, green: 0.035, blue: 0.06)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        modePicker
                        switch mode {
                        case .see: seeMode
                        case .inspect: inspectMode
                        case .car: carMode
                        case .ask: askMode
                        }
                        if isLoading || app.isAnalyzing { progressCard }
                        if let step = app.guidedStep { guidedCard(step) }
                        if let result = app.compareResult { textResult(title: "المقارنة", icon: "rectangle.2.swap", text: result) }
                        if let answer = app.assistantAnswer { textResult(title: "جواب عَيْن", icon: "bubble.left.and.text.bubble.right.fill", text: answer) }
                        if let analysis = app.analysis { analysisCard(analysis) }
                        if let error = app.errorMessage { errorCard(error) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 42)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker(onImage: handleImage).ignoresSafeArea() }
        .sheet(isPresented: $showProfiles) { profileSheet }
        .sheet(isPresented: $showOBD) { NavigationStack { OBDView() } }
        .onChange(of: photoItem) { _, item in guard let item else { return }; Task { await loadPhoto(item) } }
        .onChange(of: videoItem) { _, item in guard let item else { return }; Task { await loadVideo(item) } }
        .onChange(of: compareItems) { _, items in Task { await loadCompare(items) } }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.cyan.opacity(0.14)).frame(width: 58, height: 58)
                Image(systemName: "eye.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(.cyan)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) { Text("عَيْن").font(.system(size: 33, weight: .black, design: .rounded)); Text("4.0").font(.caption.bold().monospaced()).foregroundStyle(.cyan) }
                Text("يشوف، يفحص، يتذكر، ويقترح الخطوة الجاية").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showProfiles = true } label: { Image(systemName: "tray.full.fill").font(.title3).frame(width: 44, height: 44).background(.white.opacity(0.07), in: Circle()) }.buttonStyle(.plain)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(AYNMode.allCases) { item in
                Button { withAnimation(.snappy) { mode = item } } label: {
                    VStack(spacing: 6) { Image(systemName: icon(for: item)).font(.system(size: 17, weight: .bold)); Text(item.rawValue).font(.caption.bold()) }
                        .frame(maxWidth: .infinity).frame(height: 62)
                        .background(mode == item ? Color.cyan : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
                        .foregroundStyle(mode == item ? .black : .white)
                }.buttonStyle(.plain)
            }
        }
    }

    private func icon(for mode: AYNMode) -> String {
        switch mode { case .see: return "viewfinder"; case .inspect: return "stethoscope"; case .car: return "car.fill"; case .ask: return "bubble.left.and.bubble.right.fill" }
    }

    private var seeMode: some View {
        VStack(spacing: 14) {
            mediaHero(title: "وش هذا؟", subtitle: "صوّر أي شيء وخذ شرحًا مبسطًا وتفاصيل مفيدة")
            mediaButtons
            featureRow([("نصوص وأكواد","text.viewfinder"),("طريقة الاستخدام","gearshape.2"),("تنبيهات","exclamationmark.triangle")])
        }
    }

    private var inspectMode: some View {
        VStack(spacing: 14) {
            sectionHeader("فحص ذكي", "استخدم أكثر من زاوية أو قارن قبل/بعد بدل الاعتماد على لقطة واحدة")
            mediaButtons
            PhotosPicker(selection: $compareItems, maxSelectionCount: 6, matching: .images) {
                actionCard(title: "مقارنة قبل / بعد", subtitle: compareImages.isEmpty ? "اختر صورتين إلى 6 صور" : "تم تجهيز \(compareImages.count) صور", icon: "rectangle.2.swap", accent: .purple)
            }.buttonStyle(.plain)
            if !compareImages.isEmpty {
                Button { Task { await app.compare(images: compareImages, prompt: "قارن هذه الصور زمنيًا أو من حيث الحالة، واكشف أي تغير أو تدهور أو تحسن واضح.") } } label: { primaryButton("ابدأ المقارنة", icon: "arrow.triangle.2.circlepath") }.buttonStyle(.plain)
            }
            Button { Task { await app.nextGuidedStep(mode: "فحص عام") } } label: { actionCard(title: "وجّهني للّقطة التالية", subtitle: "عَيْن يقول لك وش تصوّر بعد عشان يزيد دقة الفحص", icon: "camera.metering.center.weighted", accent: .cyan) }.buttonStyle(.plain)
        }
    }

    private var carMode: some View {
        VStack(spacing: 14) {
            sectionHeader("مختبر السيارة", "صورة + فيديو وصوت + OBD + أسئلة قصيرة = تشخيص أذكى")
            mediaButtons
            HStack(spacing: 10) {
                Button { showOBD = true } label: { miniAction("OBD", "cable.connector", .orange) }.buttonStyle(.plain)
                Button { Task { await app.nextGuidedStep(mode: "تشخيص سيارة") } } label: { miniAction("فحص موجه", "checklist", .cyan) }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("راجع كلام الفني").font(.headline)
                TextField("مثال: قال لازم أغير كمبروسر المكيف كامل", text: $technicianText, axis: .vertical)
                    .textFieldStyle(.plain).padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
                Button { Task { await app.reviewTechnician(technicianText) } } label: { primaryButton("حلّل كلام الفني", icon: "person.crop.circle.badge.questionmark") }.buttonStyle(.plain).disabled(technicianText.isEmpty)
            }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
            featureRow([("درجة خطورة","gauge.with.dots.needle.67percent"),("ترتيب الأسباب","list.number"),("تكلفة تقريبية","banknote"),("هل تسوق؟","steeringwheel")])
        }
    }

    private var askMode: some View {
        VStack(spacing: 14) {
            sectionHeader("اسأل عَيْن", "يسأل على آخر صورة أو فيديو أو OBD بدل ما تبدأ من الصفر")
            TextField("مثال: كيف أفك هذي القطعة؟ وش أفحص قبل أشتري بديل؟", text: $question, axis: .vertical)
                .textFieldStyle(.plain).padding(16).background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
            Button { let q = question; question = ""; Task { await app.ask(q) } } label: { primaryButton("اسأل", icon: "arrow.up.circle.fill") }.buttonStyle(.plain).disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            VStack(spacing: 8) {
                ForEach(["هل هذا طبيعي؟","كيف أفكه بأمان؟","وش أسوأ احتمال؟","وش الاختبار اللي يثبت العطل؟","وش اسم القطعة الصحيح؟"], id: \.self) { q in
                    Button { Task { await app.ask(q) } } label: { HStack { Text(q); Spacer(); Image(systemName: "chevron.left") }.font(.subheadline.bold()).padding(14).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func mediaHero(title: String, subtitle: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let data = app.selectedImageData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
                else { LinearGradient(colors: [.white.opacity(0.06), .cyan.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing).overlay { VStack(spacing: 12) { Image(systemName: "viewfinder.circle.fill").font(.system(size: 78)).foregroundStyle(.cyan.opacity(0.85)); Text(title).font(.title2.bold()); Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24) } } }
            }
            .frame(maxWidth: .infinity).frame(height: 355).clipped().clipShape(RoundedRectangle(cornerRadius: 28)).overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.1)))
            HStack { Label(app.selectedMediaKind, systemImage: "dot.radiowaves.left.and.right"); Spacer(); if app.selectedImageData != nil { Button("مسح") { app.reset() }.buttonStyle(.plain) } }
                .font(.caption.bold()).padding(15).background(.ultraThinMaterial).clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
        }
    }

    private var mediaButtons: some View {
        HStack(spacing: 9) {
            Button { showCamera = true } label: { mediaButton("كاميرا", "camera.fill", true) }.buttonStyle(.plain)
            PhotosPicker(selection: $photoItem, matching: .images) { mediaButton("صورة", "photo.fill", false) }.buttonStyle(.plain)
            PhotosPicker(selection: $videoItem, matching: .videos) { mediaButton("فيديو", "video.fill", false) }.buttonStyle(.plain)
        }.disabled(isLoading || app.isAnalyzing)
    }

    private func mediaButton(_ title: String, _ icon: String, _ primary: Bool) -> some View {
        Label(title, systemImage: icon).font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 54).background(primary ? Color.cyan : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 17)).foregroundStyle(primary ? .black : .white)
    }

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.title2.bold()); Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
    private func actionCard(title: String, subtitle: String, icon: String, accent: Color) -> some View { HStack(spacing: 14) { Image(systemName: icon).font(.title2.bold()).foregroundStyle(accent).frame(width: 48, height: 48).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)); VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.left").foregroundStyle(.secondary) }.padding(15).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18)) }
    private func miniAction(_ title: String, _ icon: String, _ color: Color) -> some View { Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).frame(height: 58).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18)).foregroundStyle(color) }
    private func primaryButton(_ title: String, icon: String) -> some View { Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).frame(height: 54).background(.cyan, in: RoundedRectangle(cornerRadius: 17)).foregroundStyle(.black) }
    private func featureRow(_ items: [(String,String)]) -> some View { HStack(spacing: 8) { ForEach(Array(items.enumerated()), id: \.offset) { _, item in VStack(spacing: 6) { Image(systemName: item.1); Text(item.0).font(.caption2.bold()).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(.vertical, 12).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13)) } } }

    private var progressCard: some View { HStack(spacing: 13) { ProgressView().tint(.cyan); Text(isLoading ? "جاري تجهيز الوسائط…" : "عَيْن يفكر…").font(.headline); Spacer() }.padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18)) }
    private func guidedCard(_ text: String) -> some View { VStack(alignment: .leading, spacing: 8) { Label("اللقطة التالية", systemImage: "camera.badge.ellipsis").font(.headline).foregroundStyle(.cyan); Text(text); Button { showCamera = true } label: { Label("افتح الكاميرا", systemImage: "camera.fill") }.buttonStyle(.borderedProminent).tint(.cyan) }.frame(maxWidth: .infinity, alignment: .leading).padding(17).background(.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 20)) }
    private func textResult(title: String, icon: String, text: String) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.headline).foregroundStyle(.cyan); Text(text).font(.body).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20)) }

    private func analysisCard(_ a: VisualAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) { VStack(alignment: .leading, spacing: 5) { Text(a.category.uppercased()).font(.caption.bold()).foregroundStyle(.cyan); Text(a.title).font(.title.bold()); Text(a.summary).foregroundStyle(.white.opacity(0.78)) }; Spacer(); Text("\(a.confidence)%").font(.headline.monospacedDigit()).padding(10).background(.cyan.opacity(0.12), in: Circle()) }
            if let car = a.automotive, car.isVehicleRelated { carDiagnosis(car) }
            bullets("أهم المعلومات", a.keyFacts, "sparkles"); bullets("الظاهر بالصورة", a.visibleDetails, "eye"); bullets("الاستخدام / العمل", a.howItWorksOrUsed, "gearshape.2")
            if !a.cautions.isEmpty { bullets("تنبيهات", a.cautions, "exclamationmark.triangle.fill", .orange) }
            if let u = a.uncertainty, !u.isEmpty { Label(u, systemImage: "questionmark.circle").font(.subheadline).foregroundStyle(.secondary) }
            Button { Task { await app.nextGuidedStep(mode: mode.rawValue) } } label: { Label("كيف أكمل الفحص؟", systemImage: "arrow.triangle.branch") }.buttonStyle(.bordered).tint(.cyan)
        }.padding(18).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(.cyan.opacity(0.14)))
    }

    private func carDiagnosis(_ c: AutomotiveDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("تشخيص السيارة", systemImage: "car.badge.gearshape.fill").font(.headline).foregroundStyle(.cyan); Spacer(); if let s = c.severity { Text(s.uppercased()).font(.caption.bold()).foregroundStyle(s == "critical" ? .red : .orange) } }
            if let system = c.probableSystem { Text("النظام المحتمل: \(system)").bold() }
            if let drive = c.canDrive { Text("القيادة: \(drive)").foregroundStyle(drive == "لا" ? .red : .orange).bold() }
            ForEach(Array(c.likelyCauses.enumerated()), id: \.offset) { index, cause in VStack(alignment: .leading, spacing: 4) { HStack { Text("\(index+1). \(cause.cause)").bold(); Spacer(); Text("\(cause.probability)%").foregroundStyle(.cyan).font(.caption.bold()) }; Text(cause.reasoning).font(.caption).foregroundStyle(.secondary) }.padding(11).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12)) }
            bullets("افحص بهذا الترتيب", c.checks, "checklist"); bullets("الحلول المحتملة", c.fixes, "wrench.and.screwdriver"); if !c.dtcHints.isEmpty { bullets("أكواد OBD", c.dtcHints, "number.square") }
        }.padding(15).background(.cyan.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
    }

    private func bullets(_ title: String, _ items: [String], _ icon: String, _ color: Color = .white) -> some View { Group { if !items.isEmpty { VStack(alignment: .leading, spacing: 8) { Label(title, systemImage: icon).font(.headline).foregroundStyle(color); ForEach(Array(items.enumerated()), id: \.offset) { _, t in HStack(alignment: .top, spacing: 8) { Circle().fill(color == .white ? Color.cyan : color).frame(width: 6, height: 6).padding(.top, 6); Text(t).font(.subheadline); Spacer(minLength: 0) } } } } } }
    private func errorCard(_ text: String) -> some View { VStack(alignment: .leading, spacing: 8) { Label("تعذر التنفيذ", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.red); Text(text).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(17).background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 18)) }

    private var profileSheet: some View {
        NavigationStack {
            List {
                Section("ملف جديد") { TextField("مثال: يوكن 2013، مكيف الصالة", text: $newProfileName); Button("إنشاء ملف") { if !newProfileName.isEmpty { let p = app.workspace.addProfile(name: newProfileName, kind: "عام"); app.selectedProfileID = p.id; newProfileName = "" } }.disabled(newProfileName.isEmpty) }
                Section("ملفاتي") { ForEach(app.workspace.profiles) { p in Button { app.selectedProfileID = p.id; showProfiles = false } label: { HStack { VStack(alignment: .leading) { Text(p.name).font(.headline); Text("\(app.workspace.events(for: p.id).count) حدث").font(.caption).foregroundStyle(.secondary) }; Spacer(); if app.selectedProfileID == p.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) } } } } }
            }.navigationTitle("ذاكرة عَيْن")
        }
    }

    private func handleImage(_ image: UIImage) { guard let data = ImageCompressor.jpegData(from: image) else { app.errorMessage = "تعذر تجهيز الصورة."; return }; app.selectedImageData = data; Task { await app.analyze(imageData: data) } }
    @MainActor private func loadPhoto(_ item: PhotosPickerItem) async { isLoading = true; defer { isLoading = false; photoItem = nil }; do { guard let raw = try await item.loadTransferable(type: Data.self), let image = UIImage(data: raw) else { app.errorMessage = "تعذر قراءة الصورة."; return }; handleImage(image) } catch { app.errorMessage = error.localizedDescription } }
    @MainActor private func loadVideo(_ item: PhotosPickerItem) async { isLoading = true; defer { isLoading = false; videoItem = nil }; do { guard let data = try await item.loadTransferable(type: Data.self) else { app.errorMessage = "تعذر قراءة الفيديو."; return }; await app.analyzeVideo(data: data) } catch { app.errorMessage = error.localizedDescription } }
    @MainActor private func loadCompare(_ items: [PhotosPickerItem]) async { isLoading = true; compareImages = []; defer { isLoading = false }; for item in items.prefix(6) { if let raw = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: raw), let data = ImageCompressor.jpegData(from: img) { compareImages.append(data) } } }
}
