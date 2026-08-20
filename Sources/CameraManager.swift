import AVFoundation
import Photos
import SwiftUI
import UIKit

struct LightingSettings {
    var position = CGPoint(x: 0.72, y: 0.50)
    var intensity: Float = 0.90
    var radius: Float = 0.42
    var depthStrength: Float = 0.92
    var color = SIMD3<Float>(1.0, 0.82, 0.60)
}

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDataOutputSynchronizerDelegate {
    let session = AVCaptureSession()

    @Published var isRunning = false
    @Published var isFrontCamera = true
    @Published var status = "جاهز"
    @Published var renderedImage: UIImage?
    @Published var modelReady = false
    @Published var fps: Double = 0
    @Published var depthMode = "RGB"

    private let sessionQueue = DispatchQueue(label: "DepthLight.Session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "DepthLight.Video", qos: .userInteractive)
    private let modelQueue = DispatchQueue(label: "DepthLight.Model", qos: .utility)

    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private var input: AVCaptureDeviceInput?
    private var trueDepthActive = false

    private let engineLock = NSLock()
    private var _engine: DepthEngine?
    private var engine: DepthEngine? {
        engineLock.lock(); defer { engineLock.unlock() }
        return _engine
    }

    private var latestImage: UIImage?
    private var lastFrameTime = CACurrentMediaTime()
    private var lastInferenceTime: CFTimeInterval = 0
    private let fallbackInferenceInterval: CFTimeInterval = 1.0 / 10.0
    private var renderBusy = false

    private let settingsLock = NSLock()
    private var settings = LightingSettings()

    override init() {
        super.init()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        depthOutput.isFilteringEnabled = true
        depthOutput.alwaysDiscardsLateDepthData = true
    }

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted { self.configureAndStart() }
                else { DispatchQueue.main.async { self.status = "تم رفض إذن الكاميرا" } }
            }
        default:
            DispatchQueue.main.async { self.status = "فعّل إذن الكاميرا من الإعدادات" }
        }
    }

    private func loadEngineSafelyIfNeeded() {
        guard engine == nil else { return }
        modelQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                do {
                    let newEngine = try DepthEngine()
                    self.engineLock.lock(); self._engine = newEngine; self.engineLock.unlock()
                    DispatchQueue.main.async {
                        if !self.trueDepthActive {
                            self.modelReady = true
                            self.depthMode = "AI DEPTH"
                            self.status = "AI Depth + Metal جاهز"
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        if !self.trueDepthActive {
                            self.modelReady = false
                            self.depthMode = "RGB"
                            self.status = "تعذر تشغيل محرك العمق: \(error.localizedDescription)"
                        }
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

            for existing in self.session.inputs { self.session.removeInput(existing) }
            for existing in self.session.outputs { self.session.removeOutput(existing) }
            self.synchronizer = nil
            self.trueDepthActive = false
            self.renderBusy = false

            let position: AVCaptureDevice.Position = self.isFrontCamera ? .front : .back
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: self.isFrontCamera
                    ? [.builtInTrueDepthCamera, .builtInWideAngleCamera]
                    : [.builtInWideAngleCamera, .builtInUltraWideCamera],
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

            guard self.session.canAddOutput(self.videoOutput) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.status = "تعذر إضافة إخراج الكاميرا" }
                return
            }
            self.session.addOutput(self.videoOutput)

            var canUseTrueDepth = false
            if self.isFrontCamera,
               device.deviceType == .builtInTrueDepthCamera,
               self.session.canAddOutput(self.depthOutput) {
                self.selectBestDepthFormat(for: device)
                self.session.addOutput(self.depthOutput)
                canUseTrueDepth = true
            }

            self.configureConnections(mirrored: self.isFrontCamera)

            if canUseTrueDepth {
                let sync = AVCaptureDataOutputSynchronizer(dataOutputs: [self.videoOutput, self.depthOutput])
                sync.setDelegate(self, queue: self.videoQueue)
                self.synchronizer = sync
                self.trueDepthActive = true
            } else {
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            }

            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }

            DispatchQueue.main.async {
                self.isRunning = true
                if canUseTrueDepth {
                    self.modelReady = true
                    self.depthMode = "TRUEDEPTH"
                    self.status = "TrueDepth مباشر — حجب وظلال عالية الدقة"
                } else {
                    self.modelReady = self.engine != nil
                    self.depthMode = self.engine == nil ? "LOADING" : "AI DEPTH"
                    self.status = "جاري تجهيز AI Depth…"
                    self.loadEngineSafelyIfNeeded()
                }
            }
        }
    }

    private func selectBestDepthFormat(for device: AVCaptureDevice) {
        let formats = device.activeFormat.supportedDepthDataFormats.filter { format in
            let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            return subtype == kCVPixelFormatType_DepthFloat32 || subtype == kCVPixelFormatType_DepthFloat16
        }
        guard let best = formats.max(by: {
            let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
            return Int(a.width) * Int(a.height) < Int(b.width) * Int(b.height)
        }) else { return }

        do {
            try device.lockForConfiguration()
            device.activeDepthDataFormat = best
            device.unlockForConfiguration()
        } catch { }
    }

    private func configureConnections(mirrored: Bool) {
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = mirrored }
        }
        if let connection = depthOutput.connection(with: .depthData) {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = mirrored }
        }
    }

    func switchCamera() {
        isFrontCamera.toggle()
        DispatchQueue.main.async {
            self.renderedImage = nil
            self.depthMode = "SWITCH"
            self.status = "جاري تبديل الكاميرا…"
        }
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

    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard !renderBusy,
              let videoData = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
              !videoData.sampleBufferWasDropped,
              let depthData = synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData,
              !depthData.depthDataWasDropped,
              let pixelBuffer = CMSampleBufferGetImageBuffer(videoData.sampleBuffer) else { return }

        let converted = depthData.depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let depthMap = converted.depthDataMap

        settingsLock.lock(); let currentSettings = settings; settingsLock.unlock()
        renderBusy = true

        do {
            let currentEngine: DepthEngine
            if let existing = engine {
                currentEngine = existing
            } else {
                let newEngine = try DepthEngine(loadModel: false)
                engineLock.lock(); _engine = newEngine; engineLock.unlock()
                currentEngine = newEngine
            }

            currentEngine.processMetricDepth(pixelBuffer: pixelBuffer, depth: depthMap, settings: currentSettings) { [weak self] image in
                guard let self else { return }
                self.videoQueue.async {
                    self.renderBusy = false
                    guard let image else { return }
                    self.publish(image: image)
                }
            }
        } catch {
            renderBusy = false
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !trueDepthActive,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let now = CACurrentMediaTime()
        guard now - lastInferenceTime >= fallbackInferenceInterval else { return }
        lastInferenceTime = now

        settingsLock.lock(); let currentSettings = settings; settingsLock.unlock()

        if let currentEngine = engine {
            autoreleasepool {
                if let image = currentEngine.process(pixelBuffer: pixelBuffer, settings: currentSettings) {
                    publish(image: image)
                }
            }
        } else if let image = UIImage(pixelBuffer: pixelBuffer) {
            publish(image: image)
        }
    }

    private func publish(image: UIImage) {
        latestImage = image
        let now = CACurrentMediaTime()
        let instantFPS = 1.0 / max(now - lastFrameTime, 0.001)
        lastFrameTime = now
        DispatchQueue.main.async {
            self.renderedImage = image
            self.fps = self.fps == 0 ? instantFPS : (self.fps * 0.82 + instantFPS * 0.18)
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
