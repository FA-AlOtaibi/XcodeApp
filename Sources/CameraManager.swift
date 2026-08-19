import AVFoundation
import Photos
import SwiftUI
import UIKit

final class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "DepthLight.Camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?

    @Published var isRunning = false
    @Published var isFrontCamera = true
    @Published var depthCapable = false
    @Published var status = "جاهز"

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else {
                    DispatchQueue.main.async { self?.status = "تم رفض إذن الكاميرا" }
                    return
                }
                self?.configureAndStart()
            }
        default:
            DispatchQueue.main.async { self.status = "فعّل إذن الكاميرا من الإعدادات" }
        }
    }

    private func configureAndStart() {
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            if let old = self.input { self.session.removeInput(old) }
            if self.session.outputs.contains(self.photoOutput) == false,
               self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            let position: AVCaptureDevice.Position = self.isFrontCamera ? .front : .back
            let types: [AVCaptureDevice.DeviceType] = position == .front
                ? [.builtInTrueDepthCamera, .builtInWideAngleCamera]
                : [.builtInLiDARDepthCamera, .builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
            let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position)

            guard let device = discovery.devices.first,
                  let newInput = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(newInput) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.status = "لم أجد كاميرا مناسبة" }
                return
            }

            self.session.addInput(newInput)
            self.input = newInput
            let supportsDepth = device.formats.contains { !$0.supportedDepthDataFormats.isEmpty }
            self.session.commitConfiguration()
            self.session.startRunning()

            DispatchQueue.main.async {
                self.depthCapable = supportsDepth
                self.isRunning = true
                self.status = supportsDepth ? "Depth camera detected" : "Camera live"
            }
        }
    }

    func switchCamera() {
        isFrontCamera.toggle()
        configureAndStart()
    }

    func capture() {
        guard isRunning else { return }
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async { self.status = "تعذر التقاط الصورة" }
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { auth in
            guard auth == .authorized || auth == .limited else {
                DispatchQueue.main.async { self.status = "لم يتم السماح بالحفظ" }
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            DispatchQueue.main.async { self.status = "تم الحفظ في الصور ✓" }
        }
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}
