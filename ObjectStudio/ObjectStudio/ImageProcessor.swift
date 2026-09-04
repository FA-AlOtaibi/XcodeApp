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
    @Published var studioGray: UIImage?
    @Published var warmBackground: UIImage?
    @Published var enhanced: UIImage?
    @Published var isProcessing = false
    @Published var errorMessage: String?

    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func process(_ image: UIImage) async {
        source = image.normalized()
        transparent = nil
        whiteBackground = nil
        blackBackground = nil
        studioGray = nil
        warmBackground = nil
        enhanced = nil
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        do {
            let normalized = image.normalized()
            let cutout = try await removeBackground(from: normalized)
            transparent = cutout
            whiteBackground = composite(cutout, background: .white, shadow: true)
            blackBackground = composite(cutout, background: .black, shadow: true)
            studioGray = composite(cutout, background: UIColor(white: 0.92, alpha: 1), shadow: true)
            warmBackground = composite(cutout, background: UIColor(red: 0.93, green: 0.90, blue: 0.84, alpha: 1), shadow: true)
            enhanced = enhance(normalized)
        } catch {
            errorMessage = "تعذر عزل المنتج تلقائيًا. جرّب صورة أوضح وخلفية أبسط."
        }
    }

    private func removeBackground(from image: UIImage) async throws -> UIImage {
        guard let cgImage = image.cgImage else { throw NSError(domain: "ObjectStudio", code: 1) }
        if #available(iOS 17.0, *) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            try handler.perform([request])
            guard let result = request.results?.first else { throw NSError(domain: "ObjectStudio", code: 2) }
            let maskBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            let maskImage = CIImage(cvPixelBuffer: maskBuffer)
            let inputImage = CIImage(cgImage: cgImage)
            let filter = CIFilter.blendWithMask()
            filter.inputImage = inputImage
            filter.backgroundImage = CIImage(color: .clear).cropped(to: inputImage.extent)
            filter.maskImage = maskImage
            guard let output = filter.outputImage,
                  let outputCG = context.createCGImage(output, from: inputImage.extent) else { throw NSError(domain: "ObjectStudio", code: 3) }
            return UIImage(cgImage: outputCG)
        }
        throw NSError(domain: "ObjectStudio", code: 4)
    }

    private func enhance(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        var current = CIImage(cgImage: cgImage)
        let color = CIFilter.colorControls()
        color.inputImage = current
        color.contrast = 1.08
        color.saturation = 1.04
        color.brightness = 0.015
        if let out = color.outputImage { current = out }
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = current
        sharpen.sharpness = 0.45
        if let out = sharpen.outputImage { current = out }
        guard let outCG = context.createCGImage(current, from: current.extent) else { return nil }
        return UIImage(cgImage: outCG)
    }

    private func composite(_ foreground: UIImage, background: UIColor, shadow: Bool) -> UIImage? {
        let size = foreground.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            background.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            if shadow {
                ctx.cgContext.saveGState()
                ctx.cgContext.setShadow(offset: CGSize(width: 0, height: max(8, size.height * 0.018)), blur: max(16, size.width * 0.03), color: UIColor.black.withAlphaComponent(background == .black ? 0.18 : 0.23).cgColor)
                foreground.draw(in: CGRect(origin: .zero, size: size))
                ctx.cgContext.restoreGState()
            } else {
                foreground.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }
}

private extension UIImage {
    func normalized() -> UIImage {
        if imageOrientation == .up { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
