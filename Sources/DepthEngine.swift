import CoreImage
import CoreML
import Metal
import UIKit

final class DepthEngine {
    enum EngineError: LocalizedError {
        case noMetalDevice
        case noCommandQueue
        case noLibrary
        case noKernel
        case pixelBuffer

        var errorDescription: String? {
            switch self {
            case .noMetalDevice: return "Metal غير متوفر على الجهاز"
            case .noCommandQueue: return "تعذر إنشاء Metal command queue"
            case .noLibrary: return "تعذر تحميل مكتبة Metal"
            case .noKernel: return "تعذر تحميل depthLightKernel"
            case .pixelBuffer: return "تعذر تجهيز مدخل Core ML"
            }
        }
    }

    private let targetWidth = 518
    private let targetHeight = 392

    private let model: DepthAnythingV2SmallF16
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let ciContext: CIContext
    private var textureCache: CVMetalTextureCache?
    private let inputPixelBuffer: CVPixelBuffer

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw EngineError.noMetalDevice }
        guard let commandQueue = device.makeCommandQueue() else { throw EngineError.noCommandQueue }
        guard let library = device.makeDefaultLibrary() else { throw EngineError.noLibrary }
        guard let function = library.makeFunction(name: "depthLightKernel") else { throw EngineError.noKernel }

        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = try device.makeComputePipelineState(function: function)
        self.ciContext = CIContext(mtlDevice: device)

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.textureCache = cache

        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetWidth,
            targetHeight,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &buffer
        )
        guard result == kCVReturnSuccess, let buffer else { throw EngineError.pixelBuffer }
        self.inputPixelBuffer = buffer

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        self.model = try DepthAnythingV2SmallF16(configuration: configuration)
    }

    func process(pixelBuffer: CVPixelBuffer, settings: LightingSettings) -> UIImage? {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sx = CGFloat(targetWidth) / max(sourceImage.extent.width, 1)
        let sy = CGFloat(targetHeight) / max(sourceImage.extent.height, 1)
        let resized = sourceImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        ciContext.render(resized, to: inputPixelBuffer)

        guard let prediction = try? model.prediction(image: inputPixelBuffer) else {
            return fallbackImage(pixelBuffer)
        }

        return render(camera: pixelBuffer, depth: prediction.depth, settings: settings) ?? fallbackImage(pixelBuffer)
    }

    private func render(camera: CVPixelBuffer,
                        depth: CVPixelBuffer,
                        settings: LightingSettings) -> UIImage? {
        guard let cameraTexture = texture(from: camera, pixelFormat: .bgra8Unorm),
              let depthFormat = metalDepthFormat(for: depth),
              let depthTexture = texture(from: depth, pixelFormat: depthFormat) else { return nil }

        let width = cameraTexture.width
        let height = cameraTexture.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let outputTexture = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        var uniforms = MetalUniforms(
            lightPosition: SIMD2<Float>(Float(width) * Float(settings.position.x),
                                        Float(height) * Float(settings.position.y)),
            lightColor: settings.color,
            intensity: settings.intensity,
            radius: Float(max(width, height)) * settings.radius,
            depthStrength: settings.depthStrength,
            width: UInt32(width),
            height: UInt32(height)
        )

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(cameraTexture, index: 0)
        encoder.setTexture(depthTexture, index: 1)
        encoder.setTexture(outputTexture, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalUniforms>.stride, index: 0)

        let threadWidth = pipeline.threadExecutionWidth
        let threadHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / threadWidth)
        let threadsPerGroup = MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        let threads = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard commandBuffer.status == .completed,
              let image = CIImage(mtlTexture: outputTexture,
                                  options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]),
              let cgImage = ciContext.createCGImage(image, from: image.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    private func texture(from pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        guard let textureCache else { return nil }
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess,
              let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
        return texture
    }

    private func metalDepthFormat(for pixelBuffer: CVPixelBuffer) -> MTLPixelFormat? {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_OneComponent16Half:
            return .r16Float
        case kCVPixelFormatType_OneComponent32Float:
            return .r32Float
        case kCVPixelFormatType_OneComponent8:
            return .r8Unorm
        default:
            return nil
        }
    }

    private func fallbackImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

private struct MetalUniforms {
    var lightPosition: SIMD2<Float>
    var lightColor: SIMD3<Float>
    var intensity: Float
    var radius: Float
    var depthStrength: Float
    var width: UInt32
    var height: UInt32
}
