import CoreImage
import CoreML
import Metal
import UIKit

final class DepthEngine {
    enum EngineError: LocalizedError {
        case noMetalDevice, noCommandQueue, noKernel, pixelBuffer
        var errorDescription: String? {
            switch self {
            case .noMetalDevice: return "Metal غير متوفر على الجهاز"
            case .noCommandQueue: return "تعذر إنشاء Metal command queue"
            case .noKernel: return "تعذر تحميل Metal kernels"
            case .pixelBuffer: return "تعذر تجهيز مدخل Core ML"
            }
        }
    }

    private let targetWidth = 518
    private let targetHeight = 392
    private let model: DepthAnythingV2SmallF16?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let aiPipeline: MTLComputePipelineState
    private let metricPipeline: MTLComputePipelineState
    private let ciContext: CIContext
    private var textureCache: CVMetalTextureCache?
    private let inputPixelBuffer: CVPixelBuffer?

    private let depthLock = NSLock()
    private var smoothedSubjectDepth: Float = 0.55
    private var depthFrameCounter = 0

    convenience init() throws { try self.init(loadModel: true) }

    init(loadModel: Bool) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw EngineError.noMetalDevice }
        guard let commandQueue = device.makeCommandQueue() else { throw EngineError.noCommandQueue }
        guard let library = device.makeDefaultLibrary(),
              let aiFunction = library.makeFunction(name: "depthLightKernel"),
              let metricFunction = library.makeFunction(name: "trueDepthRelightKernel") else {
            throw EngineError.noKernel
        }

        self.device = device
        self.commandQueue = commandQueue
        self.aiPipeline = try device.makeComputePipelineState(function: aiFunction)
        self.metricPipeline = try device.makeComputePipelineState(function: metricFunction)
        self.ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.textureCache = cache

        if loadModel {
            var buffer: CVPixelBuffer?
            let attrs: [CFString: Any] = [
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ]
            let result = CVPixelBufferCreate(kCFAllocatorDefault, targetWidth, targetHeight,
                                             kCVPixelFormatType_32ARGB, attrs as CFDictionary, &buffer)
            guard result == kCVReturnSuccess, let buffer else { throw EngineError.pixelBuffer }
            self.inputPixelBuffer = buffer
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            self.model = try DepthAnythingV2SmallF16(configuration: configuration)
        } else {
            self.inputPixelBuffer = nil
            self.model = nil
        }
    }

    func process(pixelBuffer: CVPixelBuffer, settings: LightingSettings) -> UIImage? {
        guard let model, let inputPixelBuffer else { return fallbackImage(pixelBuffer) }
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let sourceSize = source.extent.size
        let scale = min(CGFloat(targetWidth) / sourceSize.width, CGFloat(targetHeight) / sourceSize.height)
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let x = (CGFloat(targetWidth) - scaled.extent.width) * 0.5
        let y = (CGFloat(targetHeight) - scaled.extent.height) * 0.5
        let composed = scaled.transformed(by: CGAffineTransform(translationX: x, y: y))
        let canvas = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        ciContext.render(composed.composited(over: canvas), to: inputPixelBuffer)
        guard let prediction = try? model.prediction(image: inputPixelBuffer) else { return fallbackImage(pixelBuffer) }
        return renderAIDepth(camera: pixelBuffer, depth: prediction.depth, settings: settings) ?? fallbackImage(pixelBuffer)
    }

    func processMetricDepth(pixelBuffer: CVPixelBuffer,
                            depth: CVPixelBuffer,
                            settings: LightingSettings,
                            completion: @escaping (UIImage?) -> Void) {
        guard let cameraTexture = texture(from: pixelBuffer, pixelFormat: .bgra8Unorm),
              let depthTexture = texture(from: depth, pixelFormat: .r32Float) else {
            completion(nil); return
        }

        depthFrameCounter += 1
        if depthFrameCounter % 3 == 0 { updateSubjectDepth(from: depth) }
        depthLock.lock(); let subjectDepth = smoothedSubjectDepth; depthLock.unlock()

        let width = cameraTexture.width
        let height = cameraTexture.height
        let depthWidth = depthTexture.width
        let depthHeight = depthTexture.height
        let cameraAspect = Float(width) / Float(max(height, 1))
        let rawDepthAspect = Float(depthWidth) / Float(max(depthHeight, 1))
        let cameraPortrait = height >= width
        let depthPortrait = depthHeight >= depthWidth
        let rotateDepth: Float = cameraPortrait == depthPortrait ? 0 : 1
        let effectiveDepthAspect = rotateDepth > 0.5 ? 1.0 / max(rawDepthAspect, 0.001) : rawDepthAspect

        let lightDepth = max(0.18, subjectDepth - 0.08)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                   width: width,
                                                                   height: height,
                                                                   mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared

        guard let output = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            completion(nil); return
        }

        var uniforms = V7Uniforms(
            lightPosition: SIMD2<Float>(Float(settings.position.x), Float(settings.position.y)),
            lightDepth: lightDepth,
            radius: settings.radius,
            colorIntensity: SIMD4<Float>(settings.color.x, settings.color.y, settings.color.z, settings.intensity),
            params: SIMD4<Float>(settings.depthStrength, subjectDepth, min(subjectDepth + 0.70, 2.0), 0),
            mapping: SIMD4<Float>(cameraAspect, effectiveDepthAspect, rotateDepth, 0),
            dimensions: SIMD2<UInt32>(UInt32(width), UInt32(height)),
            padding: .zero
        )

        encoder.setComputePipelineState(metricPipeline)
        encoder.setTexture(cameraTexture, index: 0)
        encoder.setTexture(depthTexture, index: 1)
        encoder.setTexture(output, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<V7Uniforms>.stride, index: 0)
        dispatch(encoder: encoder, pipeline: metricPipeline, width: width, height: height)
        encoder.endEncoding()

        commandBuffer.addCompletedHandler { [ciContext] buffer in
            guard buffer.status == .completed,
                  let ci = CIImage(mtlTexture: output, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]),
                  let cg = ciContext.createCGImage(ci, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
                completion(nil); return
            }
            completion(UIImage(cgImage: cg))
        }
        commandBuffer.commit()
    }

    private func renderAIDepth(camera: CVPixelBuffer, depth: CVPixelBuffer, settings: LightingSettings) -> UIImage? {
        guard let cameraTexture = texture(from: camera, pixelFormat: .bgra8Unorm),
              let depthFormat = metalDepthFormat(for: depth),
              let depthTexture = texture(from: depth, pixelFormat: depthFormat) else { return nil }
        let width = cameraTexture.width, height = cameraTexture.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let output = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        var uniforms = MetalUniforms(lightPosition: SIMD2<Float>(Float(width) * Float(settings.position.x), Float(height) * Float(settings.position.y)),
                                     lightColor: settings.color,
                                     intensity: min(settings.intensity, 0.72),
                                     radius: Float(max(width, height)) * settings.radius,
                                     depthStrength: settings.depthStrength,
                                     width: UInt32(width), height: UInt32(height))
        encoder.setComputePipelineState(aiPipeline)
        encoder.setTexture(cameraTexture, index: 0)
        encoder.setTexture(depthTexture, index: 1)
        encoder.setTexture(output, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalUniforms>.stride, index: 0)
        dispatch(encoder: encoder, pipeline: aiPipeline, width: width, height: height)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed,
              let image = CIImage(mtlTexture: output, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]),
              let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func updateSubjectDepth(from depth: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
              let base = CVPixelBufferGetBaseAddress(depth) else { return }
        let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
        let stride = CVPixelBufferGetBytesPerRow(depth) / MemoryLayout<Float>.size
        let ptr = base.assumingMemoryBound(to: Float.self)
        let x0 = Int(Float(width) * 0.30), x1 = Int(Float(width) * 0.70)
        let y0 = Int(Float(height) * 0.22), y1 = Int(Float(height) * 0.72)
        let step = max(3, min(width, height) / 48)
        var values: [Float] = []
        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                let v = ptr[y * stride + x]
                if v.isFinite, v > 0.18, v < 1.55 { values.append(v) }
                x += step
            }
            y += step
        }
        guard values.count > 20 else { return }
        values.sort()
        let median = values[values.count / 2]
        depthLock.lock()
        let alpha: Float = abs(median - smoothedSubjectDepth) > 0.25 ? 0.08 : 0.20
        smoothedSubjectDepth = smoothedSubjectDepth * (1 - alpha) + median * alpha
        depthLock.unlock()
    }

    private func dispatch(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let tw = pipeline.threadExecutionWidth
        let th = max(1, pipeline.maxTotalThreadsPerThreadgroup / tw)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
    }

    private func texture(from pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        guard let textureCache else { return nil }
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, pixelFormat,
                                                               CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
        return texture
    }

    private func metalDepthFormat(for pixelBuffer: CVPixelBuffer) -> MTLPixelFormat? {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_OneComponent16Half: return .r16Float
        case kCVPixelFormatType_OneComponent32Float: return .r32Float
        case kCVPixelFormatType_OneComponent8: return .r8Unorm
        default: return nil
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

private struct V7Uniforms {
    var lightPosition: SIMD2<Float>
    var lightDepth: Float
    var radius: Float
    var colorIntensity: SIMD4<Float>
    var params: SIMD4<Float>
    var mapping: SIMD4<Float>
    var dimensions: SIMD2<UInt32>
    var padding: SIMD2<UInt32>
}
