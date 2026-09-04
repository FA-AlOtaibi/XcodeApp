import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var model = VideoModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("← Back to Tools").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        Text("FPS Converter: Change Video Frame Rate")
                            .font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1)
                        Text("Upload a video, pick a target frame rate, and download it converted. Simple mode is fast; Smooth mode creates real in-between frames.")
                            .font(.body).foregroundStyle(.secondary).lineSpacing(4)
                    }.frame(maxWidth: .infinity, alignment: .leading)

                    PhotosPicker(selection: $pickerItem, matching: .videos) {
                        VStack(spacing: 14) {
                            Image(systemName: "arrow.up.doc").font(.system(size: 30, weight: .medium))
                            Text(model.input == nil ? "Drop a video here or click to upload" : "Choose a different video").font(.headline)
                            Text("MP4, MOV, WebM, MKV").font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 34)
                        .background(.white)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7])).foregroundStyle(.gray.opacity(0.45)))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)

                    if let info = model.input {
                        VStack(spacing: 18) {
                            HStack(spacing: 12) {
                                Image(systemName: "film.fill").font(.title2).frame(width: 46, height: 46).background(.black.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(info.name).font(.headline).lineLimit(1)
                                    Text("\(info.resolutionText) · \(info.fpsText) · \(info.durationText) · \(info.sizeText)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Target frame rate").font(.headline)
                                HStack(spacing: 8) {
                                    ForEach(model.fpsOptions, id: \.self) { fps in
                                        Button("\(fps) FPS") { model.targetFPS = fps }
                                            .font(.subheadline.weight(.semibold))
                                            .padding(.horizontal, 13).padding(.vertical, 10)
                                            .foregroundStyle(model.targetFPS == fps ? .white : .primary)
                                            .background(model.targetFPS == fps ? .black : .white)
                                            .clipShape(RoundedRectangle(cornerRadius: 9))
                                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.black.opacity(model.targetFPS == fps ? 0 : 0.12)))
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Conversion mode").font(.headline)
                                Picker("Mode", selection: $model.mode) {
                                    ForEach(VideoModel.Mode.allCases) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented)
                                Text(model.mode == .simple ? "Fast: drops or duplicates frames." : "Motion-compensated interpolation: generates new frames between originals for genuinely smoother motion.")
                                    .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(18).background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black.opacity(0.08)))

                        Button {
                            Task { await model.convert() }
                        } label: {
                            HStack { Image(systemName: "wand.and.stars"); Text("Convert to \(model.targetFPS) FPS") }
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16).foregroundStyle(.white).background(.black).clipShape(RoundedRectangle(cornerRadius: 12))
                        }.disabled(model.isProcessing)
                    }

                    if model.isProcessing {
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.large)
                            Text(model.stageText).font(.headline).multilineTextAlignment(.center)
                            if model.mode == .smooth { Text("Smooth mode is CPU-intensive and may take much longer than the clip duration.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                        }.frame(maxWidth: .infinity).padding(24).background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    if let out = model.output {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Conversion complete").font(.headline) }
                            Text("\(out.resolutionText) · \(out.fpsText) · \(out.sizeText)").font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                Button("Save to Photos") { model.saveToPhotos() }.buttonStyle(.borderedProminent).tint(.black)
                                Button("Share") { showShare = true }.buttonStyle(.bordered)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Simple vs Smooth").font(.title2.bold())
                        Text("Simple mode uses frame dropping/duplication. Smooth mode analyzes motion and synthesizes in-between frames, which is best for 24→60 or 30→60 FPS.")
                            .foregroundStyle(.secondary).lineSpacing(4)
                        Text("Everything is processed locally on your iPhone, and the original video resolution is preserved.").foregroundStyle(.secondary).lineSpacing(4)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 28)
                }
                .padding(.horizontal, 20).padding(.vertical, 24)
            }
            .background(Color(red: 0.985, green: 0.985, blue: 0.99))
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showShare) { if let url = model.output?.url { ShareSheet(items: [url]) } }
        .alert("Saved", isPresented: $model.showSaved) { Button("OK", role: .cancel) {} }
        .alert("Couldn’t convert", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.errorText ?? "") }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { if let movie = try? await item.loadTransferable(type: MovieTransferable.self) { await model.setInput(url: movie.url) } }
        }
    }
}
