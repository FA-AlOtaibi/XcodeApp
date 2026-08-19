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
    @Published var status = "جاهز"
    @Published var renderedImage: UIImage?
    @Published var modelReady = false
    @Published var fps: Double = 0

    private let sessionQueue = DispatchQueue(label: "DepthLight.Session")
    private let videoQueue = DispatchQueue(label: "DepthLight.Video", qos: .userInitiated)
    private let modelQueue = DispatchQueue(label: "DepthLight.Model", qos: .utility)
    private let videoOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?

    private let engineLock = NSLock()
    private var _engine: DepthEngine?
    private var engine: DepthEngine? {
        engineLock.lock(); defer { engineLock.unlock() }
        return _engine
    }

    private var latestImage: UIImage?
    private var lastFrameTime = CACurrentMediaTime()
    private var lastInferenceTime: CFTimeInterval = 0
    private let inferenceInterval: CFTimeInterval = 1.0 / 8.0

    private let settingsLock = NSLock()
    private var settings = LightingSettings()

    override init() {
        super.init()
        // Important: do not construct Core ML / Metal synchronously during app launch.
        // The old version did this in init(), which could make iOS terminate the app
        // before the first frame was shown on some devices/signing setups.
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

        loadEngineSafelyIfNeeded()
    }

    private func loadEngineSafelyIfNeeded() {
        guard engine == nil, !modelReady else { return }
        DispatchQueue.main.async { self.status = "الكاميرا تعمل — جاري تحميل Core ML…" }

        modelQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                do {
                    let newEngine = try DepthEngine()
                    self.engineLock.lock()
                    self._engine = newEngine
                    self.engineLock.unlock()
                    DispatchQueue.main.async {
                        self.modelReady = true
                        self.status = "Depth Anything V2 + Metal جاهز"
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.modelReady = false
                        self.status = "وضع الكاميرا الآمن — Core ML: \(error.localizedDescription)"
                    }
                }
            }
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

            if !self.session.outputs.contains(self.videoOutput) {
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
            let deviceTypes: [AVCaptureDevice.DeviceType] = self.isFrontCamera
                ? [.builtInTrueDepthCamera, .builtInWideAngleCamera]
                : [.builtInWideAngleCamera, .builtInUltraWideCamera]

            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: position
            )

            guard let device = discovery.devices.first,
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
                if self.modelReady { self.status = "Depth Anything V2 + Metal يعمل" }
            }
        }
    }

    func switchCamera() {
        isFrontCamera.toggle()
        configureAndStart()
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
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let now = CACurrentMediaTime()
        let currentEngine = engine

        // Until the model is ready, show the camera immediately. Once ready,
        // throttle expensive depth inference to ~8 FPS to avoid jetsam/watchdog exits.
        if currentEngine != nil, now - lastInferenceTime < inferenceInterval {
            return
        }
        if currentEngine != nil { lastInferenceTime = now }

        settingsLock.lock()
        let currentSettings = settings
        settingsLock.unlock()

        autoreleasepool {
            let image: UIImage?
            if let currentEngine {
                image = currentEngine.process(pixelBuffer: pixelBuffer, settings: currentSettings)
            } else {
                image = UIImage(pixelBuffer: pixelBuffer)
            }

            guard let image else { return }
            latestImage = image
            let currentFPS = 1.0 / max(now - lastFrameTime, 0.001)
            lastFrameTime = now

            DispatchQueue.main.async {
                self.renderedImage = image
                self.fps = self.fps == 0 ? currentFPS : (self.fps * 0.85 + currentFPS * 0.15)
            }
        }
    }
}

private extension UIImage {
    convenience init?(pixelBuffer: CVPixelBuffer) {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return nil }
        self.init(cgImage: cg)
    }
}
