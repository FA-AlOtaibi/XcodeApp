import AVKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Home

@MainActor
final class MainViewController: UIViewController, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private let library = LibraryStore()

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let importCard = UIView()
    private let importLabel = UILabel()
    private let photosButton = UIButton(type: .system)
    private let filesButton = UIButton(type: .system)
    private let loading = UIActivityIndicatorView(style: .medium)
    private let bottomBar = UIView()

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildHome()
    }

    private func buildHome() {
        titleLabel.text = "ScreenFlow"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 42, weight: .bold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8

        subtitleLabel.text = "FPS + AI Video Enhancer"
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.42)
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .medium)

        let headerText = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerText.axis = .vertical
        headerText.spacing = 2

        let headerIcon = makeCircleButton(icon: "arrow.down", action: #selector(openPhotos))
        let header = UIStackView(arrangedSubviews: [headerText, headerIcon])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 18
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        importCard.backgroundColor = UIColor(white: 0.045, alpha: 1)
        importCard.layer.cornerRadius = 22
        importCard.layer.cornerCurve = .continuous
        importCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(importCard)

        let link = UIImageView(image: UIImage(systemName: "link"))
        link.tintColor = UIColor.white.withAlphaComponent(0.55)
        link.translatesAutoresizingMaskIntoConstraints = false
        importCard.addSubview(link)

        importLabel.text = "Choose a video to enhance"
        importLabel.textColor = UIColor.white.withAlphaComponent(0.46)
        importLabel.font = .systemFont(ofSize: 17, weight: .medium)
        importLabel.translatesAutoresizingMaskIntoConstraints = false
        importCard.addSubview(importLabel)

        loading.hidesWhenStopped = true
        loading.color = .white
        loading.translatesAutoresizingMaskIntoConstraints = false
        importCard.addSubview(loading)

        configurePrimaryButton(photosButton, title: "Photos", icon: "photo.on.rectangle.angled", primary: true)
        configurePrimaryButton(filesButton, title: "Files", icon: "folder", primary: false)
        photosButton.addTarget(self, action: #selector(openPhotos), for: .touchUpInside)
        filesButton.addTarget(self, action: #selector(openFiles), for: .touchUpInside)

        let actionRow = UIStackView(arrangedSubviews: [photosButton, filesButton])
        actionRow.axis = .horizontal
        actionRow.spacing = 12
        actionRow.distribution = .fillEqually
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionRow)

        let quickRow = makeQuickRow()
        quickRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(quickRow)

        buildBottomBar()

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            headerIcon.widthAnchor.constraint(equalToConstant: 54),
            headerIcon.heightAnchor.constraint(equalToConstant: 54),

            importCard.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 34),
            importCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            importCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            importCard.heightAnchor.constraint(equalToConstant: 88),

            link.leadingAnchor.constraint(equalTo: importCard.leadingAnchor, constant: 22),
            link.centerYAnchor.constraint(equalTo: importCard.centerYAnchor),
            link.widthAnchor.constraint(equalToConstant: 24),
            link.heightAnchor.constraint(equalToConstant: 24),
            importLabel.leadingAnchor.constraint(equalTo: link.trailingAnchor, constant: 14),
            importLabel.centerYAnchor.constraint(equalTo: importCard.centerYAnchor),
            importLabel.trailingAnchor.constraint(lessThanOrEqualTo: loading.leadingAnchor, constant: -10),
            loading.trailingAnchor.constraint(equalTo: importCard.trailingAnchor, constant: -22),
            loading.centerYAnchor.constraint(equalTo: importCard.centerYAnchor),

            actionRow.topAnchor.constraint(equalTo: importCard.bottomAnchor, constant: 18),
            actionRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            actionRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            actionRow.heightAnchor.constraint(equalToConstant: 66),

            quickRow.topAnchor.constraint(equalTo: actionRow.bottomAnchor, constant: 24),
            quickRow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            quickRow.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            quickRow.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            quickRow.bottomAnchor.constraint(lessThanOrEqualTo: bottomBar.topAnchor, constant: -18)
        ])
    }

    private func makeQuickRow() -> UIStackView {
        let presets: [(String, String)] = [
            ("60", "FPS"), ("120", "FPS"), ("4K", "Ultra"), ("AI", "Enhance")
        ]
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 22
        row.distribution = .equalCentering

        for (main, sub) in presets {
            let circle = UIView()
            circle.backgroundColor = UIColor(white: 0.10, alpha: 1)
            circle.layer.cornerRadius = 31
            circle.translatesAutoresizingMaskIntoConstraints = false
            circle.widthAnchor.constraint(equalToConstant: 62).isActive = true
            circle.heightAnchor.constraint(equalToConstant: 62).isActive = true

            let mainLabel = UILabel()
            mainLabel.text = main
            mainLabel.textColor = .white
            mainLabel.font = .systemFont(ofSize: 18, weight: .bold)
            mainLabel.textAlignment = .center
            mainLabel.translatesAutoresizingMaskIntoConstraints = false
            circle.addSubview(mainLabel)
            NSLayoutConstraint.activate([
                mainLabel.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
                mainLabel.centerYAnchor.constraint(equalTo: circle.centerYAnchor)
            ])

            let subLabel = UILabel()
            subLabel.text = sub
            subLabel.textColor = UIColor.white.withAlphaComponent(0.48)
            subLabel.font = .systemFont(ofSize: 12, weight: .medium)
            subLabel.textAlignment = .center

            let item = UIStackView(arrangedSubviews: [circle, subLabel])
            item.axis = .vertical
            item.alignment = .center
            item.spacing = 8
            row.addArrangedSubview(item)
        }
        return row
    }

    private func buildBottomBar() {
        bottomBar.backgroundColor = UIColor(white: 0.045, alpha: 0.98)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        let home = bottomItem(title: "Enhance", icon: "wand.and.stars", active: true)
        let libraryButton = bottomItem(title: "Library", icon: "folder.fill", active: false)
        libraryButton.addTarget(self, action: #selector(openLibrary), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [home, libraryButton])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(row)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -82),
            row.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 8),
            row.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            row.heightAnchor.constraint(equalToConstant: 64)
        ])
    }

    private func bottomItem(title: String, icon: String, active: Bool) -> UIButton {
        let b = UIButton(type: .system)
        var cfg = UIButton.Configuration.plain()
        cfg.title = title
        cfg.image = UIImage(systemName: icon)
        cfg.imagePlacement = .top
        cfg.imagePadding = 5
        cfg.baseForegroundColor = active ? UIColor(red: 0.36, green: 0.48, blue: 0.18, alpha: 1) : UIColor.white.withAlphaComponent(0.55)
        b.configuration = cfg
        return b
    }

    private func makeCircleButton(icon: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.image = UIImage(systemName: icon)
        cfg.baseForegroundColor = UIColor(red: 0.36, green: 0.48, blue: 0.18, alpha: 1)
        cfg.baseBackgroundColor = UIColor(red: 0.03, green: 0.05, blue: 0.02, alpha: 1)
        cfg.cornerStyle = .capsule
        b.configuration = cfg
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func configurePrimaryButton(_ button: UIButton, title: String, icon: String, primary: Bool) {
        var cfg = UIButton.Configuration.filled()
        cfg.title = title
        cfg.image = UIImage(systemName: icon)
        cfg.imagePadding = 10
        cfg.baseBackgroundColor = primary ? UIColor(red: 0.31, green: 0.40, blue: 0.17, alpha: 1) : UIColor(white: 0.12, alpha: 1)
        cfg.baseForegroundColor = primary ? .white : UIColor.white.withAlphaComponent(0.75)
        cfg.cornerStyle = .large
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 18, weight: .bold)
            return out
        }
        button.configuration = cfg
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
        setImporting(true)

        let type = provider.registeredTypeIdentifiers.first(where: {
            guard let t = UTType($0) else { return false }
            return t.conforms(to: .movie) || t.conforms(to: .video)
        }) ?? UTType.movie.identifier

        provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, fileError in
            guard let self else { return }
            if let url, let copy = try? Self.copyImportedFile(url, preferredExtension: url.pathExtension) {
                Task { @MainActor in self.finishImport(copy) }
                return
            }
            provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, dataError in
                guard let self else { return }
                guard let data, !data.isEmpty else {
                    Task { @MainActor in
                        self.setImporting(false)
                        self.showError(dataError?.localizedDescription ?? fileError?.localizedDescription ?? "Could not import this video.")
                    }
                    return
                }
                let ext = UTType(type)?.preferredFilenameExtension ?? "mov"
                let dst = FileManager.default.temporaryDirectory.appendingPathComponent("screenflow_\(UUID().uuidString).\(ext)")
                do {
                    try data.write(to: dst, options: .atomic)
                    Task { @MainActor in self.finishImport(dst) }
                } catch {
                    Task { @MainActor in self.setImporting(false); self.showError(error.localizedDescription) }
                }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        setImporting(true)
        do {
            let copy = try Self.copyImportedFile(url, preferredExtension: url.pathExtension)
            finishImport(copy)
        } catch {
            setImporting(false)
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

    private func finishImport(_ url: URL) {
        setImporting(false)
        let editor = EditorViewController(videoURL: url, library: library)
        editor.modalPresentationStyle = .fullScreen
        present(editor, animated: true)
    }

    private func setImporting(_ importing: Bool) {
        photosButton.isEnabled = !importing
        filesButton.isEnabled = !importing
        if importing {
            loading.startAnimating()
            importLabel.text = "Importing video…"
        } else {
            loading.stopAnimating()
            importLabel.text = "Choose a video to enhance"
        }
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

// MARK: - Editor

@MainActor
final class EditorViewController: UIViewController {
    private let videoURL: URL
    private let library: LibraryStore
    private let model = VideoModel()

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let preview = UIView()
    private let playerVC = AVPlayerViewController()
    private let fps = UISegmentedControl(items: ["24", "30", "60", "120"])
    private let quality = UISegmentedControl(items: ["Native", "2K", "4K"])
    private let motion = UISegmentedControl(items: ["Fast", "Smooth"])
    private let aiSwitch = UISwitch()
    private let action = UIButton(type: .system)
    private let overlay = UIView()
    private let percent = UILabel()
    private let stage = UILabel()
    private let progress = UIProgressView(progressViewStyle: .bar)
    private var timer: Timer?

    init(videoURL: URL, library: LibraryStore) {
        self.videoURL = videoURL
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildEditor()
        Task { await loadVideo() }
    }

    private func buildEditor() {
        let close = UIButton(type: .system)
        var closeCfg = UIButton.Configuration.filled()
        closeCfg.image = UIImage(systemName: "xmark")
        closeCfg.baseForegroundColor = .white
        closeCfg.baseBackgroundColor = UIColor(white: 0.10, alpha: 1)
        closeCfg.cornerStyle = .capsule
        close.configuration = closeCfg
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeEditor), for: .touchUpInside)
        view.addSubview(close)

        let title = UILabel()
        title.text = "Enhance Video"
        title.textColor = .white
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll)

        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        preview.backgroundColor = UIColor(white: 0.055, alpha: 1)
        preview.layer.cornerRadius = 22
        preview.layer.cornerCurve = .continuous
        preview.clipsToBounds = true
        preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 0.60).isActive = true
        stack.addArrangedSubview(preview)

        stack.addArrangedSubview(makeOptionCard(title: "Frame Rate", subtitle: "Smooth output motion", control: fps))
        stack.addArrangedSubview(makeOptionCard(title: "Resolution", subtitle: "Native, 2K or 4K", control: quality))
        stack.addArrangedSubview(makeAI())
        stack.addArrangedSubview(makeOptionCard(title: "Motion", subtitle: "Frame interpolation", control: motion))

        [fps, quality, motion].forEach(configureSegment)
        fps.selectedSegmentIndex = 2
        quality.selectedSegmentIndex = 2
        motion.selectedSegmentIndex = 1
        aiSwitch.isOn = true

        model.targetFPS = 60
        model.quality = .fourK
        model.mode = .smooth
        model.upscaleEngine = .ai

        fps.addTarget(self, action: #selector(settingsChanged), for: .valueChanged)
        quality.addTarget(self, action: #selector(settingsChanged), for: .valueChanged)
        motion.addTarget(self, action: #selector(settingsChanged), for: .valueChanged)
        aiSwitch.addTarget(self, action: #selector(settingsChanged), for: .valueChanged)

        var cfg = UIButton.Configuration.filled()
        cfg.title = "Enhance · 60 FPS · 4K"
        cfg.image = UIImage(systemName: "wand.and.stars")
        cfg.imagePadding = 10
        cfg.baseBackgroundColor = UIColor(red: 0.31, green: 0.40, blue: 0.17, alpha: 1)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .large
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 18, weight: .bold)
            return out
        }
        action.configuration = cfg
        action.translatesAutoresizingMaskIntoConstraints = false
        action.addTarget(self, action: #selector(convert), for: .touchUpInside)
        view.addSubview(action)

        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            close.widthAnchor.constraint(equalToConstant: 46),
            close.heightAnchor.constraint(equalToConstant: 46),
            title.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: close.trailingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),

            action.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            action.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            action.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            action.heightAnchor.constraint(equalToConstant: 60),

            scroll.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: action.topAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16)
        ])

        buildOverlay()
    }

    private func makeOptionCard(title: String, subtitle: String, control: UISegmentedControl) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.055, alpha: 1)
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous

        let t = UILabel(); t.text = title; t.textColor = .white; t.font = .systemFont(ofSize: 18, weight: .bold)
        let s = UILabel(); s.text = subtitle; s.textColor = UIColor.white.withAlphaComponent(0.4); s.font = .systemFont(ofSize: 12, weight: .medium)
        let labels = UIStackView(arrangedSubviews: [t, s]); labels.axis = .vertical; labels.spacing = 1; labels.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(labels); card.addSubview(control)
        NSLayoutConstraint.activate([
            labels.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            labels.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            labels.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            control.topAnchor.constraint(equalTo: labels.bottomAnchor, constant: 10),
            control.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            control.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            control.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            control.heightAnchor.constraint(equalToConstant: 42)
        ])
        return card
    }

    private func makeAI() -> UIView {
        let card = UIView(); card.backgroundColor = UIColor(white: 0.055, alpha: 1); card.layer.cornerRadius = 18; card.layer.cornerCurve = .continuous
        let title = UILabel(); title.text = "AI Super Resolution"; title.textColor = .white; title.font = .systemFont(ofSize: 18, weight: .bold)
        let sub = UILabel(); sub.text = "Real-ESRGAN x2"; sub.textColor = UIColor.white.withAlphaComponent(0.4); sub.font = .systemFont(ofSize: 12, weight: .medium)
        let labels = UIStackView(arrangedSubviews: [title, sub]); labels.axis = .vertical; labels.spacing = 2; labels.translatesAutoresizingMaskIntoConstraints = false
        aiSwitch.onTintColor = UIColor(red: 0.31, green: 0.40, blue: 0.17, alpha: 1); aiSwitch.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(labels); card.addSubview(aiSwitch)
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            labels.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            labels.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: aiSwitch.leadingAnchor, constant: -12),
            aiSwitch.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            aiSwitch.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
        return card
    }

    private func configureSegment(_ c: UISegmentedControl) {
        c.selectedSegmentTintColor = .white
        c.backgroundColor = UIColor.white.withAlphaComponent(0.055)
        c.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 14, weight: .bold)], for: .selected)
        c.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.6), .font: UIFont.systemFont(ofSize: 14, weight: .semibold)], for: .normal)
    }

    private func loadVideo() async {
        await model.setInput(url: videoURL)
        guard model.input != nil else {
            showError(model.errorText ?? "Could not read this video.")
            return
        }
        let player = AVPlayer(url: videoURL)
        playerVC.player = player
        addChild(playerVC)
        let playerView = playerVC.view!
        playerView.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: preview.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: preview.bottomAnchor)
        ])
        playerVC.didMove(toParent: self)
    }

    @objc private func settingsChanged() {
        model.targetFPS = [24, 30, 60, 120][fps.selectedSegmentIndex]
        model.quality = [.enhanced, .twoK, .fourK][quality.selectedSegmentIndex]
        model.mode = motion.selectedSegmentIndex == 1 ? .smooth : .simple
        model.upscaleEngine = aiSwitch.isOn ? .ai : .standard
        let q = ["Native", "2K", "4K"][quality.selectedSegmentIndex]
        action.configuration?.title = "Enhance · \(model.targetFPS) FPS · \(q)"
    }

    @objc private func closeEditor() { dismiss(animated: true) }

    @objc private func convert() {
        guard model.input != nil else { return }
        overlay.isHidden = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            let p = max(0, min(1, self.model.progress))
            self.percent.text = "\(Int(p * 100))%"
            self.progress.progress = Float(p)
            self.stage.text = self.model.stageText
        }
        Task {
            await model.convert(library: library)
            timer?.invalidate(); timer = nil; overlay.isHidden = true
            if let error = model.errorText { showError(error) }
            else { SFNativeBridge.impactSuccess(); showDone() }
        }
    }

    private func buildOverlay() {
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.96)
        overlay.isHidden = true
        view.addSubview(overlay)
        percent.textColor = .white; percent.font = .systemFont(ofSize: 56, weight: .bold); percent.textAlignment = .center; percent.translatesAutoresizingMaskIntoConstraints = false
        stage.textColor = UIColor.white.withAlphaComponent(0.6); stage.font = .systemFont(ofSize: 16, weight: .semibold); stage.textAlignment = .center; stage.numberOfLines = 2; stage.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = .white; progress.trackTintColor = UIColor.white.withAlphaComponent(0.12); progress.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(percent); overlay.addSubview(stage); overlay.addSubview(progress)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor), overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor), overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor), overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            percent.centerXAnchor.constraint(equalTo: overlay.centerXAnchor), percent.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -30),
            stage.topAnchor.constraint(equalTo: percent.bottomAnchor, constant: 12), stage.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 28), stage.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -28),
            progress.topAnchor.constraint(equalTo: stage.bottomAnchor, constant: 24), progress.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 44), progress.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -44)
        ])
    }

    private func showDone() {
        let alert = UIAlertController(title: "Saved", message: "Your enhanced video is now in ScreenFlow Library.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Done", style: .default))
        present(alert, animated: true)
    }

    private func showError(_ text: String) {
        let alert = UIAlertController(title: "ScreenFlow", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Library

@MainActor
final class LibraryViewController: UITableViewController {
    private let store: LibraryStore
    init(store: LibraryStore) { self.store = store; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Library"
        view.backgroundColor = .black
        tableView.backgroundColor = .black
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationController?.navigationBar.tintColor = .white
        navigationController?.navigationBar.barStyle = .black
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
    }
    @objc private func done() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { store.items.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let item = store.items[indexPath.row]
        cell.backgroundColor = UIColor(white: 0.055, alpha: 1)
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = UIColor.white.withAlphaComponent(0.48)
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = "\(item.durationText) · \(item.sizeText)"
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let player = AVPlayerViewController(); player.player = AVPlayer(url: store.url(for: store.items[indexPath.row])); present(player, animated: true) { player.player?.play() }
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let item = store.items[indexPath.row]; store.delete(item); tableView.deleteRows(at: [indexPath], with: .automatic)
    }
}
