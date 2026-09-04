import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var processor = ImageProcessor()
    @StateObject private var hf = HuggingFaceService()
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedResult = 0
    @State private var showSettings = false
    @State private var show3D = false
    @State private var showAR = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.035, green: 0.035, blue: 0.045).ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 18) {
                        header
                        hero
                        if processor.source != nil {
                            localStudio
                            aiTools
                            if let depth = hf.depthImage { depthSection(depth) }
                            if !hf.angleImages.isEmpty { angleSection }
                            if let model = hf.modelURL { modelSection(model) }
                        }
                        if let error = hf.errorMessage ?? processor.errorMessage { errorCard(error) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 42)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView(service: hf) }
        .sheet(isPresented: $show3D) {
            if let url = hf.modelURL {
                NavigationStack {
                    ModelViewer(fileURL: url)
                        .background(Color.black)
                        .navigationTitle("3D Preview")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("إغلاق") { show3D = false } } }
                }
            }
        }
        .sheet(isPresented: $showAR) {
            if let url = hf.usdzURL {
                QuickLookPreview(url: url).ignoresSafeArea()
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    hf.clearResults()
                    await processor.process(image)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white)
                Image(systemName: "cube.transparent").font(.system(size: 21, weight: .black)).foregroundStyle(.black)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text("OBJECT STUDIO").font(.system(size: 19, weight: .black, design: .rounded)).tracking(1.3)
                Text("Product imaging, angles, 3D & AR").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .bold)).frame(width: 44, height: 44)
                    .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.top, 8)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.08)))
                if let source = processor.source {
                    Image(uiImage: source).resizable().scaledToFit().padding(10)
                        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                } else {
                    VStack(spacing: 15) {
                        ZStack {
                            Circle().fill(.white.opacity(0.07)).frame(width: 88, height: 88)
                            Image(systemName: "viewfinder").font(.system(size: 40, weight: .light)).foregroundStyle(.white.opacity(0.9))
                        }
                        Text("حوّل صورة المنتج إلى Studio Pack").font(.title3.bold())
                        Text("عزل، تحسين، Depth، زوايا جديدة، 3D وAR Quick Look").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(35)
                }
                if processor.isProcessing || hf.isBusy {
                    RoundedRectangle(cornerRadius: 30).fill(.black.opacity(0.68))
                    VStack(spacing: 11) {
                        ProgressView().controlSize(.large)
                        Text(processor.isProcessing ? "نجهز المنتج…" : hf.progressText)
                            .font(.subheadline.bold()).multilineTextAlignment(.center).padding(.horizontal, 24)
                    }
                    .padding(.bottom, 130)
                }
            }
            .frame(height: 370)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack {
                    Image(systemName: processor.source == nil ? "photo.badge.plus" : "arrow.triangle.2.circlepath.camera")
                    Text(processor.source == nil ? "اختيار صورة المنتج" : "تغيير صورة المنتج")
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous)).foregroundStyle(.black)
            }
            .disabled(processor.isProcessing || hf.isBusy)
        }
    }

    private var localStudio: some View {
        sectionCard(title: "Studio Pack", subtitle: "معالجة فورية على الآيفون — بدون رفع للسيرفر") {
            VStack(spacing: 14) {
                Picker("Result", selection: $selectedResult) {
                    Text("شفاف").tag(0); Text("أبيض").tag(1); Text("رمادي").tag(2); Text("دافئ").tag(3); Text("محسّن").tag(4)
                }.pickerStyle(.segmented)
                if let image = localResult {
                    ZStack {
                        if selectedResult == 0 { checkerboard } else { Color.white.opacity(0.025) }
                        Image(uiImage: image).resizable().scaledToFit().padding(8)
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.06)))
                    HStack(spacing: 10) {
                        ShareLink(item: ImageTransferable(image: image), preview: SharePreview("Object Studio", image: Image(uiImage: image))) {
                            Label("مشاركة", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }.buttonStyle(SecondaryButtonStyle())
                        Button { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) } label: {
                            Label("حفظ", systemImage: "arrow.down.to.line").frame(maxWidth: .infinity)
                        }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private var aiTools: some View {
        sectionCard(title: "AI Lab", subtitle: "Hugging Face — يستخدم حسابك وحصتك") {
            VStack(spacing: 11) {
                aiButton(icon: "square.3.layers.3d.down.right", title: "Depth Map", subtitle: "Depth Anything V2", action: {
                    guard let image = processor.source else { return }; Task { await hf.generateDepth(from: image) }
                })
                aiButton(icon: "camera.rotate", title: "4 زوايا جديدة", subtitle: "Qwen Image Edit — ±45° و ±90°", action: {
                    guard let image = processor.transparent ?? processor.source else { return }; Task { await hf.generateAngles(from: image) }
                })
                aiButton(icon: "cube.fill", title: "إنشاء مجسم 3D", subtitle: "Hunyuan3D 2.1 — مجسم وخامات", badge: "GPU", action: {
                    guard let image = processor.transparent ?? processor.source else { return }; Task { await hf.generate3D(from: image, textured: true) }
                })
                aiButton(icon: "arkit", title: "USDZ + AR Quick Look", subtitle: "إنشاء نسخة متوافقة مع واقع آبل المعزز", badge: "AR", action: {
                    guard let image = processor.transparent ?? processor.source else { return }
                    Task {
                        await hf.generateARUSDZ(from: image)
                        if hf.usdzURL != nil { showAR = true }
                    }
                })
            }
        }
    }

    private func depthSection(_ image: UIImage) -> some View {
        sectionCard(title: "Depth", subtitle: "خريطة عمق من الصورة") {
            VStack(spacing: 12) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 310).clipShape(RoundedRectangle(cornerRadius: 20))
                HStack(spacing: 10) {
                    ShareLink(item: ImageTransferable(image: image), preview: SharePreview("Depth Map", image: Image(uiImage: image))) {
                        Label("مشاركة", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }.buttonStyle(SecondaryButtonStyle())
                    Button { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) } label: {
                        Label("حفظ", systemImage: "arrow.down.to.line").frame(maxWidth: .infinity)
                    }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var angleSection: some View {
        sectionCard(title: "Multi-angle", subtitle: "زوايا مولدة لنفس المنتج") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(hf.angleImages.indices, id: \.self) { index in
                        let image = hf.angleImages[index]
                        VStack(alignment: .leading, spacing: 7) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 230, height: 230).clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                            HStack {
                                Text(["-90°", "-45°", "+45°", "+90°"][min(index, 3)]).font(.caption.bold())
                                Spacer()
                                ShareLink(item: ImageTransferable(image: image), preview: SharePreview("Angle", image: Image(uiImage: image))) { Image(systemName: "square.and.arrow.up") }
                            }.padding(.horizontal, 4)
                        }
                    }
                }
            }
        }
    }

    private func modelSection(_ url: URL) -> some View {
        sectionCard(title: "3D Asset", subtitle: hf.usdzURL == nil ? "ملف Hunyuan3D جاهز للعرض والتصدير" : "3D + USDZ جاهزان، ويمكن فتح AR Quick Look") {
            VStack(spacing: 12) {
                Button { show3D = true } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22).fill(.white.opacity(0.045)).frame(height: 220)
                        VStack(spacing: 12) {
                            Image(systemName: "rotate.3d").font(.system(size: 48, weight: .light))
                            Text("فتح العرض التفاعلي").font(.headline)
                            Text("اسحب لتدوير المجسم وكبّر بإصبعين").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.buttonStyle(.plain)

                if let usdz = hf.usdzURL {
                    Button { showAR = true } label: {
                        Label("فتح AR Quick Look", systemImage: "arkit").frame(maxWidth: .infinity)
                    }.buttonStyle(PrimaryARButtonStyle())
                    HStack(spacing: 10) {
                        ShareLink(item: usdz) { Label("تصدير USDZ", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
                        ShareLink(item: url) { Label("تصدير \(url.pathExtension.uppercased())", systemImage: "cube").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
                    }
                } else {
                    HStack(spacing: 10) {
                        ShareLink(item: url) { Label("تصدير \(url.pathExtension.uppercased())", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
                        Button {
                            guard let image = processor.transparent ?? processor.source else { return }
                            Task { await hf.generateARUSDZ(from: image); if hf.usdzURL != nil { showAR = true } }
                        } label: { Label("إنشاء USDZ", systemImage: "arkit").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private func aiButton(icon: String, title: String, subtitle: String, badge: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).frame(width: 46, height: 46)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(title).font(.subheadline.bold()); if let badge { Text(badge).font(.system(size: 9, weight: .black)).padding(.horizontal, 6).padding(.vertical, 3).background(.white.opacity(0.12), in: Capsule()) } }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain).disabled(hf.isBusy)
    }

    private func sectionCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.title3.bold()); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            content()
        }
        .padding(15)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.06)))
    }

    private func errorCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(text).font(.footnote).foregroundStyle(.white.opacity(0.88)); Spacer()
        }
        .padding(14).background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private var localResult: UIImage? {
        switch selectedResult {
        case 1: return processor.whiteBackground
        case 2: return processor.studioGray
        case 3: return processor.warmBackground
        case 4: return processor.enhanced
        default: return processor.transparent
        }
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let tile: CGFloat = 18
            for y in stride(from: 0.0, to: size.height, by: tile) {
                for x in stride(from: 0.0, to: size.width, by: tile) {
                    let alt = (Int(x / tile) + Int(y / tile)).isMultiple(of: 2)
                    context.fill(Path(CGRect(x: x, y: y, width: tile, height: tile)), with: .color(alt ? .gray.opacity(0.18) : .gray.opacity(0.07)))
                }
            }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var service: HuggingFaceService
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var showToken = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Hugging Face") {
                    HStack {
                        if showToken { TextField("hf_...", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled() }
                        else { SecureField("hf_...", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled() }
                        Button { showToken.toggle() } label: { Image(systemName: showToken ? "eye.slash" : "eye") }
                    }
                    Text("التوكن يُحفظ في Keychain على الجهاز ولا يوضع داخل كود التطبيق.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Advanced endpoints") {
                    TextField("Qwen Space", text: $service.qwenHost).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Hunyuan3D Space", text: $service.hunyuanHost).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Depth model", text: $service.depthModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    Link("إنشاء Hugging Face Token", destination: URL(string: "https://huggingface.co/settings/tokens")!)
                } footer: {
                    Text("استخدم Read token للتطبيق. نماذج ZeroGPU قد تتطلب تسجيل دخول وحصة GPU متاحة في حساب Hugging Face.")
                }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("حفظ") { service.token = token.trimmingCharacters(in: .whitespacesAndNewlines); dismiss() }.bold() }
            }
            .onAppear { token = service.token }
        }
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.bold()).padding(.vertical, 13)
            .background(.white.opacity(configuration.isPressed ? 0.14 : 0.075), in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
    }
}

private struct PrimaryARButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).padding(.vertical, 14)
            .background(.white.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 15)).foregroundStyle(.black)
    }
}
