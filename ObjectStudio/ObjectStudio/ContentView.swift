import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var processor = ImageProcessor()
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedResult = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        workspace
                        if processor.transparent != nil { results }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 36)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await processor.process(image)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OBJECT")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.secondary)
                Text("Studio")
                    .font(.system(size: 34, weight: .black, design: .rounded))
            }
            Spacer()
            Image(systemName: "cube.transparent")
                .font(.system(size: 25, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.top, 14)
    }

    private var workspace: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08))
                    }

                if let image = processor.source {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(8)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("اختر صورة منتج")
                            .font(.headline)
                        Text("صورة واضحة وخلفية بسيطة تعطي نتيجة أفضل")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if processor.isProcessing {
                    Rectangle()
                        .fill(.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large)
                        Text("نعزل المنتج…").font(.subheadline.weight(.semibold))
                    }
                }
            }
            .frame(height: 390)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(processor.source == nil ? "اختيار صورة" : "اختيار صورة أخرى", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.black)
            }

            if let message = processor.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Studio Pack")
                    .font(.title3.bold())
                Spacer()
                Text("3 نتائج")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Picker("النتيجة", selection: $selectedResult) {
                Text("شفاف").tag(0)
                Text("أبيض").tag(1)
                Text("أسود").tag(2)
            }
            .pickerStyle(.segmented)

            if let image = currentResult {
                ZStack {
                    checkerboard
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                }
                .frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                HStack(spacing: 12) {
                    ShareLink(item: ImageTransferable(image: image), preview: SharePreview("Object Studio", image: Image(uiImage: image))) {
                        Label("مشاركة", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StudioButtonStyle())

                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    } label: {
                        Label("حفظ", systemImage: "arrow.down.to.line")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StudioButtonStyle())
                }
            }

            featureRow(icon: "sparkles", title: "Background Removal", subtitle: "عزل المنتج على الجهاز — بدون سيرفر")
            featureRow(icon: "square.3.layers.3d", title: "Studio Backgrounds", subtitle: "نسخة شفافة + أبيض + أسود")
            featureRow(icon: "cube", title: "3D / Multi-angle", subtitle: "الواجهة مجهزة لإضافة موديل Hugging Face لاحقًا")
        }
        .padding(.top, 6)
    }

    private var currentResult: UIImage? {
        switch selectedResult {
        case 1: return processor.whiteBackground
        case 2: return processor.blackBackground
        default: return processor.transparent
        }
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let tile: CGFloat = 18
            for y in stride(from: 0.0, to: size.height, by: tile) {
                for x in stride(from: 0.0, to: size.width, by: tile) {
                    let isAlt = (Int(x / tile) + Int(y / tile)).isMultiple(of: 2)
                    context.fill(Path(CGRect(x: x, y: y, width: tile, height: tile)), with: .color(isAlt ? .gray.opacity(0.18) : .gray.opacity(0.08)))
                }
            }
        }
        .background(Color.white.opacity(0.04))
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct StudioButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .padding(.vertical, 13)
            .background(.white.opacity(configuration.isPressed ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 15))
    }
}
