import AVKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class MainViewController: UIViewController, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private let model = VideoModel()
    private let library = LibraryStore()

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
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
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let percent = UILabel()
    private let stage = UILabel()
    private var timer: Timer?

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildRootLayout()
        buildOverlay()
        applyDefaults()
    }

    private func buildRootLayout() {
        buildActionButton()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -10),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16)
        ])

        contentStack.addArrangedSubview(makeHeader())
        contentStack.addArrangedSubview(makePreview())
        contentStack.addArrangedSubview(makeImportButtons())
        contentStack.addArrangedSubview(makeSection(title: "Frame rate", subtitle: "Choose the output FPS", control: fps))
        contentStack.addArrangedSubview(makeSection(title: "Resolution", subtitle: "Keep native size or upscale", control: resolution))
        contentStack.addArrangedSubview(makeAISection())
        contentStack.addArrangedSubview(makeSection(title: "Motion", subtitle: "Smooth creates in-between frames", control: motion))

        [fps, resolution, motion].forEach(configureSegmented)
        fps.addTarget(self, action: #selector(fpsChanged), for: .valueChanged)
        resolution.addTarget(self, action: #selector(resChanged), for: .valueChanged)
        motion.addTarget(self, action: #selector(motionChanged), for: .valueChanged)
        aiSwitch.addTarget(self, action: #selector(aiChanged), for: .valueChanged)
    }

    private func makeHeader() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12

        let text = UIStackView()
        text.axis = .vertical
        text.spacing = 1

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
        libraryButton.widthAnchor.constraint(equalToConstant: 48).isActive = true
        libraryButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
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

        let aspect = preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 0.62)
        aspect.priority = .required
        aspect.isActive = true

        addChild(playerVC)
        let playerView = playerVC.view!
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.isHidden = true
        preview.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: preview.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: preview.bottomAnchor)
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
        icon.widthAnchor.constraint(equalToConstant: 46).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 46).isActive = true

        let title = UILabel()
        title.text = "Choose a video"
        title.textColor = .white
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textAlignment = .center

        let sub = UILabel()
        sub.text = "Photos or Files"
        sub.textColor = UIColor.white.withAlphaComponent(0.42)
        sub.font = .systemFont(ofSize: 13, weight: .medium)
        sub.textAlignment = .center

        placeholder.addArrangedSubview(icon)
        placeholder.addArrangedSubview(title)
        placeholder.addArrangedSubview(sub)
        placeholder.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openPhotos)))
        return preview
    }

    private func makeImportButtons() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually

        let photos = smallButton(title: "Photos", icon: "photo.on.rectangle.angled", primary: true)
        photos.addTarget(self, action: #selector(openPhotos), for: .touchUpInside)
        let files = smallButton(title: "Files", icon: "folder", primary: false)
        files.addTarget(self, action: #selector(openFiles), for: .touchUpInside)

        row.addArrangedSubview(photos)
        row.addArrangedSubview(files)
        row.heightAnchor.constraint(equalToConstant: 52).isActive = true
        return row
    }

    private func makeSection(title: String, subtitle: String, control: UISegmentedControl) -> UIView {
        let card = cardView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.38)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let heading = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        heading.axis = .vertical
        heading.spacing = 1

        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(control)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 15),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -15)
        ])
        return card
    }

    private func makeAISection() -> UIView {
        let card = cardView()
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        let text = UIStackView()
        text.axis = .vertical
        text.spacing = 2

        let title = UILabel()
        title.text = "AI Super Resolution"
        title.textColor = .white
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.78

        let subtitle = UILabel()
        subtitle.text = "Real-ESRGAN x2 detail recovery"
        subtitle.textColor = UIColor.white.withAlphaComponent(0.38)
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)

        text.addArrangedSubview(title)
        text.addArrangedSubview(subtitle)

        aiSwitch.onTintColor = .white
        aiSwitch.thumbTintColor = .black
        aiSwitch.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addArrangedSubview(text)
        row.addArrangedSubview(aiSwitch)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    private func cardView() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.055, alpha: 1)
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.05).cgColor
        card.layer.borderWidth = 1
        return card
    }

    private func configureSegmented(_ control: UISegmentedControl) {
        control.selectedSegmentTintColor = .white
        control.backgroundColor = UIColor.white.withAlphaComponent(0.055)
        control.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 14, weight: .bold)], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.58), .font: UIFont.systemFont(ofSize: 14, weight: .semibold)], for: .normal)
        control.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func smallButton(title: String, icon: String, primary: Bool) -> UIButton {
        let button = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.title = title
        cfg.image = UIImage(systemName: icon)
        cfg.imagePadding = 8
        cfg.baseBackgroundColor = primary ? .white : UIColor.white.withAlphaComponent(0.08)
        cfg.baseForegroundColor = primary ? .black : .white
        cfg.cornerStyle = .large
        button.configuration = cfg
        return button
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

        stage.textColor = UIColor.white.withAlphaComponent(0.62)
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
            percent.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -30),
            stage.topAnchor.constraint(equalTo: percent.bottomAnchor, constant: 12),
            stage.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stage.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            progress.topAnchor.constraint(equalTo: stage.bottomAnchor, constant: 24),
            progress.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 44),
            progress.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -44)
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
        config.preferredAssetRepresentationMode = .compatible
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
        actionButton.isEnabled = false
        actionButton.configuration?.title = "Importing…"

        let preferredType: String = {
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) { return UTType.movie.identifier }
            if provider.hasItemConformingToTypeIdentifier(UTType.video.identifier) { return UTType.video.identifier }
            return provider.registeredTypeIdentifiers.first ?? UTType.movie.identifier
        }()

        provider.loadFileRepresentation(forTypeIdentifier: preferredType) { [weak self] url, fileError in
            guard let self else { return }
            if let url, let copied = self.copyImportedFile(url: url) {
                Task { @MainActor in await self.finishImport(copied) }
                return
            }

            provider.loadDataRepresentation(forTypeIdentifier: preferredType) { [weak self] data, dataError in
                guard let self else { return }
                guard let data else {
                    Task { @MainActor in
                        self.actionButton.isEnabled = true
                        self.updateAction()
                        let message = dataError?.localizedDescription ?? fileError?.localizedDescription ?? "Could not import this video from Photos."
                        self.showError(message)
                    }
                    return
                }
                let ext = UTType(preferredType)?.preferredFilenameExtension ?? "mov"
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("screenflow_\(UUID().uuidString).\(ext)")
                do {
                    try data.write(to: dest, options: .atomic)
                    Task { @MainActor in await self.finishImport(dest) }
                } catch {
                    Task { @MainActor in
                        self.actionButton.isEnabled = true
                        self.updateAction()
                        self.showError("The video was selected, but ScreenFlow could not copy it into the app.")
                    }
                }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let source = urls.first else { return }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        guard let copied = copyImportedFile(url: source) else {
            showError("ScreenFlow could not copy this file into the app.")
            return
        }
        Task { await finishImport(copied) }
    }

    private nonisolated func copyImportedFile(url: URL) -> URL? {
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("screenflow_\(UUID().uuidString).\(ext)")
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private func finishImport(_ url: URL) async {
        await model.setInput(url: url)
        actionButton.isEnabled = true
        guard let info = model.input else {
            updateAction()
            showError(model.errorText ?? "ScreenFlow could not read this video.")
            return
        }

        player = AVPlayer(url: info.url)
        playerVC.player = player
        playerVC.view.isHidden = false
        placeholder.isHidden = true
        updateAction()
        SFNativeBridge.impactSuccess()
    }

    @objc private func convertTapped() {
        guard model.input != nil else {
            openPhotos()
            return
        }

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
            timer?.invalidate()
            timer = nil
            overlay.isHidden = true
            if let error = model.errorText {
                showError(error)
            } else {
                SFNativeBridge.impactSuccess()
                showCompletion()
            }
        }
    }

    private func showCompletion() {
        let alert = UIAlertController(title: "Saved", message: "The enhanced video was saved to ScreenFlow Library.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Open Library", style: .default) { _ in self.openLibrary() })
        alert.addAction(UIAlertAction(title: "Done", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = actionButton
            popover.sourceRect = actionButton.bounds
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
        navigationController?.navigationBar.barStyle = .black
        navigationController?.navigationBar.tintColor = .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
    }

    @objc private func done() { dismiss(animated: true) }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "video") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "video")
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
