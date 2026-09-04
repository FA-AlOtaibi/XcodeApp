import AVKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class MainViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private let model = VideoModel()
    private let library = LibraryStore()

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let actionButton = UIButton(type: .system)
    private let fps = UISegmentedControl(items: ["24", "30", "60", "120"])
    private let resolution = UISegmentedControl(items: ["Native", "2K", "4K"])
    private let motion = UISegmentedControl(items: ["Fast", "Smooth"])
    private let aiSwitch = UISwitch()

    private let playerVC = AVPlayerViewController()
    private var player: AVPlayer?
    private weak var previewHost: UIView?
    private weak var previewPlaceholder: UIView?

    private let overlay = UIView()
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let percent = UILabel()
    private let stage = UILabel()
    private var timer: Timer?

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildTable()
        buildActionButton()
        buildOverlay()
        applyDefaults()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // We manage safe-area spacing ourselves. This prevents UIKit from adding
        // a second automatic top inset on different iPhone sizes.
        tableView.contentInset = UIEdgeInsets(top: max(8, view.safeAreaInsets.top + 6), left: 0, bottom: 18, right: 0)
        tableView.scrollIndicatorInsets = tableView.contentInset
    }

    private func buildTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .black
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.alwaysBounceVertical = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 90
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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

        // Keep table content visible above the fixed action button on every screen height.
        tableView.contentInset.bottom = 96
        tableView.scrollIndicatorInsets.bottom = 96
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
        percent.font = .systemFont(ofSize: 56, weight: .bold)
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
            percent.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -34),
            stage.topAnchor.constraint(equalTo: percent.bottomAnchor, constant: 12),
            stage.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 30),
            stage.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -30),
            progress.topAnchor.constraint(equalTo: stage.bottomAnchor, constant: 24),
            progress.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 46),
            progress.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -46)
        ])
    }

    private func applyDefaults() {
        configureSegment(fps)
        configureSegment(resolution)
        configureSegment(motion)

        fps.selectedSegmentIndex = 2
        resolution.selectedSegmentIndex = 2
        motion.selectedSegmentIndex = 1
        aiSwitch.isOn = true

        model.targetFPS = 60
        model.quality = .fourK
        model.mode = .smooth
        model.upscaleEngine = .ai

        fps.addTarget(self, action: #selector(fpsChanged), for: .valueChanged)
        resolution.addTarget(self, action: #selector(resChanged), for: .valueChanged)
        motion.addTarget(self, action: #selector(motionChanged), for: .valueChanged)
        aiSwitch.addTarget(self, action: #selector(aiChanged), for: .valueChanged)
        updateAction()
    }

    private func configureSegment(_ control: UISegmentedControl) {
        control.selectedSegmentTintColor = .white
        control.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        control.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 14, weight: .bold)], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.62), .font: UIFont.systemFont(ofSize: 14, weight: .semibold)], for: .normal)
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 7 }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.row {
        case 0: return 72
        case 1:
            let usableWidth = max(280, view.bounds.width - 32)
            return min(310, max(205, usableWidth * 0.56)) + 12
        case 2: return 66
        case 3, 4, 6: return 112
        case 5: return 88
        default: return 88
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none

        switch indexPath.row {
        case 0: cell.contentView.addSubview(makeHeader(in: cell.contentView))
        case 1: cell.contentView.addSubview(makePreview(in: cell.contentView))
        case 2: cell.contentView.addSubview(makeImportRow(in: cell.contentView))
        case 3: cell.contentView.addSubview(makeControlCard(in: cell.contentView, title: "Frame Rate", subtitle: "Output FPS", control: fps))
        case 4: cell.contentView.addSubview(makeControlCard(in: cell.contentView, title: "Resolution", subtitle: "Native, 2K or 4K", control: resolution))
        case 5: cell.contentView.addSubview(makeAIBox(in: cell.contentView))
        case 6: cell.contentView.addSubview(makeControlCard(in: cell.contentView, title: "Motion", subtitle: "Fast or smooth interpolation", control: motion))
        default: break
        }
        return cell
    }

    private func pin(_ child: UIView, in parent: UIView, horizontal: CGFloat = 16, vertical: CGFloat = 6) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: horizontal),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -horizontal),
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: vertical),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -vertical)
        ])
    }

    private func makeHeader(in parent: UIView) -> UIView {
        let wrap = UIView()
        pin(wrap, in: parent, horizontal: 18, vertical: 4)

        let title = UILabel()
        title.text = "ScreenFlow"
        title.textColor = .white
        title.font = .systemFont(ofSize: 30, weight: .bold)

        let subtitle = UILabel()
        subtitle.text = "FPS + AI Video Enhancer"
        subtitle.textColor = UIColor.white.withAlphaComponent(0.42)
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)

        let labels = UIStackView(arrangedSubviews: [title, subtitle])
        labels.axis = .vertical
        labels.spacing = 1
        labels.translatesAutoresizingMaskIntoConstraints = false

        let libraryButton = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.image = UIImage(systemName: "square.stack.3d.up.fill")
        cfg.baseBackgroundColor = UIColor.white.withAlphaComponent(0.08)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        libraryButton.configuration = cfg
        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        libraryButton.addTarget(self, action: #selector(openLibrary), for: .touchUpInside)

        wrap.addSubview(labels)
        wrap.addSubview(libraryButton)
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            labels.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: libraryButton.leadingAnchor, constant: -12),
            libraryButton.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            libraryButton.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            libraryButton.widthAnchor.constraint(equalToConstant: 48),
            libraryButton.heightAnchor.constraint(equalToConstant: 48)
        ])
        return wrap
    }

    private func makePreview(in parent: UIView) -> UIView {
        let host = UIView()
        host.backgroundColor = UIColor(white: 0.055, alpha: 1)
        host.layer.cornerRadius = 22
        host.layer.cornerCurve = .continuous
        host.clipsToBounds = true
        pin(host, in: parent, horizontal: 16, vertical: 6)
        previewHost = host

        let placeholder = UIView()
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: host.topAnchor),
            placeholder.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            placeholder.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        previewPlaceholder = placeholder

        let icon = UIImageView(image: UIImage(systemName: "video.badge.plus"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "Choose a video"
        title.textColor = .white
        title.font = .systemFont(ofSize: 23, weight: .bold)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let sub = UILabel()
        sub.text = "Photos or Files"
        sub.textColor = UIColor.white.withAlphaComponent(0.42)
        sub.font = .systemFont(ofSize: 14, weight: .medium)
        sub.textAlignment = .center
        sub.translatesAutoresizingMaskIntoConstraints = false

        [icon, title, sub].forEach(placeholder.addSubview)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: placeholder.centerYAnchor, constant: -36),
            icon.widthAnchor.constraint(equalToConstant: 52),
            icon.heightAnchor.constraint(equalToConstant: 52),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: placeholder.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: placeholder.trailingAnchor, constant: -20),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            sub.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            sub.trailingAnchor.constraint(equalTo: title.trailingAnchor)
        ])
        placeholder.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openPhotos)))
        return host
    }

    private func makeImportRow(in parent: UIView) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        pin(row, in: parent, horizontal: 16, vertical: 7)

        let photos = importButton(title: "Photos", icon: "photo.on.rectangle.angled", primary: true)
        let files = importButton(title: "Files", icon: "folder", primary: false)
        photos.addTarget(self, action: #selector(openPhotos), for: .touchUpInside)
        files.addTarget(self, action: #selector(openFiles), for: .touchUpInside)
        row.addArrangedSubview(photos)
        row.addArrangedSubview(files)
        return row
    }

    private func importButton(title: String, icon: String, primary: Bool) -> UIButton {
        let b = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.title = title
        cfg.image = UIImage(systemName: icon)
        cfg.imagePadding = 8
        cfg.baseBackgroundColor = primary ? .white : UIColor.white.withAlphaComponent(0.08)
        cfg.baseForegroundColor = primary ? .black : .white
        cfg.cornerStyle = .large
        b.configuration = cfg
        return b
    }

    private func makeControlCard(in parent: UIView, title: String, subtitle: String, control: UISegmentedControl) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.055, alpha: 1)
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        pin(card, in: parent, horizontal: 16, vertical: 6)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.38)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let text = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        text.axis = .vertical
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(text)
        card.addSubview(control)
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            text.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            text.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
            control.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            control.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
            control.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            control.heightAnchor.constraint(equalToConstant: 42)
        ])
        return card
    }

    private func makeAIBox(in parent: UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.055, alpha: 1)
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        pin(card, in: parent, horizontal: 16, vertical: 6)

        let title = UILabel()
        title.text = "AI Super Resolution"
        title.textColor = .white
        title.font = .systemFont(ofSize: 18, weight: .bold)

        let subtitle = UILabel()
        subtitle.text = "Real-ESRGAN x2"
        subtitle.textColor = UIColor.white.withAlphaComponent(0.38)
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)

        let text = UIStackView(arrangedSubviews: [title, subtitle])
        text.axis = .vertical
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false
        aiSwitch.onTintColor = .white
        aiSwitch.thumbTintColor = .black
        aiSwitch.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(text)
        card.addSubview(aiSwitch)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            text.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: aiSwitch.leadingAnchor, constant: -12),
            aiSwitch.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
            aiSwitch.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
        return card
    }

    // MARK: - Actions

    @objc private func fpsChanged() {
        model.targetFPS = [24, 30, 60, 120][fps.selectedSegmentIndex]
        updateAction()
    }

    @objc private func resChanged() {
        model.quality = [.enhanced, .twoK, .fourK][resolution.selectedSegmentIndex]
        updateAction()
    }

    @objc private func motionChanged() {
        model.mode = motion.selectedSegmentIndex == 1 ? .smooth : .simple
    }

    @objc private func aiChanged() {
        model.upscaleEngine = aiSwitch.isOn ? .ai : .standard
    }

    private func updateAction() {
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
        setImporting(true)

        let type = provider.registeredTypeIdentifiers.first(where: { id in
            guard let t = UTType(id) else { return false }
            return t.conforms(to: .movie) || t.conforms(to: .video)
        }) ?? UTType.movie.identifier

        provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, fileError in
            guard let self else { return }
            if let url {
                do {
                    let copy = try Self.copyImportedFile(url, preferredExtension: url.pathExtension)
                    Task { @MainActor in await self.finishImport(copy) }
                    return
                } catch { }
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
                do {
                    let ext = UTType(type)?.preferredFilenameExtension ?? "mov"
                    let dst = FileManager.default.temporaryDirectory.appendingPathComponent("screenflow_\(UUID().uuidString).\(ext)")
                    try data.write(to: dst, options: .atomic)
                    Task { @MainActor in await self.finishImport(dst) }
                } catch {
                    Task { @MainActor in
                        self.setImporting(false)
                        self.showError(error.localizedDescription)
                    }
                }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        setImporting(true)
        do {
            let copy = try Self.copyImportedFile(url, preferredExtension: url.pathExtension)
            Task { await finishImport(copy) }
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

    private func finishImport(_ url: URL) async {
        await model.setInput(url: url)
        setImporting(false)
        guard let info = model.input else {
            showError(model.errorText ?? "Could not read this video.")
            return
        }

        previewPlaceholder?.isHidden = true
        player = AVPlayer(url: info.url)
        playerVC.player = player

        if playerVC.parent == nil { addChild(playerVC) }
        if let host = previewHost {
            let playerView = playerVC.view!
            playerView.removeFromSuperview()
            playerView.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(playerView)
            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(equalTo: host.topAnchor),
                playerView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                playerView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            ])
            playerVC.didMove(toParent: self)
        }
        updateAction()
    }

    private func setImporting(_ importing: Bool) {
        actionButton.isEnabled = !importing
        actionButton.configuration?.showsActivityIndicator = importing
        if importing { actionButton.configuration?.title = "Importing…" }
        else { updateAction() }
    }

    @objc private func convertTapped() {
        guard model.input != nil else { openPhotos(); return }
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
            if let error = model.errorText { showError(error) }
            else { SFNativeBridge.impactSuccess() }
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
        let player = AVPlayerViewController()
        player.player = AVPlayer(url: store.url(for: store.items[indexPath.row]))
        present(player, animated: true) { player.player?.play() }
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let item = store.items[indexPath.row]
        store.delete(item)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }
}
