import SwiftUI
import UniformTypeIdentifiers

struct ImageTransferable: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { value in
            guard let data = value.image.pngData() else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
        .suggestedFileName("ObjectStudio.png")
    }
}
