import SwiftUI

struct UnifiedFileActionsSheet: View {
    @ObservedObject var model: AppModel
    let item: LocalMedia
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var showEditor = false
    @State private var showShare = false
    @State private var confirmDelete = false

    private let olive = Color(red: 0.27, green: 0.33, blue: 0.18)
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 12) {
                        LocalThumb(item: item)
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.url.deletingPathExtension().lastPathComponent)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(model.formattedBytes(item.size)) • \(item.ext.uppercased())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .frame(width: 34, height: 34)
                                .background(Color.primary.opacity(0.07), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if item.isVideo {
                        sectionTitle("ذكي", icon: "sparkles")
                        LazyVGrid(columns: columns, spacing: 10) {
                            smartTile("Smart Clip", "sparkles.rectangle.stack") { await model.smartClipV3(item) }
                            smartTile("ترجمة عربية", "captions.bubble") { await model.burnSubtitlesV3(item, target: "ar") }
                            smartTile("حذف الصمت", "waveform.slash") { await model.removeSilenceV3(item) }
                            smartTile("تتبع 9:16", "person.crop.rectangle") { await model.autoReframeV3(item) }
                            smartTile("تنظيف الصوت", "waveform.badge.minus") { await model.cleanAudioV3(item) }
                            smartTile("صور غلاف", "photo.stack") { await model.thumbnailMakerV3(item) }
                        }

                        sectionTitle("الصوت", icon: "waveform")
                        LazyVGrid(columns: columns, spacing: 10) {
                            smartTile("إبقاء الكلام", "mic.fill") { await model.separateWithDemucs(from: item, keepVoice: true) }
                            smartTile("إبقاء الموسيقى", "music.note") { await model.separateWithDemucs(from: item, keepVoice: false) }
                            smartTile("رفع وضوح الكلام", "person.wave.2") { await model.boostSpeechV3(item) }
                            smartTile("استخراج الصوت", "waveform") { await model.extractAudio(from: item) }
                        }
                    }

                    sectionTitle("الملف", icon: "ellipsis.circle")
                    LazyVGrid(columns: columns, spacing: 10) {
                        if item.isVideo {
                            tile("تعديل", "slider.horizontal.3") { showEditor = true }
                            tile("حفظ في الصور", "photo.badge.plus") { Task { await model.saveExistingToPhotos(item.url) } }
                        }
                        tile("مشاركة", "square.and.arrow.up") { showShare = true }
                        tile("اسم مرتب", "textformat") { model.autoRename(item); dismiss() }
                    }

                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("نقل إلى سلة المهملات", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .navigationBarHidden(true)
            .overlay {
                if busy {
                    ZStack {
                        Color.black.opacity(0.16).ignoresSafeArea()
                        VStack(spacing: 10) {
                            ProgressView().controlSize(.large)
                            Text("جارٍ التنفيذ…").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showEditor) {
            NavigationStack {
                MediaEditorView(sourceURL: item.url, model: model)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("تم") { showEditor = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showShare) { ActivityShareSheet(items: [item.url]) }
        .confirmationDialog("نقل الملف إلى سلة المهملات؟", isPresented: $confirmDelete) {
            Button("نقل إلى السلة", role: .destructive) {
                model.moveToTrash(item)
                model.refreshStorage()
                dismiss()
            }
            Button("إلغاء", role: .cancel) {}
        }
    }

    private func sectionTitle(_ text: String, icon: String) -> some View {
        HStack {
            Label(text, systemImage: icon).font(.headline)
            Spacer()
        }
    }

    private func smartTile(_ title: String, _ icon: String, work: @escaping () async -> Void) -> some View {
        Button {
            guard !busy else { return }
            busy = true
            Task {
                await work()
                busy = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(olive)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func tile(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).foregroundStyle(olive)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(13)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
