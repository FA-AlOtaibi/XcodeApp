import SwiftUI
import ARKit
import SceneKit
import Vision
import Photos

@MainActor
final class RelightState: ObservableObject {
    @Published var status = "جاري تشغيل TrueDepth…"
    @Published var faceTracked = false
    @Published var handDetected = false
    @Published var handBlocking = false
    @Published var fps: Double = 0
    @Published var captureToken = 0
}

struct RealisticRelightView: UIViewRepresentable {
    @ObservedObject var state: RelightState
    var lightPosition: CGPoint
    var intensity: Double
    var warmth: Double
    var shadowSoftness: Double
    var ambient: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.scene = SCNScene()
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling4X
        view.automaticallyUpdatesLighting = false
        view.autoenablesDefaultLighting = false
        view.backgroundColor = .black
        context.coordinator.attach(to: view)
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.update(
            lightPosition: lightPosition,
            intensity: intensity,
            warmth: warmth,
            shadowSoftness: shadowSoftness,
            ambient: ambient
        )
        context.coordinator.captureIfNeeded(token: state.captureToken)
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        private weak var sceneView: ARSCNView?
        private let state: RelightState

        private let pointLightNode = SCNNode()
        private let ambientLightNode = SCNNode()
        private let shadowOverlay = UIView()
        private let shadowShape = CAShapeLayer()
        private let shadowGlow = CAShapeLayer()
        private let faceMask = CAShapeLayer()

        private let visionQueue = DispatchQueue(label: "DepthLight.Vision.Hand", qos: .userInitiated)
        private var visionBusy = false
        private var lastVisionTime: CFTimeInterval = 0
        private let visionInterval: CFTimeInterval = 1.0 / 12.0

        private var lightPosition = CGPoint(x: 0.72, y: 0.42)
        private var baseIntensity = 0.85
        private var warmth = 0.50
        private var shadowSoftness = 0.55
        private var ambient = 0.22
        private var handBlocking = false
        private var lastCaptureToken = -1
        private var lastFrameTime = CACurrentMediaTime()

        init(state: RelightState) {
            self.state = state
            super.init()
        }

