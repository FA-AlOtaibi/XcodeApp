import SwiftUI

struct SubtitleViewerView: View {
    let item: LocalMedia
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "captions.bubble.fill")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.url.deletingPathExtension().lastPathComponent)
                            .font(.headline).lineLimit(2)
                        Text(item.ext.uppercased())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShareLink(item: item.url) { Image(systemName: "square.and.arrow.up") }
                }

                if text.isEmpty {
                    ContentUnavailableView("الملف فارغ", systemImage: "captions.bubble")
                        .frame(maxWidth: .infinity).padding(.top, 80)
                } else {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(16)
        }
        .navigationTitle("الترجمة")
        .navigationBarTitleDisplayMode(.inline)
        .task { text = (try? String(contentsOf: item.url, encoding: .utf8)) ?? "" }
    }
}
