import AVKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class MainViewController: UIViewController, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private let model = VideoModel()
    private let library = LibraryStore()

    private let header = UIView()
    private let preview = UIView()
    private let placeholder = UIStackView()
    private let playerVC = AVPlayerViewController()
    private var player: AVPlayer?

    private let controlsScroll = UIScrollView()
    private let controlsStack = UIStackView()
    private let fps = UISegmentedControl(items: ["24", "30", "60", "120"])
    private let resolution = UISegmentedControl(items: ["Native", "2K", "4K"])
    private let motion = UISegmentedControl(items: ["Fast", "Smooth"])
    private let aiSwitch = UISwitch()
    private let actionButton = UIButton(type: .system)

    private let overlay = UIView()
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let percent = UILabel()
    private let stage = UILabel()
    private var timer: Timer?

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildHeader()
        buildPreview()
        buildActionButton()
        buildControls()
        buildOverlay()
        applyDefaults()
    }

    private func buildHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        let title = UILabel()
        title.text = "ScreenFlow"
        title.textColor = .white
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.adjustsFontForContentSizeCategory = true
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = UILabel()
        subtitle.text = "FPS + AI Video Enhancer"
        subtitle.textColor = UIColor.white.withAlphaComponent(0.42)
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let libraryButton = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.image = UIImage(systemName: "square.stack.3d.up.fill")
        cfg.baseBackgroundColor = UIColor.white.withAlphaComponent(0.08)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        libraryButton.configuration = cfg
        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        libraryButton.addTarget(self, action: #selector(openLibrary), for: .touchUpInside)

        [title, subtitle, libraryButton].forEach(header.addSubview)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            header.heightAnchor.constraint(equalToConstant: 58),

            title.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: 1),
            title.trailingAnchor.constraint(lessThanOrEqualTo: libraryButton.leadingAnchor, constant: -12),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: -1),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: libraryButton.leadingAnchor, constant: -12),

            libraryButton.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            libraryButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            libraryButton.widthAnchor.constraint(equalToConstant: 46),
            libraryButton.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func buildPreview() {
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.backgroundColor = UIColor(white: 0.055, alpha: 1)
        preview.layer.cornerRadius = 22
        preview.layer.cornerCurve = .continuous
        preview.clipsToBounds = true
        view.addSubview(preview)

        let ratio = preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 0.68)
        ratio.priority = .defaultHigh
        let minH = preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        let maxH = preview.heightAnchor.constraint(lessThanOrEqualToConstant: 310)

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            preview.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            preview.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            ratio, minH, maxH
        ])

        placeholder.axis = .vertical
        placeholder.alignment = .center
        placeholder.spacing = 8
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
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let title = UILabel()
        title.text = "Choose a video"
        title.textColor = .white
        title.font = .systemFont(ofSize: 23, weight: .bold)
        title.textAlignment = .center

        let sub = UILabel()
        sub.text = "Photos or Files"
        sub.textColor = UIColor.white.withAlphaComponent(0.43)
        sub.font = .systemFont(ofSize: 14, weight: .medium)
        sub.textAlignment = .center

        let files = UIButton(type: .system)
        var fc = UIButton.Configuration.filled()
        fc.title = "Files"
        fc.image = UIImage(systemName: "folder")
        fc.imagePadding = 6
        fc.baseBackgroundColor = UIColor.white.withAlphaComponent(0.08)
        fc.baseForegroundColor = .white
        fc.cornerStyle = .capsule
        files.configuration = fc
        files.heightAnchor.constraint(equalToConstant: 38).isActive = true
        files.addTarget(self, action: #selector(openFiles), for: .touchUpInside)

        placeholder.addArrangedSubview(icon)
        placeholder.addArrangedSubview(title)
        placeholder.addArrangedSubview(sub)
        placeholder.addArrangedSubview(files)
        placeholder.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openPhotos)))
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
            actionButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            actionButton.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    private func buildControls() {
        controlsScroll.translatesAutoresizingMaskIntoConstraints = false
        controlsScroll.showsVerticalScrollIndicator = false
        controlsScroll.alwaysBounceVertical = false
        view.addSubview(controlsScroll)

        controlsStack.axis = .vertical
        controlsStack.spacing = 9
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsScroll.addSubview(controlsStack)

        NSLayoutConstraint.activate([
            controlsScroll.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 10),
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
        resolution.addTarget(self, action: #selector(resChanged), for: .valueChanged)
        motion.addTarget(self, action: #selector(motionChanged), for: .valueChanged)
        aiSwitch.addTarget(self, action: #selector(aiChanged), for: .valueChanged)

        controlsStack.addArrangedSubview(controlRow(title: "Frame Rate", subtitle: "Output FPS", control: fps))
        controlsStack.addArrangedSubview(controlRow(title: "Resolution", subtitle: "Output size", control: resolution))
        controlsStack.addArrangedSubview(aiRow())
        controlsStack.addArrangedSubview(controlRow(title: "Motion", subtitle: "Interpolation", control: motion))
    }

    private func configureSegmented(_ control: UISegmentedControl) {
        control.selectedSegmentTintColor = .white
        control.backgroundColor = UIColor.white.withAlphaComponent(0.055)
        control.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 14, weight: .bold)], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.58), .font: UIFont.systemFont(ofSize: 14, weight: .semibold)], for: .normal)
        control.heightAnchor.constraint(equalToConstant: 42).isActive = true
    }

    private func controlRow(title: String, subtitle: String, control: UIView) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor(white: 0.055, alpha: 1)
        box.layer.cornerRadius = 17
        box.layer.cornerCurve = .continuous
        box.heightAnchor.constraint(equalToConstant: 68).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.34)
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        control.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(titleLabel)
        box.addSubview(subtitleLabel)
        box.addSubview(control)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 15),
            titleLabel.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            titleLabel.widthAnchor.constraint(equalTo: box.widthAnchor, multiplier: 0.27),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.widthAnchor.constraint(equalTo: titleLabel.widthAnchor),

            control.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            control.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            control.centerYAnchor.constraint(equalTo: box.centerYAnchor)
        ])
        return box
    }

    private func aiRow() -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor(white: 0.055, alpha: 1)
        box.layer.cornerRadius = 17
        box.layer.cornerCurve = .continuous
        box.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "AI Super Resolution"
        title.textColor = .white
        title.font = .systemFont(ofSize: 16, weight: .bold)
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.82

        let sub = UILabel()
        sub.text = "Real-ESRGAN x2 detail recovery"
        sub.textColor = UIColor.white.withAlphaComponent(0.34)
        sub.font = .systemFont(ofSize: 11, weight: .medium)

        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(sub)

        aiSwitch.onTintColor = .white
        aiSwitch.thumbTintColor = .black
        aiSwitch.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(textStack)
        box.addSubview(aiSwitch)
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 15),
            textStack.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            textStack.trailingAnchor.constraint(equalTo: aiSwitch.leadingAnchor, constant: -14),
            aiSwitch.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -15),
            aiSwitch.centerYAnchor.constraint(equalTo: box.centerYAnchor)
        ])
        return box
    }

    private func buildOverlay() {
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.96)
        overlay.isHidden = true
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        percent.textColor = .white
        percent.font = .systemFont(ofSize: 58, weight: .bold)
        percent.textAlignment = .center
        percent.translatesAutoresizingMaskIntoConstraints = false

        stage.textColor = UIColor.white.withAlphaComponent(0.6)
        stage.font = .systemFont(ofSize: 16, weight: .semibold)
        stage.textAlignment = .center
        stage.numberOfLines = 2
        stage.translatesAutoresizingMaskIntoConstraints = false

        progress.progressTintColor = .white
        progress.trackTintColor = UIColor.white.withAlphaComponent(0.12)
        progress.translatesAutoresizingMaskIntoConstraints = false

        [percent, stage, progress].forEach(overlay.addSubview)
        NSLayoutConstraint.activate([
            percent.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            percent.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -32),
            stage.topAnchor.constraint(equalTo: percent.bottomAnchor, constant: 12),
            stage.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 30),
            stage.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -30),
            progress.topAnchor.constraint(equalTo: stage.bottomAnchor, constant: 24),
            progress.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 46),
            progress.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -46)
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
        updateAction()
    }

    @objc private func fpsChanged() {
        model.targetFPS = [24, 30, 60, 120][fps.selectedSegmentIndex]
        SFNativeBridge.impactSelection()
        updateAction()
    }

    @objc private func resChanged() {
        model.quality = [.enhanced, .twoK, .fourK][resolution.selectedSegmentIndex]
        SFNativeBridge.impactSelection()
        updateAction()
    }

    @objc private func motionChanged() {
        model.mode = motion.selectedSegmentIndex == 1 ? .smooth : .simple
        SFNativeBridge.impactSelection()
    }

    @objc private func aiChanged() {
        model.upscaleEngine = aiSwitch.isOn ? .ai : .standard
        SFNativeBridge.impactSelection()
    }

    private func updateAction() {
        guard model.input != nil else {
            actionButton.configuration?.title = "Choose a Video"
            return
        }
        let quality = ["Native", "2K", "4K"][resolution.selectedSegmentIndex]
        actionButton.configuration?.title = "Enhance · \(model.targetFPS) FPS · \(quality)"
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
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        let type = provider.registeredTypeIdentifiers.first ?? UTType.movie.identifier
        provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, _ in
            guard let self, let url else { return }
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("screenflow_input_\(UUID().uuidString).\(ext)")
            try? FileManager.default.removeItem(at: copy)
            do {
                try FileManager.default.copyItem(at: url, to: copy)
                Task { @MainActor in await self.load(copy) }
            } catch {
                Task { @MainActor in self.showError("Could not import this video.") }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in await load(url) }
    }

    private func load(_ url: URL) async {
        await model.setInput(url: url)
        guard let info = model.input else {
            showError(model.errorText ?? "Could not read this video.")
            return
        }

        placeholder.isHidden = true
        if playerVC.parent == nil {
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
        player = AVPlayer(url: info.url)
        playerVC.player = player
        updateAction()
        SFNativeBridge.impactSuccess()
    }

    @objc private func convertTapped() {
        guard model.input != nil else {
            openPhotos()
            return
        }

        overlay.isHidden = false
        percent.text = "0%"
        stage.text = "Preparing"
        progress.progress = 0

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            let p = max(0, min(1, self.model.progress))
            self.percent.text = "\(Int(p * 100))%"
            self.progress.progress = Float(p)
            self.stage.text = self.model.stageText
        }

        Task { @MainActor in
            await model.convert(library: library)
            timer?.invalidate()
            timer = nil
            overlay.isHidden = true
            if let error = model.errorText {
                showError(error)
            } else if let output = model.output {
                SFNativeBridge.impactSuccess()
                showCompletion(output)
            }
        }
    }

    private func showCompletion(_ info: VideoModel.Info) {
        let alert = UIAlertController(title: "Saved", message: "\(info.resolutionText) · \(info.fpsText) · \(info.sizeText)", preferredStyle: .actionSheet)
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

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let id = "video"
        let cell = tableView.dequeueReusableCell(withIdentifier: id) ?? UITableViewCell(style: .subtitle, reuseIdentifier: id)
        let item = store.items[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.secondaryText = "\(item.durationText) · \(item.sizeText)"
        content.textProperties.color = .white
        content.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.48)
        cell.contentConfiguration = content
        cell.backgroundColor = UIColor(white: 0.055, alpha: 1)
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
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
