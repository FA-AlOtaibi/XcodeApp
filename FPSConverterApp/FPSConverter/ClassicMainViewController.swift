import AVKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ClassicMainViewController: UIViewController, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private let model = VideoModel()
    private let library = LibraryStore()

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let preview = UIView()
    private let placeholder = UIStackView()
    private let playerVC = AVPlayerViewController()
    private var player: AVPlayer?

    private let fps = UISegmentedControl(items: ["24", "30", "60", "120"])
    private let resolution = UISegmentedControl(items: ["Native", "2K", "4K"])
    private let motion = UISegmentedControl(items: ["Fast", "Smooth"])
    private let aiSwitch = UISwitch()
    private let actionButton = UIButton(type: .system)

    private let overlay = UIView()
    private let percentLabel = UILabel()
    private let stageLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private var timer: Timer?

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildUI()
        applyDefaults()
    }

    private func buildUI() {
        buildBottomAction()

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -10),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -18)
        ])

        stack.addArrangedSubview(makeHeader())
        stack.addArrangedSubview(makePreview())
        stack.addArrangedSubview(makeImportRow())
        stack.addArrangedSubview(makeSection(title: "Frame Rate", subtitle: "Choose the output FPS", control: fps))
        stack.addArrangedSubview(makeSection(title: "Resolution", subtitle: "Output size without cropping", control: resolution))
        stack.addArrangedSubview(makeAISection())
        stack.addArrangedSubview(makeSection(title: "Motion Engine", subtitle: "Smooth creates in-between frames", control: motion))
        stack.addArrangedSubview(makeLibraryButton())

        [fps, resolution, motion].forEach(configureSegmented)
        fps.addTarget(self, action: #selector(fpsChanged), for: .valueChanged)
        resolution.addTarget(self, action: #selector(resolutionChanged), for: .valueChanged)
        motion.addTarget(self, action: #selector(motionChanged), for: .valueChanged)
        aiSwitch.addTarget(self, action: #selector(aiChanged), for: .valueChanged)

        buildOverlay()
    }

    private func makeHeader() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12

        let text = UIStackView()
        text.axis = .vertical
        text.spacing = 2

        let title = UILabel()
        title.text = "ScreenFlow"
        title.textColor = .white
        title.font = .systemFont(ofSize: 30, weight: .bold)

        let subtitle = UILabel()
        subtitle.text = "FPS + AI Video Enhancer"
        subtitle.textColor = UIColor.white.withAlphaComponent(0.42)
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)

        text.addArrangedSubview(title)
        text.addArrangedSubview(subtitle)

        let libraryButton = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.image = UIImage(systemName: "square.stack.3d.up.fill")
        cfg.baseBackgroundColor = UIColor.white.withAlphaComponent(0.08)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        libraryButton.configuration = cfg
        libraryButton.widthAnchor.constraint(equalToConstant: 46).isActive = true
        libraryButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        libraryButton.addTarget(self, action: #selector(openLibrary), for: .touchUpInside)

        row.addArrangedSubview(text)
        row.addArrangedSubview(libraryButton)
        return row
    }

    private func makePreview() -> UIView {
        preview.backgroundColor = UIColor(white: 0.055, alpha: 1)
        preview.layer.cornerRadius = 22
        preview.layer.cornerCurve = .continuous
        preview.clipsToBounds = true
        preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 0.56).isActive = true

        addChild(playerVC)
        let pv = playerVC.view!
        pv.translatesAutoresizingMaskIntoConstraints = false
        pv.isHidden = true
        preview.addSubview(pv)
        NSLayoutConstraint.activate([
            pv.topAnchor.constraint(equalTo: preview.topAnchor),
            pv.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            pv.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            pv.bottomAnchor.constraint(equalTo: preview.bottomAnchor)
        ])
        playerVC.didMove(toParent: self)

        placeholder.axis = .vertical
        placeholder.alignment = .center
        placeholder.spacing = 7
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
            placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: preview.leadingAnchor, constant: 20),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: preview.trailingAnchor, constant: -20)
        ])

        let icon = UIImageView(image: UIImage(systemName: "video.badge.plus"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let title = UILabel()
        title.text = "Choose a video"
        title.textColor = .white
        title.font = .systemFont(ofSize: 21, weight: .bold)

        let sub = UILabel()
        sub.text = "Photos or Files"
        sub.textColor = UIColor.white.withAlphaComponent(0.42)
        sub.font = .systemFont(ofSize: 13, weight: .medium)

        placeholder.addArrangedSubview(icon)
        placeholder.addArrangedSubview(title)
        placeholder.addArrangedSubview(sub)
        preview.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openPhotos)))
        return preview
    }

    private func makeImportRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually

        let photos = compactButton(title: "Photos", icon: "photo.on.rectangle.angled", primary: true)
        let files = compactButton(title: "Files", icon: "folder", primary: false)
        photos.addTarget(self, action: #selector(openPhotos), for: .touchUpInside)
        files.addTarget(self, action: #selector(openFiles), for: .touchUpInside)
        row.addArrangedSubview(photos)
        row.addArrangedSubview(files)
        row.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return row
    }

    private func makeSection(title: String, subtitle: String, control: UISegmentedControl) -> UIView {
        let card = cardView()
        let vertical = UIStackView()
        vertical.axis = .vertical
        vertical.spacing = 9
        vertical.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(vertical)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.38)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        vertical.addArrangedSubview(titleLabel)
        vertical.addArrangedSubview(subtitleLabel)
        vertical.addArrangedSubview(control)

        NSLayoutConstraint.activate([
            vertical.topAnchor.constraint(equalTo: card.topAnchor, constant: 15),
            vertical.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            vertical.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
            vertical.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -15)
        ])
        return card
    }

    private func makeAISection() -> UIView {
        let card = cardView()
        card.heightAnchor.constraint(equalToConstant: 86).isActive = true

        let icon = UIImageView(image: UIImage(systemName: "brain.head.profile"))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "AI Super Resolution"
        title.textColor = .white
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.78
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = UILabel()
        subtitle.text = "Real-ESRGAN detail recovery"
        subtitle.textColor = UIColor.white.withAlphaComponent(0.40)
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        aiSwitch.onTintColor = .white
        aiSwitch.thumbTintColor = .black
        aiSwitch.translatesAutoresizingMaskIntoConstraints = false

        [icon, title, subtitle, aiSwitch].forEach(card.addSubview)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),

            aiSwitch.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            aiSwitch.centerYAnchor.constraint(equalTo: card.centerYAnchor),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(lessThanOrEqualTo: aiSwitch.leadingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: aiSwitch.leadingAnchor, constant: -12),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4)
        ])
        return card
    }

    private func makeLibraryButton() -> UIButton {
        let button = compactButton(title: "Open ScreenFlow Library", icon: "square.stack.3d.up.fill", primary: false)
        button.contentHorizontalAlignment = .leading
        button.heightAnchor.constraint(equalToConstant: 54).isActive = true
        button.addTarget(self, action: #selector(openLibrary), for: .touchUpInside)
        return button
    }

    private func cardView() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.055, alpha: 1)
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.06).cgColor
        return card
    }

    private func compactButton(title: String, icon: String, primary: Bool) -> UIButton {
        let button = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.title = title
        cfg.image = UIImage(systemName: icon)
        cfg.imagePadding = 8
        cfg.cornerStyle = .large
        cfg.baseBackgroundColor = primary ? .white : UIColor.white.withAlphaComponent(0.08)
        cfg.baseForegroundColor = primary ? .black : .white
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 16, weight: .bold)
            return out
        }
        button.configuration = cfg
        return button
    }

    private func configureSegmented(_ control: UISegmentedControl) {
        control.selectedSegmentTintColor = .white
        control.backgroundColor = UIColor.white.withAlphaComponent(0.055)
        control.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 14, weight: .bold)], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.58), .font: UIFont.systemFont(ofSize: 14, weight: .semibold)], for: .normal)
        control.heightAnchor.constraint(equalToConstant: 42).isActive = true
    }

    private func buildBottomAction() {
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        var cfg = UIButton.Configuration.filled()
        cfg.title = "Choose a Video"
        cfg.image = UIImage(systemName: "wand.and.stars")
        cfg.imagePadding = 10
        cfg.baseBackgroundColor = .white
        cfg.baseForegroundColor = .black
        cfg.cornerStyle = .large
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 18, weight: .bold)
            return out
        }
        actionButton.configuration = cfg
        actionButton.addTarget(self, action: #selector(convertTapped), for: .touchUpInside)
        view.addSubview(actionButton)

        NSLayoutConstraint.activate([
            actionButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            actionButton.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    private func buildOverlay() {
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.94)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.alpha = 0
        overlay.isHidden = true
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        percentLabel.textColor = .white
        percentLabel.font = .systemFont(ofSize: 54, weight: .bold)
        percentLabel.textAlignment = .center
        percentLabel.translatesAutoresizingMaskIntoConstraints = false

        stageLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        stageLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        stageLabel.textAlignment = .center
        stageLabel.numberOfLines = 2
        stageLabel.translatesAutoresizingMaskIntoConstraints = false

        progressView.progressTintColor = .white
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.13)
        progressView.translatesAutoresizingMaskIntoConstraints = false

        [percentLabel, stageLabel, progressView].forEach(overlay.addSubview)
        NSLayoutConstraint.activate([
            percentLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            percentLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -34),
            stageLabel.topAnchor.constraint(equalTo: percentLabel.bottomAnchor, constant: 12),
            stageLabel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 30),
            stageLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -30),
            progressView.topAnchor.constraint(equalTo: stageLabel.bottomAnchor, constant: 26),
            progressView.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 46),
            progressView.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -46)
        ])
    }

    private func applyDefaults() {
        fps.selectedSegmentIndex = 2
        resolution.selectedSegmentIndex = 2
        motion.selectedSegmentIndex = 1
        aiSwitch.isOn = true
        model.targetFPS = 60
        model.quality = .fourK
        model.mode = .smooth
        model.upscaleEngine = .ai
        updateActionTitle()
    }

    @objc private func fpsChanged() {
        model.targetFPS = [24, 30, 60, 120][fps.selectedSegmentIndex]
        updateActionTitle()
    }

    @objc private func resolutionChanged() {
        model.quality = [.enhanced, .twoK, .fourK][resolution.selectedSegmentIndex]
        updateActionTitle()
    }

    @objc private func motionChanged() {
        model.mode = motion.selectedSegmentIndex == 1 ? .smooth : .simple
    }

    @objc private func aiChanged() {
        model.upscaleEngine = aiSwitch.isOn ? .ai : .standard
    }

    private func updateActionTitle() {
        let q = resolution.selectedSegmentIndex == 0 ? "Native" : (resolution.selectedSegmentIndex == 1 ? "2K" : "4K")
        actionButton.configuration?.title = model.input == nil ? "Choose a Video" : "Enhance · \(model.targetFPS) FPS · \(q)"
    }

    @objc private func openPhotos() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func openFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .video], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        let type = provider.registeredTypeIdentifiers.first(where: {
            guard let t = UTType($0) else { return false }
            return t.conforms(to: .movie) || t.conforms(to: .video)
        }) ?? UTType.movie.identifier

        provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, firstError in
            guard let self else { return }
            if let url, let copied = try? Self.copyImportedFile(url, preferredExtension: url.pathExtension) {
                Task { @MainActor in await self.loadVideo(copied) }
                return
            }
            provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, secondError in
                guard let self else { return }
                guard let data, !data.isEmpty else {
                    Task { @MainActor in self.showError(secondError?.localizedDescription ?? firstError?.localizedDescription ?? "Could not import this video.") }
                    return
                }
                let ext = UTType(type)?.preferredFilenameExtension ?? "mov"
                let dst = FileManager.default.temporaryDirectory.appendingPathComponent("screenflow_\(UUID().uuidString).\(ext)")
                do {
                    try data.write(to: dst, options: .atomic)
                    Task { @MainActor in await self.loadVideo(dst) }
                } catch {
                    Task { @MainActor in self.showError(error.localizedDescription) }
                }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            let copied = try Self.copyImportedFile(url, preferredExtension: url.pathExtension)
            Task { await loadVideo(copied) }
        } catch {
            showError(error.localizedDescription)
        }
    }

    nonisolated private static func copyImportedFile(_ source: URL, preferredExtension: String) throws -> URL {
        let ext = preferredExtension.isEmpty ? "mov" : preferredExtension
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("screenflow_\(UUID().uuidString).\(ext)")
        try? FileManager.default.removeItem(at: dst)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: dst)
        return dst
    }

    private func loadVideo(_ url: URL) async {
        await model.setInput(url: url)
        guard let info = model.input else {
            showError(model.errorText ?? "Could not read this video.")
            return
        }
        placeholder.isHidden = true
        let pv = playerVC.view!
        pv.isHidden = false
        player = AVPlayer(url: info.url)
        playerVC.player = player
        updateActionTitle()
        SFNativeBridge.impactSuccess()
    }

    @objc private func convertTapped() {
        guard model.input != nil else {
            openPhotos()
            return
        }
        showProgress()
        Task {
            await model.convert(library: library)
            hideProgress()
            if let error = model.errorText {
                showError(error)
            } else if let output = model.output {
                SFNativeBridge.impactSuccess()
                showCompletion(output)
            }
        }
    }

    private func showProgress() {
        overlay.isHidden = false
        UIView.animate(withDuration: 0.2) { self.overlay.alpha = 1 }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let value = Float(max(0, min(1, self.model.progress)))
            self.progressView.setProgress(value, animated: true)
            self.percentLabel.text = "\(Int(value * 100))%"
            self.stageLabel.text = self.model.stageText.isEmpty ? "Processing on-device" : self.model.stageText
        }
    }

    private func hideProgress() {
        timer?.invalidate()
        timer = nil
        UIView.animate(withDuration: 0.2, animations: { self.overlay.alpha = 0 }) { _ in
            self.overlay.isHidden = true
        }
    }

    private func showCompletion(_ info: VideoModel.Info) {
        let alert = UIAlertController(title: "Saved to Library", message: "\(info.resolutionText) · \(info.fpsText) · \(info.sizeText)", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Save to Photos", style: .default) { _ in self.model.saveToPhotos() })
        alert.addAction(UIAlertAction(title: "Open Library", style: .default) { _ in self.openLibrary() })
        alert.addAction(UIAlertAction(title: "Done", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = actionButton
            pop.sourceRect = actionButton.bounds
        }
        present(alert, animated: true)
    }

    @objc private func openLibrary() {
        let vc = LibraryViewController(store: library)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func showError(_ text: String) {
        let alert = UIAlertController(title: "ScreenFlow", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