        func attach(to view: ARSCNView) {
            sceneView = view

            let point = SCNLight()
            point.type = .omni
            point.intensity = 1800
            point.temperature = 5200
            point.attenuationStartDistance = 0.05
            point.attenuationEndDistance = 1.25
            point.attenuationFalloffExponent = 2.0
            point.castsShadow = true
            point.shadowMode = .forward
            point.shadowMapSize = CGSize(width: 1024, height: 1024)
            point.shadowSampleCount = 16
            point.shadowBias = 0.008
            point.shadowRadius = 12
            pointLightNode.light = point
            view.scene.rootNode.addChildNode(pointLightNode)

            let ambientLight = SCNLight()
            ambientLight.type = .ambient
            ambientLight.intensity = 120
            ambientLight.color = UIColor(white: 0.72, alpha: 1)
            ambientLightNode.light = ambientLight
            view.scene.rootNode.addChildNode(ambientLightNode)

            shadowOverlay.isUserInteractionEnabled = false
            shadowOverlay.backgroundColor = .clear
            shadowOverlay.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(shadowOverlay)
            NSLayoutConstraint.activate([
                shadowOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                shadowOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                shadowOverlay.topAnchor.constraint(equalTo: view.topAnchor),
                shadowOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

            shadowShape.fillColor = UIColor.black.withAlphaComponent(0.25).cgColor
            shadowShape.strokeColor = UIColor.black.withAlphaComponent(0.30).cgColor
            shadowShape.lineCap = .round
            shadowShape.lineJoin = .round
            shadowShape.lineWidth = 22
            shadowShape.opacity = 0

            shadowGlow.fillColor = UIColor.clear.cgColor
            shadowGlow.strokeColor = UIColor.black.withAlphaComponent(0.22).cgColor
            shadowGlow.lineCap = .round
            shadowGlow.lineJoin = .round
            shadowGlow.lineWidth = 38
            shadowGlow.opacity = 0

            shadowOverlay.layer.addSublayer(shadowGlow)
            shadowOverlay.layer.addSublayer(shadowShape)
            shadowOverlay.layer.mask = faceMask
        }

        func start() {
            guard ARFaceTrackingConfiguration.isSupported else {
                Task { @MainActor in
                    state.status = "هذا الوضع يحتاج كاميرا TrueDepth أمامية"
                    state.faceTracked = false
                }
                return
            }

            let config = ARFaceTrackingConfiguration()
            config.isLightEstimationEnabled = true
            if #available(iOS 13.0, *) {
                config.maximumNumberOfTrackedFaces = 1
            }
            sceneView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            Task { @MainActor in state.status = "ابحث عن وجهك أمام الكاميرا" }
        }

        func update(lightPosition: CGPoint,
                    intensity: Double,
                    warmth: Double,
                    shadowSoftness: Double,
                    ambient: Double) {
            self.lightPosition = lightPosition
            self.baseIntensity = intensity
            self.warmth = warmth
            self.shadowSoftness = shadowSoftness
            self.ambient = ambient
            applyLightSettings()
        }

        private func applyLightSettings() {
            guard let light = pointLightNode.light else { return }
            let blockedFactor = handBlocking ? 0.07 : 1.0
            light.intensity = CGFloat((350 + baseIntensity * 2850) * blockedFactor)
            light.temperature = CGFloat(2800 + warmth * 5700)
            light.shadowRadius = CGFloat(2 + shadowSoftness * 26)
            light.shadowSampleCount = shadowSoftness > 0.55 ? 32 : 16
            ambientLightNode.light?.intensity = CGFloat(25 + ambient * 520)
        }

        func captureIfNeeded(token: Int) {
            guard token != lastCaptureToken, token > 0, let sceneView else { return }
            lastCaptureToken = token
            let image = sceneView.snapshot()
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { auth in
                guard auth == .authorized || auth == .limited else {
                    Task { @MainActor in self.state.status = "لم يتم السماح بحفظ الصورة" }
                    return
                }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                Task { @MainActor in self.state.status = "تم حفظ الصورة ✓" }
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard anchor is ARFaceAnchor,
                  let device = sceneView?.device,
                  let shadowGeometry = ARSCNFaceGeometry(device: device, fillMesh: true),
                  let highlightGeometry = ARSCNFaceGeometry(device: device, fillMesh: true) else { return nil }

            let root = SCNNode()

            let shadowNode = SCNNode(geometry: shadowGeometry)
            shadowNode.name = "shadowFace"
            shadowNode.castsShadow = true
            let shadowMaterial = SCNMaterial()
            shadowMaterial.lightingModel = .lambert
            shadowMaterial.diffuse.contents = UIColor.white
            shadowMaterial.ambient.contents = UIColor(white: 0.12, alpha: 1)
            shadowMaterial.blendMode = .multiply
            shadowMaterial.transparency = 0.72
            shadowMaterial.isDoubleSided = true
            shadowMaterial.readsFromDepthBuffer = true
            shadowMaterial.writesToDepthBuffer = false
            shadowGeometry.firstMaterial = shadowMaterial

            let highlightNode = SCNNode(geometry: highlightGeometry)
            highlightNode.name = "highlightFace"
            let highlightMaterial = SCNMaterial()
            highlightMaterial.lightingModel = .physicallyBased
            highlightMaterial.diffuse.contents = UIColor(white: 0.72, alpha: 1)
            highlightMaterial.metalness.contents = 0.0
            highlightMaterial.roughness.contents = 0.62
            highlightMaterial.blendMode = .add
            highlightMaterial.transparency = 0.16
            highlightMaterial.isDoubleSided = true
            highlightMaterial.readsFromDepthBuffer = true
            highlightMaterial.writesToDepthBuffer = false
            highlightGeometry.firstMaterial = highlightMaterial

            root.addChildNode(shadowNode)
            root.addChildNode(highlightNode)
            return root
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let face = anchor as? ARFaceAnchor else { return }
            if let geometry = node.childNode(withName: "shadowFace", recursively: false)?.geometry as? ARSCNFaceGeometry {
                geometry.update(from: face.geometry)
            }
            if let geometry = node.childNode(withName: "highlightFace", recursively: false)?.geometry as? ARSCNFaceGeometry {
                geometry.update(from: face.geometry)
            }
            updateFaceMask(faceNode: node)
            Task { @MainActor in
                self.state.faceTracked = face.isTracked
                if !self.handBlocking {
                    self.state.status = face.isTracked ? "Face mesh + واقعية الإضاءة تعمل" : "حرك وجهك داخل الإطار"
                }
            }
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            updateLightWorldPosition(frame: frame)
            runHandVisionIfNeeded(frame: frame)

            let now = CACurrentMediaTime()
            let fps = 1.0 / max(now - lastFrameTime, 0.001)
            lastFrameTime = now
            Task { @MainActor in
                self.state.fps = self.state.fps == 0 ? fps : (self.state.fps * 0.88 + fps * 0.12)
            }
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            Task { @MainActor in
                switch camera.trackingState {
                case .normal:
                    break
                case .limited(let reason):
                    self.state.status = "تتبع محدود: \(reason)"
                case .notAvailable:
                    self.state.status = "تتبع TrueDepth غير متاح"
                }
            }
        }

        private func updateLightWorldPosition(frame: ARFrame) {
            let x = Float((0.5 - lightPosition.x) * 0.62)
            let y = Float((0.5 - lightPosition.y) * 0.95)
            let local = SIMD4<Float>(x, y, -0.34, 1)
            let world = simd_mul(frame.camera.transform, local)
            pointLightNode.simdPosition = SIMD3<Float>(world.x, world.y, world.z)
        }

        private func updateFaceMask(faceNode: SCNNode) {
            guard let view = sceneView else { return }
            let localCorners = [
                SCNVector3(-0.092, 0.115, 0.015), SCNVector3(0.092, 0.115, 0.015),
                SCNVector3(-0.092, -0.115, 0.015), SCNVector3(0.092, -0.115, 0.015)
            ]
            let projected = localCorners.map { p -> CGPoint in
                let world = faceNode.convertPosition(p, to: nil)
                let q = view.projectPoint(world)
                return CGPoint(x: CGFloat(q.x), y: CGFloat(q.y))
            }
            guard let minX = projected.map(\.x).min(), let maxX = projected.map(\.x).max(),
                  let minY = projected.map(\.y).min(), let maxY = projected.map(\.y).max() else { return }
            let rect = CGRect(x: minX - 8, y: minY - 12, width: maxX - minX + 16, height: maxY - minY + 24)
            DispatchQueue.main.async {
                self.faceMask.frame = self.shadowOverlay.bounds
                self.faceMask.path = UIBezierPath(ovalIn: rect).cgPath
            }
        }

        private func runHandVisionIfNeeded(frame: ARFrame) {
            let now = CACurrentMediaTime()
            guard now - lastVisionTime >= visionInterval, !visionBusy else { return }
            lastVisionTime = now
            visionBusy = true
            let pixelBuffer = frame.capturedImage
            let viewSize = sceneView?.bounds.size ?? .zero
            let currentLight = lightPosition

            visionQueue.async { [weak self] in
                guard let self else { return }
                defer { self.visionBusy = false }

                let request = VNDetectHumanHandPoseRequest()
                request.maximumHandCount = 1
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
                do {
                    try handler.perform([request])
                    guard let observation = request.results?.first else {
                        self.setNoHand()
                        return
                    }
                    let recognized = try observation.recognizedPoints(.all)
                    var points: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
                    for (joint, p) in recognized where p.confidence > 0.22 {
                        points[joint] = CGPoint(
                            x: p.location.x * viewSize.width,
                            y: (1 - p.location.y) * viewSize.height
                        )
                    }
                    guard points.count >= 6 else {
                        self.setNoHand()
                        return
                    }
                    self.drawHandShadow(points: points, viewSize: viewSize, light: currentLight)
                } catch {
                    self.setNoHand()
                }
            }
        }

        private func setNoHand() {
            handBlocking = false
            applyLightSettings()
            DispatchQueue.main.async {
                self.shadowShape.opacity = 0
                self.shadowGlow.opacity = 0
                Task { @MainActor in
                    self.state.handDetected = false
                    self.state.handBlocking = false
                }
            }
        }

        private func drawHandShadow(points: [VNHumanHandPoseObservation.JointName: CGPoint],
                                    viewSize: CGSize,
                                    light: CGPoint) {
            let all = Array(points.values)
            guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
                  let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else {
                setNoHand(); return
            }

            let handRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -18, dy: -18)
            let lightPoint = CGPoint(x: light.x * viewSize.width, y: light.y * viewSize.height)
            let blocks = handRect.contains(lightPoint)
            handBlocking = blocks
            applyLightSettings()

            let handCenter = CGPoint(x: handRect.midX, y: handRect.midY)
            let dx = (handCenter.x - lightPoint.x) * 0.18
            let dy = (handCenter.y - lightPoint.y) * 0.18

            let path = UIBezierPath()
            let fingerChains: [[VNHumanHandPoseObservation.JointName]] = [
                [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
                [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
                [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
                [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
                [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]
            ]
            for chain in fingerChains {
                var started = false
                for joint in chain {
                    guard var p = points[joint] else { continue }
                    p.x += dx; p.y += dy
                    if started { path.addLine(to: p) } else { path.move(to: p); started = true }
                }
            }

            let palmNames: [VNHumanHandPoseObservation.JointName] = [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
            let palm = palmNames.compactMap { points[$0] }.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            if let first = palm.first {
                let palmPath = UIBezierPath()
                palmPath.move(to: first)
                palm.dropFirst().forEach { palmPath.addLine(to: $0) }
                palmPath.close()
                path.append(palmPath)
            }

            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.shadowShape.frame = self.shadowOverlay.bounds
                self.shadowGlow.frame = self.shadowOverlay.bounds
                self.shadowShape.path = path.cgPath
                self.shadowGlow.path = path.cgPath
                self.shadowShape.lineWidth = CGFloat(18 + self.shadowSoftness * 18)
                self.shadowGlow.lineWidth = CGFloat(32 + self.shadowSoftness * 38)
                self.shadowShape.opacity = blocks ? 0.46 : 0.24
                self.shadowGlow.opacity = blocks ? 0.30 : 0.13
                CATransaction.commit()

                Task { @MainActor in
                    self.state.handDetected = true
                    self.state.handBlocking = blocks
                    self.state.status = blocks ? "يدك تحجب مصدر الضوء — shadow active" : "يد متتبعة — حرّكها فوق الضوء لحجبه"
                }
            }
        }
    }
}
