import AVFoundation
import Photos
import SwiftUI
import UIKit

struct LightingSettings {
    var position = CGPoint(x: 0.74, y: 0.58)
    var intensity: Float = 0.8
    var radius: Float = 0.32
    var depthStrength: Float = 1.0
    var color = SIMD3<Float>(0.15, 0.50, 1.0)
}

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    @Published var isRunning = false
    @Published var isFrontCamera = true
    @Published var status = "جاري التجهيز…"
    @Published var renderedImage: UIImage?
    @Published var modelReady = false
    @Published var fps: Double = 0

    private let sessionQueue = DispatchQueue(label: "DepthLight.Session")
    private let videoQueue = DispatchQueue(label: "DepthLight.Video", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var engine: DepthEngine?
    private var latestImage: UIImage?
    private var processing = false
    private var lastFrameTime = CACurrentMediaTime()

    private let settingsLock = NSLock()
    private var settings = LightingSettings()

    override init() {
        super.init()
        do {
            engine = try DepthEngine()
            modelReady = true
            status = "Core ML + Metal جاهز"
        } catch {
            modelReady = false
            status = "تعذر تحميل نموذج العمق: \(error.localizedDescription)"
        }
    }

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureAndStart()
                } else {
                    DispatchQueue.main.async { self?.status = "تم رفض إذن الكاميرا" }
                }
            }
        default:
            DispatchQueue.main.async { self.status = "فعّل إذن الكاميرا من الإعدادات" }
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            if let old = self.input {
                self.session.removeInput(old)
                self.input = nil
            }

            if self.session.outputs.contains(self.videoOutput) == false {
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                }
            }

            let position: AVCaptureDevice.Position = self.isFrontCamera ? .front : .back
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera, .builtInUltraWideCamera],
                mediaType: .video,
                position: position
            )

            guard let device = discovery.devices.first(where: { $0.position == position }),
                  let newInput = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(newInput) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.status = "لم أجد كاميرا مناسبة" }
                return
            }

            self.session.addInput(newInput)
            self.input = newInput

            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = self.isFrontCamera
                }
            }

            self.session.commitConfiguration()
            if !self.session.isRunning {
                self.session.startRunning()
            }

            DispatchQueue.main.async {
                self.isRunning = true
                self.status = self.modelReady ? "Depth Anything V2 + Metal يعمل" : self.status
            }
        }
    }

    func switchCamera() {
        DispatchQueue.main.async {
            self.isFrontCamera.toggle()
            self.configureAndStart()
        }
    }

    func updateLight(position: CGPoint? = nil,
                     intensity: Float? = nil,
                     radius: Float? = nil,
                     depthStrength: Float? = nil,
                     color: SIMD3<Float>? = nil) {
        settingsLock.lock()
        if let position { settings.position = position }
        if let intensity { settings.intensity = intensity }
        if let radius { settings.radius = radius }
        if let depthStrength { settings.depthStrength = depthStrength }
        if let color { settings.color = color }
        settingsLock.unlock()
    }

    func capture() {
        guard let image = latestImage else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] auth in
            guard auth == .authorized || auth == .limited else {
                DispatchQueue.main.async { self?.status = "لم يتم السماح بالحفظ" }
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            DispatchQueue.main.async { self?.status = "تم حفظ الصورة ✓" }
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !processing,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        processing = true
        settingsLock.lock()
        let currentSettings = settings
        settingsLock.unlock()

        autoreleasepool {
            let image: UIImage?
            if let engine {
                image = engine.process(pixelBuffer: pixelBuffer, settings: currentSettings)
            } else {
                image = UIImage(pixelBuffer: pixelBuffer)
            }

            if let image {
                latestImage = image
                let now = CACurrentMediaTime()
                let currentFPS = 1.0 / max(now - lastFrameTime, 0.001)
                lastFrameTime = now
                DispatchQueue.main.async {
                    self.renderedImage = image
                    self.fps = self.fps == 0 ? currentFPS : (self.fps * 0.85 + currentFPS * 0.15)
                }
            }
        }
        processing = false
    }
}

private extension UIImage {
    convenience init?(pixelBuffer: CVPixelBuffer) {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return nil }
        self.init(cgImage: cg)
    }
}
