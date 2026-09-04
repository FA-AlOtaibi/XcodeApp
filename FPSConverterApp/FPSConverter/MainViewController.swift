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
    private let placeholder = UIView()
    private let playerVC = AVPlayerViewController()
    private var player: AVPlayer?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
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
        buildActionButton()   // IMPORTANT: add this before constraints reference it
        buildControls()
        buildOverlay()
        applyDefaults()
    }

    private func buildHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        let icon = UIImageView(image: UIImage(systemName: "waveform.path.ecg"))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "ScreenFlow"
        title.textColor = .white
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let lib = UIButton(type: .system)
        var c = UIButton.Configuration.filled()
        c.image = UIImage(systemName: "square.stack.3d.up.fill")
        c.baseBackgroundColor = UIColor.white.withAlphaComponent(0.08)
        c.baseForegroundColor = .white
        c.cornerStyle = .capsule
        lib.configuration = c
        lib.translatesAutoresizingMaskIntoConstraints = false
        lib.addTarget(self, action: #selector(openLibrary), for: .touchUpInside)

        [icon, title, lib].forEach(header.addSubview)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            header.heightAnchor.constraint(equalToConstant: 46),
            icon.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            lib.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            lib.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            lib.widthAnchor.constraint(equalToConstant: 44),
            lib.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func buildPreview() {
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.backgroundColor = UIColor(white: 0.055, alpha: 1)
        preview.layer.cornerRadius = 22
        preview.layer.cornerCurve = .continuous
        preview.clipsToBounds = true
        view.addSubview(preview)

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            preview.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.34)
        ])

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: preview.topAnchor),
            placeholder.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            placeholder.bottomAnchor.constraint(equalTo: preview.bottomAnchor)
        ])

        let icon = UIImageView(image: UIImage(systemName: "video.badge.plus"))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "Choose a video"
        title.textColor = .white
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let sub = UILabel()
        sub.text = "Photos or Files"
        sub.textColor = UIColor.white.withAlphaComponent(0.45)
        sub.font = .systemFont(ofSize: 14, weight: .medium)
        sub.translatesAutoresizingMaskIntoConstraints = false

        let files = UIButton(type: .system)
        var fc = UIButton.Configuration.filled()
        fc.title = "Files"
        fc.image = UIImage(systemName: "folder")
        fc.imagePadding = 6
        fc.baseBackgroundColor = UIColor.white.withAlphaComponent(0.08)
        fc.baseForegroundColor = .white
        fc.cornerStyle = .capsule
        files.configuration = fc
        files.translatesAutoresizingMaskIntoConstraints = false
        files.addTarget(self, action: #selector(openFiles), for: .touchUpInside)

        [icon, title, sub, files].forEach(placeholder.addSubview)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: placeholder.centerYAnchor, constant: -48),
            icon.widthAnchor.constraint(equalToConstant: 52), icon.heightAnchor.constraint(equalToConstant: 52),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 14),
            title.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            sub.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            files.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 13),
            files.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            files.heightAnchor.constraint(equalToConstant: 38)
        ])

        placeholder.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openPhotos)))
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
        actionButton.configuration = c
        actionButton.addTarget(self, action: #selector(convertTapped), for: .touchUpInside)
        view.addSubview(actionButton)

        NSLayoutConstraint.activate([
            actionButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            actionButton.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    private func buildControls() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll)

        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16)
        ])

        [fps, resolution, motion].forEach(configure)
        fps.addTarget(self, action: #selector(fpsChanged), for: .valueChanged)
        resolution.addTarget(self, action: #selector(resChanged), for: .valueChanged)
        motion.addTarget(self, action: #selector(motionChanged), for: .valueChanged)
        aiSwitch.addTarget(self, action: #selector(aiChanged), for: .valueChanged)

        stack.addArrangedSubview(row("Frame Rate", control: fps))
        stack.addArrangedSubview(row("Resolution", control: resolution))
        stack.addArrangedSubview(aiRow())
        stack.addArrangedSubview(row("Motion", control: motion))
    }

    private func configure(_ s: UISegmentedControl) {
        s.selectedSegmentTintColor = .white
        s.backgroundColor = UIColor.white.withAlphaComponent(0.055)
        s.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 14, weight: .bold)], for: .selected)
        s.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.6), .font: UIFont.systemFont(ofSize: 14, weight: .semibold)], for: .normal)
        s.heightAnchor.constraint(equalToConstant: 42).isActive = true
    }

    private func row(_ title: String, control: UIView) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor(white: 0.055, alpha: 1)
        box.layer.cornerRadius = 18
        box.heightAnchor.constraint(equalToConstant: 76).isActive = true

        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = .systemFont(ofSize: 17, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label); box.addSubview(control)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 100),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            control.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            control.centerYAnchor.constraint(equalTo: box.centerYAnchor)
        ])
        return box
    }

    private func aiRow() -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor(white: 0.055, alpha: 1)
        box.layer.cornerRadius = 18
        box.heightAnchor.constraint(equalToConstant: 68).isActive = true

        let label = UILabel()
        label.text = "AI Super Resolution"
        label.textColor = .white
        label.font = .systemFont(ofSize: 17, weight: .bold)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        label.translatesAutoresizingMaskIntoConstraints = false
        aiSwitch.onTintColor = .white
        aiSwitch.thumbTintColor = .black
        aiSwitch.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label); box.addSubview(aiSwitch)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: aiSwitch.leadingAnchor, constant: -14),
            aiSwitch.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
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
            overlay.topAnchor.constraint(equalTo: view.topAnchor), overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor), overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        percent.textColor = .white; percent.font = .systemFont(ofSize: 60, weight: .bold); percent.textAlignment = .center
        percent.translatesAutoresizingMaskIntoConstraints = false
        stage.textColor = UIColor.white.withAlphaComponent(0.6); stage.font = .systemFont(ofSize: 16, weight: .semibold); stage.textAlignment = .center
        stage.translatesAutoresizingMaskIntoConstraints = false
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = .white; progress.trackTintColor = UIColor.white.withAlphaComponent(0.12)
        [percent, stage, progress].forEach(overlay.addSubview)
        NSLayoutConstraint.activate([
            percent.centerXAnchor.constraint(equalTo: overlay.centerXAnchor), percent.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -30),
            stage.topAnchor.constraint(equalTo: percent.bottomAnchor, constant: 12), stage.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 30), stage.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -30),
            progress.topAnchor.constraint(equalTo: stage.bottomAnchor, constant: 26), progress.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 54), progress.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -54)
        ])
    }

    private func applyDefaults() {
        fps.selectedSegmentIndex = 2; resolution.selectedSegmentIndex = 2; motion.selectedSegmentIndex = 1; aiSwitch.isOn = true
        model.targetFPS = 60; model.quality = .fourK; model.mode = .smooth; model.upscaleEngine = .ai
        updateAction()
    }

    @objc private func fpsChanged() { model.targetFPS = [24,30,60,120][fps.selectedSegmentIndex]; updateAction() }
    @objc private func resChanged() { model.quality = [.enhanced,.twoK,.fourK][resolution.selectedSegmentIndex]; updateAction() }
    @objc private func motionChanged() { model.mode = motion.selectedSegmentIndex == 1 ? .smooth : .simple }
    @objc private func aiChanged() { model.upscaleEngine = aiSwitch.isOn ? .ai : .standard }

    private func updateAction() {
        guard model.input != nil else { actionButton.configuration?.title = "Choose a Video"; return }
        actionButton.configuration?.title = "Enhance · \(model.targetFPS) FPS · \(["Native","2K","4K"][resolution.selectedSegmentIndex])"
    }

    @objc private func openPhotos() {
        var c = PHPickerConfiguration(photoLibrary: .shared()); c.filter = .videos; c.selectionLimit = 1
        let p = PHPickerViewController(configuration: c); p.delegate = self; present(p, animated: true)
    }

    @objc private func openFiles() {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .video], asCopy: true); p.delegate = self; present(p, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        provider.loadFileRepresentation(forTypeIdentifier: provider.registeredTypeIdentifiers.first ?? UTType.movie.identifier) { [weak self] url, _ in
            guard let self, let url else { return }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("sf_\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)")
            try? FileManager.default.removeItem(at: copy)
            do { try FileManager.default.copyItem(at: url, to: copy); Task { @MainActor in await self.load(copy) } }
            catch { Task { @MainActor in self.showError("Could not import this video.") } }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }; Task { await load(url) }
    }

    private func load(_ url: URL) async {
        await model.setInput(url: url)
        guard let info = model.input else { showError(model.errorText ?? "Could not read this video."); return }
        placeholder.isHidden = true
        player = AVPlayer(url: info.url); playerVC.player = player
        addChild(playerVC); let v = playerVC.view!; v.translatesAutoresizingMaskIntoConstraints = false; preview.addSubview(v)
        NSLayoutConstraint.activate([v.topAnchor.constraint(equalTo: preview.topAnchor), v.leadingAnchor.constraint(equalTo: preview.leadingAnchor), v.trailingAnchor.constraint(equalTo: preview.trailingAnchor), v.bottomAnchor.constraint(equalTo: preview.bottomAnchor)])
        playerVC.didMove(toParent: self); updateAction()
    }

    @objc private func convertTapped() {
        guard model.input != nil else { openPhotos(); return }
        overlay.isHidden = false
        timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }; let p = max(0, min(1, self.model.progress)); self.percent.text = "\(Int(p*100))%"; self.progress.progress = Float(p); self.stage.text = self.model.stageText
        }
        Task { await model.convert(library: library); timer?.invalidate(); timer = nil; overlay.isHidden = true; if let e = model.errorText { showError(e) } else { SFNativeBridge.impactSuccess() } }
    }

    @objc private func openLibrary() {
        let vc = LibraryViewController(store: library); let nav = UINavigationController(rootViewController: vc); nav.modalPresentationStyle = .fullScreen; present(nav, animated: true)
    }

    private func showError(_ text: String) {
        let a = UIAlertController(title: "ScreenFlow", message: text, preferredStyle: .alert); a.addAction(UIAlertAction(title: "OK", style: .default)); present(a, animated: true)
    }
}

@MainActor
final class LibraryViewController: UITableViewController {
    private let store: LibraryStore
    init(store: LibraryStore) { self.store = store; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() { super.viewDidLoad(); title = "Library"; view.backgroundColor = .black; tableView.backgroundColor = .black; navigationController?.navigationBar.barStyle = .black; navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done)) }
    @objc private func done() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { store.items.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil); let i = store.items[indexPath.row]; c.backgroundColor = UIColor(white: 0.055, alpha: 1); c.textLabel?.textColor = .white; c.detailTextLabel?.textColor = .gray; c.textLabel?.text = i.title; c.detailTextLabel?.text = "\(i.durationText) · \(i.sizeText)"; return c }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { let p = AVPlayerViewController(); p.player = AVPlayer(url: store.url(for: store.items[indexPath.row])); present(p, animated: true) { p.player?.play() } }
}
