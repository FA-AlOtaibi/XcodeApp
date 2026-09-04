import AVKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class MainViewController: UIViewController, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private let model = VideoModel()
    private let library = LibraryStore()

    private let topBar = UIView()
    private let preview = UIView()
    private let previewPlaceholder = UIView()
    private let previewTitle = UILabel()
    private let previewMeta = UILabel()
    private let playerVC = AVPlayerViewController()
    private var player: AVPlayer?

    private let controlsScroll = UIScrollView()
    private let controlsStack = UIStackView()
    private let fps = UISegmentedControl(items: ["24", "30", "60", "120"])
    private let resolution = UISegmentedControl(items: ["Native", "2K", "4K"])
    private let motion = UISegmentedControl(items: ["Fast", "Smooth"])
    private let aiSwitch = UISwitch()
    private let actionButton = UIButton(type: .system)

    private let progressView = UIView()
    private let progressBar = UIProgressView(progressViewStyle: .bar)
    private let progressPercent = UILabel()
    private let progressStage = UILabel()
    private var progressTimer: Timer?

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildUI()
        applyDefaults()
    }

    private func buildUI() {
        buildTopBar()
        buildPreview()
        buildControls()
        buildActionButton()
        buildProgressOverlay()
    }

    private func buildTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        let mark = UIImageView(image: UIImage(systemName: "waveform.path"))
        mark.tintColor = .white
        mark.contentMode = .scaleAspectFit
        mark.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "ScreenFlow"
        title.textColor = .white
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let libraryButton = UIButton(type: .system)
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: "square.stack.3d.up.fill")
        c.baseForegroundColor = .white
        c.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        libraryButton.configuration = c
        libraryButton.addTarget(self, action: #selector(openLibrary), for: .touchUpInside)
        libraryButton.translatesAutoresizingMaskIntoConstraints = false

        [mark, title, libraryButton].forEach(topBar.addSubview)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            topBar.heightAnchor.constraint(equalToConstant: 46),

            mark.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            mark.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 34),
            mark.heightAnchor.constraint(equalToConstant: 34),

            title.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            libraryButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            libraryButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            libraryButton.widthAnchor.constraint(equalToConstant: 44),
            libraryButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func buildPreview() {
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.backgroundColor = UIColor(white: 0.055, alpha: 1)
        preview.layer.cornerRadius = 20
        preview.layer.cornerCurve = .continuous
        preview.clipsToBounds = true
        view.addSubview(preview)

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            preview.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.34)
        ])

        previewPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(previewPlaceholder)
        NSLayoutConstraint.activate([
            previewPlaceholder.topAnchor.constraint(equalTo: preview.topAnchor),
            previewPlaceholder.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            previewPlaceholder.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            previewPlaceholder.bottomAnchor.constraint(equalTo: preview.bottomAnchor)
        ])

        let icon = UIImageView(image: UIImage(systemName: "play.rectangle.on.rectangle"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.85)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        previewTitle.text = "Choose a video"
        previewTitle.textColor = .white
        previewTitle.font = .systemFont(ofSize: 24, weight: .bold)
        previewTitle.textAlignment = .center
        previewTitle.translatesAutoresizingMaskIntoConstraints = false

        previewMeta.text = "Tap to import from Photos"
        previewMeta.textColor = UIColor.white.withAlphaComponent(0.45)
        previewMeta.font = .systemFont(ofSize: 14, weight: .medium)
        previewMeta.textAlignment = .center
        previewMeta.translatesAutoresizingMaskIntoConstraints = false

        let filesButton = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.title = "Files"
        cfg.image = UIImage(systemName: "folder")
        cfg.imagePadding = 7
        cfg.baseBackgroundColor = UIColor.white.withAlphaComponent(0.08)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        filesButton.configuration = cfg
        filesButton.addTarget(self, action: #selector(openFiles), for: .touchUpInside)
        filesButton.translatesAutoresizingMaskIntoConstraints = false

        [icon, previewTitle, previewMeta, filesButton].forEach(previewPlaceholder.addSubview)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: previewPlaceholder.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: previewPlaceholder.centerYAnchor, constant: -46),
            icon.widthAnchor.constraint(equalToConstant: 52),
            icon.heightAnchor.constraint(equalToConstant: 52),

            previewTitle.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 14),
            previewTitle.leadingAnchor.constraint(equalTo: previewPlaceholder.leadingAnchor, constant: 20),
            previewTitle.trailingAnchor.constraint(equalTo: previewPlaceholder.trailingAnchor, constant: -20),

            previewMeta.topAnchor.constraint(equalTo: previewTitle.bottomAnchor, constant: 5),
            previewMeta.leadingAnchor.constraint(equalTo: previewPlaceholder.leadingAnchor, constant: 20),
            previewMeta.trailingAnchor.constraint(equalTo: previewPlaceholder.trailingAnchor, constant: -20),

            filesButton.topAnchor.constraint(equalTo: previewMeta.bottomAnchor, constant: 14),
            filesButton.centerXAnchor.constraint(equalTo: previewPlaceholder.centerXAnchor),
            filesButton.heightAnchor.constraint(equalToConstant: 38)
        ])

        previewPlaceholder.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openPhotos)))
    }

    private func buildControls() {
        controlsScroll.translatesAutoresizingMaskIntoConstraints = false
        controlsScroll.showsVerticalScrollIndicator = false
        controlsScroll.alwaysBounceVertical = false
        view.addSubview(controlsScroll)

        controlsStack.axis = .vertical
        controlsStack.spacing = 12
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsScroll.addSubview(controlsStack)

        NSLayoutConstraint.activate([
            controlsScroll.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 12),
            controlsScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsScroll.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -10),

            controlsStack.topAnchor.constraint(equalTo: controlsScroll.contentLayoutGuide.topAnchor),
            controlsStack.bottomAnchor.constraint(equalTo: controlsScroll.contentLayoutGuide.bottomAnchor),
            controlsStack.leadingAnchor.constraint(equalTo: controlsScroll.frameLayoutGuide.leadingAnchor, constant: 16),
            controlsStack.trailingAnchor.constraint(equalTo: controlsScroll.frameLayoutGuide.trailingAnchor, constant: -16)
        ])

        [fps, resolution, motion].forEach(configureSegmented)
        fps.addTarget(self, action: #selector(fpsChanged), for: .valueChanged)
        resolution.addTarget(self, action: #selector(resolutionChanged), for: .valueChanged)
        motion.addTarget(self, action: #selector(motionChanged), for: .valueChanged)
        aiSwitch.addTarget(self, action: #selector(aiChanged), for: .valueChanged)

        controlsStack.addArrangedSubview(optionRow(title: "Frame rate", subtitle: "Output motion", control: fps))
        controlsStack.addArrangedSubview(optionRow(title: "Resolution", subtitle: "Output size", control: resolution))
        controlsStack.addArrangedSubview(toggleRow())
        controlsStack.addArrangedSubview(optionRow(title: "Motion", subtitle: "Interpolation", control: motion))
    }

    private func configureSegmented(_ control: UISegmentedControl) {
        control.selectedSegmentTintColor = .white
        control.backgroundColor = UIColor.white.withAlphaComponent(0.055)
        control.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 14, weight: .bold)], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.6), .font: UIFont.systemFont(ofSize: 14, weight: .semibold)], for: .normal)
        control.heightAnchor.constraint(equalToConstant: 42).isActive = true
    }

    private func optionRow(title: String, subtitle: String, control: UIView) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(white: 0.055, alpha: 1)
        container.layer.cornerRadius = 18
        container.layer.cornerCurve = .continuous
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 92).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.38)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        control.translatesAutoresizingMaskIntoConstraints = false
        [titleLabel, subtitleLabel, control].forEach(container.addSubview)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 15),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.widthAnchor.constraint(equalToConstant: 90),

            control.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 126),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func toggleRow() -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(white: 0.055, alpha: 1)
        container.layer.cornerRadius = 18
        container.layer.cornerCurve = .continuous
        container.heightAnchor.constraint(equalToConstant: 78).isActive = true

        let icon = UIImageView(image: UIImage(systemName: "brain.head.profile"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "AI Super Resolution"
        title.textColor = .white
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.78
        title.translatesAutoresizingMaskIntoConstraints = false

        let sub = UILabel()
        sub.text = "Core ML detail recovery"
        sub.textColor = UIColor.white.withAlphaComponent(0.4)
        sub.font = .systemFont(ofSize: 12, weight: .medium)
        sub.translatesAutoresizingMaskIntoConstraints = false

        aiSwitch.onTintColor = .white
        aiSwitch.thumbTintColor = .black
        aiSwitch.translatesAutoresizingMaskIntoConstraints = false

        [icon, title, sub, aiSwitch].forEach(container.addSubview)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(lessThanOrEqualTo: aiSwitch.leadingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 15),
            sub.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),

            aiSwitch.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            aiSwitch.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func buildActionButton() {
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        var cfg = UIButton.Configuration.filled()
        cfg.title = "Choose a Video"
        cfg.image = UIImage(systemName: "wand.and.stars")
        cfg.imagePadding = 10
        cfg.baseBackgroundColor = .white
        cfg.baseForegroundColor = .black
        cfg.cornerStyle = .large
        actionButton.configuration = cfg
        actionButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        actionButton.addTarget(self, action: #selector(convertTapped), for: .touchUpInside)
        view.addSubview(actionButton)

        NSLayoutConstraint.activate([
            actionButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            actionButton.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    private func buildProgressOverlay() {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.backgroundColor = UIColor.black.withAlphaComponent(0.96)
        progressView.alpha = 0
        progressView.isHidden = true
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        progressPercent.textColor = .white
        progressPercent.font = .systemFont(ofSize: 64, weight: .bold)
        progressPercent.textAlignment = .center
        progressPercent.translatesAutoresizingMaskIntoConstraints = false

        progressStage.textColor = UIColor.white.withAlphaComponent(0.62)
        progressStage.font = .systemFont(ofSize: 16, weight: .semibold)
        progressStage.textAlignment = .center
        progressStage.numberOfLines = 2
        progressStage.translatesAutoresizingMaskIntoConstraints = false

        progressBar.progressTintColor = .white
        progressBar.trackTintColor = UIColor.white.withAlphaComponent(0.12)
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        [progressPercent, progressStage, progressBar].forEach(progressView.addSubview)
        NSLayoutConstraint.activate([
            progressPercent.centerXAnchor.constraint(equalTo: progressView.centerXAnchor),
            progressPercent.centerYAnchor.constraint(equalTo: progressView.centerYAnchor, constant: -28),
            progressStage.topAnchor.constraint(equalTo: progressPercent.bottomAnchor, constant: 12),
            progressStage.leadingAnchor.constraint(equalTo: progressView.leadingAnchor, constant: 30),
            progressStage.trailingAnchor.constraint(equalTo: progressView.trailingAnchor, constant: -30),
            progressBar.topAnchor.constraint(equalTo: progressStage.bottomAnchor, constant: 26),
            progressBar.leadingAnchor.constraint(equalTo: progressView.leadingAnchor, constant: 54),
            progressBar.trailingAnchor.constraint(equalTo: progressView.trailingAnchor, constant: -54)
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
        SFNativeBridge.impactSelection()
        updateActionTitle()
    }

    @objc private func resolutionChanged() {
        model.quality = [.enhanced, .twoK, .fourK][resolution.selectedSegmentIndex]
        SFNativeBridge.impactSelection()
        updateActionTitle()
    }

    @objc private func motionChanged() {
        model.mode = motion.selectedSegmentIndex == 1 ? .smooth : .simple
        SFNativeBridge.impactSelection()
    }

    @objc private func aiChanged() {
        model.upscaleEngine = aiSwitch.isOn ? .ai : .standard
        SFNativeBridge.impactSelection()
    }

    private func updateActionTitle() {
        guard model.input != nil else {
            actionButton.configuration?.title = "Choose a Video"
            return
        }
        let q = ["Native", "2K", "4K"][resolution.selectedSegmentIndex]
        actionButton.configuration?.title = "Enhance · \(model.targetFPS) FPS · \(q)"
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
        let type = provider.registeredTypeIdentifiers.first ?? UTType.movie.identifier
        provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, _ in
            guard let self, let url else { return }
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("screenflow_\(UUID().uuidString).\(ext)")
            try? FileManager.default.removeItem(at: copy)
            do {
                try FileManager.default.copyItem(at: url, to: copy)
                Task { @MainActor in await self.loadVideo(copy) }
            } catch {
                Task { @MainActor in self.showError("Could not import this video.") }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in await loadVideo(url) }
    }

    private func loadVideo(_ url: URL) async {
        await model.setInput(url: url)
        guard let info = model.input else {
            showError(model.errorText ?? "Could not read this video.")
            return
        }

        previewPlaceholder.isHidden = true
        player?.pause()
        player = AVPlayer(url: info.url)
        playerVC.player = player
        if playerVC.parent == nil {
            addChild(playerVC)
            playerVC.view.translatesAutoresizingMaskIntoConstraints = false
            preview.addSubview(playerVC.view)
            NSLayoutConstraint.activate([
                playerVC.view.topAnchor.constraint(equalTo: preview.topAnchor),
                playerVC.view.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
                playerVC.view.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
                playerVC.view.bottomAnchor.constraint(equalTo: preview.bottomAnchor)
            ])
            playerVC.didMove(toParent: self)
        }
        updateActionTitle()
        SFNativeBridge.impactSuccess()
    }

    @objc private func convertTapped() {
        guard model.input != nil else { openPhotos(); return }
        showProgress()
        Task { @MainActor in
            await model.convert(library: library)
            hideProgress()
            if let error = model.errorText {
                showError(error)
            } else if let out = model.output {
                SFNativeBridge.impactSuccess()
                let alert = UIAlertController(title: "Saved to Library", message: "\(out.resolutionText) · \(out.fpsText) · \(out.sizeText)", preferredStyle: .actionSheet)
                alert.addAction(UIAlertAction(title: "Save to Photos", style: .default) { _ in self.model.saveToPhotos() })
                alert.addAction(UIAlertAction(title: "Open Library", style: .default) { _ in self.openLibrary() })
                alert.addAction(UIAlertAction(title: "Done", style: .cancel))
                if let pop = alert.popoverPresentationController { pop.sourceView = self.actionButton; pop.sourceRect = self.actionButton.bounds }
                self.present(alert, animated: true)
            }
        }
    }

    private func showProgress() {
        progressView.isHidden = false
        UIView.animate(withDuration: 0.18) { self.progressView.alpha = 1 }
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let p = Float(max(0, min(1, self.model.progress)))
                self.progressBar.setProgress(p, animated: true)
                self.progressPercent.text = "\(Int(p * 100))%"
                self.progressStage.text = self.model.stageText.isEmpty ? "Processing on-device" : self.model.stageText
            }
        }
    }

    private func hideProgress() {
        progressTimer?.invalidate()
        progressTimer = nil
        UIView.animate(withDuration: 0.18, animations: { self.progressView.alpha = 0 }) { _ in
            self.progressView.isHidden = true
        }
    }

    @objc private func openLibrary() {
        let nav = UINavigationController(rootViewController: LibraryViewController(store: library))
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func showError(_ text: String) {
        let alert = UIAlertController(title: "ScreenFlow", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

@MainActor
final class LibraryViewController: UITableViewController {
    private let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Library"
        view.backgroundColor = .black
        tableView.backgroundColor = .black
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.08)
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationController?.navigationBar.tintColor = .white
        navigationController?.navigationBar.barStyle = .black
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
    }

    @objc private func done() { dismiss(animated: true) }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { store.items.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let id = "cell"
        let cell = tableView.dequeueReusableCell(withIdentifier: id) ?? UITableViewCell(style: .subtitle, reuseIdentifier: id)
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
        let item = store.items[indexPath.row]
        let player = AVPlayerViewController()
        player.player = AVPlayer(url: store.url(for: item))
        present(player, animated: true) { player.player?.play() }
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let item = store.items[indexPath.row]
        store.delete(item)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }
}
