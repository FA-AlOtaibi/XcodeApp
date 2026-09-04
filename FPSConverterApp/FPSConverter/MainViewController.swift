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
    private let overlay = UIView()
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let percent = UILabel()
    private let stage = UILabel()
    private var timer: Timer?

    private let playerVC = AVPlayerViewController()
    private var player: AVPlayer?
    private weak var previewHost: UIView?
    private weak var previewPlaceholder: UIView?

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureDefaults()
        buildActionButton()
        buildTable()
        buildOverlay()
    }

    private func configureDefaults() {
        model.targetFPS = 60
        model.quality = .fourK
        model.mode = .smooth
        model.upscaleEngine = .ai
    }

    private func buildActionButton() {
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        var c = UIButton.Configuration.filled()
        c.title = "Choose a Video"
        c.image = UIImage(systemName: "wand.and.stars")
        c.imagePadding = 10
        c.baseBackgroundColor = .white
        c.baseForegroundColor = .black
        c.cornerStyle = .large
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 18, weight: .bold)
            return out
        }
        actionButton.configuration = c
        actionButton.addTarget(self, action: #selector(convertTapped), for: .touchUpInside)
        view.addSubview(actionButton)

        NSLayoutConstraint.activate([
            actionButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            actionButton.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    private func buildTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .black
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.alwaysBounceVertical = true
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 0
        view.insertSubview(tableView, belowSubview: actionButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -8)
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

        percent.translatesAutoresizingMaskIntoConstraints = false
        percent.textColor = .white
        percent.font = .systemFont(ofSize: 56, weight: .bold)
        percent.textAlignment = .center

        stage.translatesAutoresizingMaskIntoConstraints = false
        stage.textColor = UIColor.white.withAlphaComponent(0.62)
        stage.font = .systemFont(ofSize: 16, weight: .semibold)
        stage.textAlignment = .center
        stage.numberOfLines = 2

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = .white
        progress.trackTintColor = UIColor.white.withAlphaComponent(0.12)

        overlay.addSubview(percent)
        overlay.addSubview(stage)
        overlay.addSubview(progress)
        NSLayoutConstraint.activate([
            percent.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            percent.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -34),
            stage.topAnchor.constraint(equalTo: percent.bottomAnchor, constant: 12),
            stage.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stage.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            progress.topAnchor.constraint(equalTo: stage.bottomAnchor, constant: 24),
            progress.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 44),
            progress.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -44)
        ])
    }

    // MARK: Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 7 }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.row {
        case 0: return 70
        case 1:
            let w = max(280, view.bounds.width - 32)
            return min(300, max(210, w * 0.56)) + 12
        case 2: return 64
        case 3, 4, 6: return 112
        case 5: return 86
        default: return 90
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none

        let content: UIView
        switch indexPath.row {
        case 0: content = headerView()
        case 1: content = previewView()
        case 2: content = importRow()
        case 3: content = optionCard(title: "Frame Rate", subtitle: "Output FPS", items: ["24", "30", "60", "120"], selected: fpsIndex, action: #selector(fpsChanged(_:)))
        case 4: content = optionCard(title: "Resolution", subtitle: "Native, 2K or 4K", items: ["Native", "2K", "4K"], selected: qualityIndex, action: #selector(resolutionChanged(_:)))
        case 5: content = aiCard()
        case 6: content = optionCard(title: "Motion", subtitle: "Fast or smooth interpolation", items: ["Fast", "Smooth"], selected: model.mode == .smooth ? 1 : 0, action: #selector(motionChanged(_:)))
        default: content = UIView()
        }

        content.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: indexPath.row == 0 ? 18 : 16),
            content.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: indexPath.row == 0 ? -18 : -16),
            content.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 6),
            content.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -6)
        ])
        return cell
    }

    private var fpsIndex: Int {
        switch model.targetFPS { case 24: return 0; case 30: return 1; case 120: return 3; default: return 2 }
    }

    private var qualityIndex: Int {
        switch model.quality { case .enhanced: return 0; case .twoK: return 1; case .fourK: return 2 }
    }

    private func headerView() -> UIView {
        let wrap = UIView()
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
        var c = UIButton.Configuration.filled()
        c.image = UIImage(systemName: "square.stack.3d.up.fill")
        c.baseBackgroundColor = UIColor.white.withAlphaComponent(0.08)
        c.baseForegroundColor = .white
        c.cornerStyle = .capsule
        libraryButton.configuration = c
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

    private func previewView() -> UIView {
        let host = UIView()
        host.backgroundColor = UIColor(white: 0.055, alpha: 1)
        host.layer.cornerRadius = 22
        host.layer.cornerCurve = .continuous
        host.clipsToBounds = true
        previewHost = host

        if let info = model.input {
            let p = AVPlayer(url: info.url)
            player = p
            playerVC.player = p
            if playerVC.parent == nil { addChild(playerVC) }
            let pv = playerVC.view!
            pv.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(pv)
            NSLayoutConstraint.activate([
                pv.topAnchor.constraint(equalTo: host.topAnchor),
                pv.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                pv.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                pv.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            ])
            if playerVC.parent === self { playerVC.didMove(toParent: self) }
        } else {
            let holder = UIView()
            holder.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(holder)
            previewPlaceholder = holder
            NSLayoutConstraint.activate([
                holder.topAnchor.constraint(equalTo: host.topAnchor),
                holder.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                holder.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                holder.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            ])

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
            holder.addSubview(icon); holder.addSubview(title); holder.addSubview(sub)
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: holder.centerYAnchor, constant: -36),
                icon.widthAnchor.constraint(equalToConstant: 52),
                icon.heightAnchor.constraint(equalToConstant: 52),
                title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
                title.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 20),
                title.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -20),
                sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
                sub.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                sub.trailingAnchor.constraint(equalTo: title.trailingAnchor)
            ])
            holder.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openPhotos)))
        }
        return host
    }

    private func importRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        let photos = importButton("Photos", icon: "photo.on.rectangle.angled", primary: true)
        let files = importButton("Files", icon: "folder", primary: false)
        photos.addTarget(self, action: #selector(openPhotos), for: .touchUpInside)
        files.addTarget(self, action: #selector(openFiles), for: .touchUpInside)
        row.addArrangedSubview(photos)
        row.addArrangedSubview(files)
        return row
    }

    private func importButton(_ title: String, icon: String, primary: Bool) -> UIButton {
        let b = UIButton(type: .system)
        var c = UIButton.Configuration.filled()
        c.title = title
        c.image = UIImage(systemName: icon)
        c.imagePadding = 8
        c.baseBackgroundColor = primary ? .white : UIColor.white.withAlphaComponent(0.08)
        c.baseForegroundColor = primary ? .black : .white
        c.cornerStyle = .large
        b.configuration = c
        return b
    }

    private func optionCard(title: String, subtitle: String, items: [String], selected: Int, action: Selector) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.055, alpha: 1)
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous

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

        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = selected
        control.selectedSegmentTintColor = .white
        control.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        control.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 14, weight: .bold)], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.62), .font: UIFont.systemFont(ofSize: 14, weight: .semibold)], for: .normal)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.addTarget(self, action: action, for: .valueChanged)

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

    private func aiCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.055, alpha: 1)
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous

        let title = UILabel(); title.text = "AI Super Resolution"; title.textColor = .white; title.font = .systemFont(ofSize: 18, weight: .bold)
        let subtitle = UILabel(); subtitle.text = "Real-ESRGAN x2"; subtitle.textColor = UIColor.white.withAlphaComponent(0.38); subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        let text = UIStackView(arrangedSubviews: [title, subtitle]); text.axis = .vertical; text.spacing = 2; text.translatesAutoresizingMaskIntoConstraints = false
        let sw = UISwitch(); sw.isOn = model.upscaleEngine == .ai; sw.onTintColor = .white; sw.thumbTintColor = .black; sw.translatesAutoresizingMaskIntoConstraints = false
        sw.addTarget(self, action: #selector(aiChanged(_:)), for: .valueChanged)
        card.addSubview(text); card.addSubview(sw)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            text.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: sw.leadingAnchor, constant: -12),
            sw.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
            sw.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
        return card
    }

    // MARK: Actions

    @objc private func fpsChanged(_ sender: UISegmentedControl) {
        model.targetFPS = [24, 30, 60, 120][sender.selectedSegmentIndex]
        updateAction()
    }

    @objc private func resolutionChanged(_ sender: UISegmentedControl) {
        model.quality = [.enhanced, .twoK, .fourK][sender.selectedSegmentIndex]
        updateAction()
    }

    @objc private func motionChanged(_ sender: UISegmentedControl) {
        model.mode = sender.selectedSegmentIndex == 1 ? .smooth : .simple
    }

    @objc private func aiChanged(_ sender: UISwitch) {
        model.upscaleEngine = sender.isOn ? .ai : .standard
    }

    private func updateAction() {
        guard model.input != nil else { actionButton.configuration?.title = "Choose a Video"; return }
        let q = ["Native", "2K", "4K"][qualityIndex]
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
            if let url, let copy = try? Self.copyImportedFile(url, preferredExtension: url.pathExtension) {
                Task { @MainActor in await self.finishImport(copy) }
                return
            }
            provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, dataError in
                guard let self else { return }
                guard let data, !data.isEmpty else {
                    Task { @MainActor in self.setImporting(false); self.showError(dataError?.localizedDescription ?? fileError?.localizedDescription ?? "Could not import this video.") }
                    return
                }
                do {
                    let ext = UTType(type)?.preferredFilenameExtension ?? "mov"
                    let dst = FileManager.default.temporaryDirectory.appendingPathComponent("screenflow_\(UUID().uuidString).\(ext)")
                    try data.write(to: dst, options: .atomic)
                    Task { @MainActor in await self.finishImport(dst) }
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
            Task { @MainActor in await finishImport(copy) }
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
        guard model.input != nil else { showError(model.errorText ?? "Could not read this video."); return }
        tableView.reloadData()
        updateAction()
    }

    private func setImporting(_ importing: Bool) {
        actionButton.isEnabled = !importing
        actionButton.configuration?.showsActivityIndicator = importing
        if importing { actionButton.configuration?.title = "Importing…" } else { updateAction() }
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
            timer?.invalidate(); timer = nil; overlay.isHidden = true
            if let error = model.errorText { showError(error) } else { SFNativeBridge.impactSuccess() }
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
        let p = AVPlayerViewController(); p.player = AVPlayer(url: store.url(for: store.items[indexPath.row])); present(p, animated: true) { p.player?.play() }
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let item = store.items[indexPath.row]; store.delete(item); tableView.deleteRows(at: [indexPath], with: .automatic)
    }
}
