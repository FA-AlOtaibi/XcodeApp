import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
final class ImageProcessor: ObservableObject {
    @Published var source: UIImage?
    @Published var transparent: UIImage?
    @Published var whiteBackground: UIImage?
    @Published var blackBackground: UIImage?
    @Published var isProcessing = false
    @Published var errorMessage: String?

    private let context = CIContext()

    func process(_ image: UIImage) async {
        source = image
        transparent = nil
        whiteBackground = nil
        blackBackground = nil
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        do {
            let cutout = try await removeBackground(from: image)
            transparent = cutout
            whiteBackground = composite(cutout, background: .white)
            blackBackground = composite(cutout, background: .black)
        } catch {
            errorMessage = "تعذر عزل المنتج تلقائيًا. جرّب صورة أوضح وخلفية أبسط."
        }
    }

    private func removeBackground(from image: UIImage) async throws -> UIImage {
        guard let cgImage = image.cgImage else { throw NSError(domain: "ObjectStudio", code: 1) }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])
        guard let result = request.results?.first else { throw NSError(domain: "ObjectStudio", code: 2) }

        let maskBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        let maskImage = CIImage(cvPixelBuffer: maskBuffer)
        let inputImage = CIImage(cgImage: cgImage)

        let filter = CIFilter.blendWithMask()
        filter.inputImage = inputImage
        filter.backgroundImage = CIImage.empty()
        filter.maskImage = maskImage

        guard let output = filter.outputImage,
              let outputCG = context.createCGImage(output, from: inputImage.extent) else {
            throw NSError(domain: "ObjectStudio", code: 3)
        }
        return UIImage(cgImage: outputCG, scale: image.scale, orientation: image.imageOrientation)
    }

    private func composite(_ foreground: UIImage, background: UIColor) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: foreground.size)
        return renderer.image { ctx in
            background.setFill()
            ctx.fill(CGRect(origin: .zero, size: foreground.size))
            foreground.draw(in: CGRect(origin: .zero, size: foreground.size))
        }
    }
}
