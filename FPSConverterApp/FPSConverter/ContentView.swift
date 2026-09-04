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
                        Text("FPS + Quality Converter")
                            .font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1)
                        Text("Increase frame rate and improve video quality in one export. Smooth mode creates in-between frames, while 2K/4K modes upscale with high-quality Lanczos filtering, light denoise, sharpening, and a higher bitrate.")
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
                                Text("Output quality").font(.headline)
                                Picker("Quality", selection: $model.quality) {
                                    ForEach(VideoModel.Quality.allCases) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented)
                                Text(qualityDescription)
                                    .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                            }.frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Frame conversion").font(.headline)
                                Picker("Mode", selection: $model.mode) {
                                    ForEach(VideoModel.Mode.allCases) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented)
                                Text(model.mode == .simple ? "Fast: drops or duplicates frames." : "Motion-compensated interpolation: creates new in-between frames for genuinely smoother motion.")
                                    .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(18).background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black.opacity(0.08)))

                        Button {
                            Task { await model.convert() }
                        } label: {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text("Convert · \(model.targetFPS) FPS · \(model.quality.rawValue)")
                            }
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16).foregroundStyle(.white).background(.black).clipShape(RoundedRectangle(cornerRadius: 12))
                        }.disabled(model.isProcessing)
                    }

                    if model.isProcessing {
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.large)
                            Text(model.stageText).font(.headline).multilineTextAlignment(.center)
                            Text("Smooth + 4K can take a long time because motion interpolation is performed before the high-quality upscale.")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                        Text("What quality mode actually does").font(.title2.bold())
                        Text("Enhanced keeps the original dimensions but cleans and sharpens the image and exports at a higher bitrate. 2K and 4K also upscale the frame using Lanczos before export.")
                            .foregroundStyle(.secondary).lineSpacing(4)
                        Text("Upscaling improves presentation and output resolution, but it cannot recreate detail that was never present in a low-resolution source.")
                            .foregroundStyle(.secondary).lineSpacing(4)
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

    private var qualityDescription: String {
        switch model.quality {
        case .enhanced:
            return "Keep the source dimensions, reduce compression noise, recover edge detail, and export at a higher bitrate."
        case .twoK:
            return "Upscale toward a 2560-pixel long edge, then enhance and export at a higher bitrate."
        case .fourK:
            return "Upscale toward a 3840-pixel long edge, enhance detail, and use the highest bitrate. Best quality, slowest export."
        }
    }
}
