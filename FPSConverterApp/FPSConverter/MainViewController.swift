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
    private let previewContainer = UIView()
    private let previewPlaceholder = UIView()
    private let previewIcon = UIImageView(image: UIImage(systemName: "video.badge.plus"))
    private let previewTitle = UILabel()
    private let previewMeta = UILabel()
    private let playerViewController = AVPlayerViewController()

    private let fpsControl = UISegmentedControl(items: ["24", "30", "60", "120"])
    private let qualityControl = UISegmentedControl(items: ["Native", "2K", "4K"])
    private let motionControl = UISegmentedControl(items: ["Fast", "Smooth"])
    private let aiSwitch = UISwitch()
    private let enhanceButton = UIButton(type: .system)
    private let progressOverlay = UIView()
    private let progressRing = UIProgressView(progressViewStyle: .bar)
    private let progressLabel = UILabel()
    private let progressPercent = UILabel()
    private var progressTimer: Timer?

    private var currentPlayer: AVPlayer?

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersHomeIndicatorAutoHidden: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupLayout()
        syncControlsFromModel()
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .always
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -18),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -128)
        ])

        contentStack.addArrangedSubview(makeHeader())
        contentStack.addArrangedSubview(makePreview())
        contentStack.addArrangedSubview(makeQuickImportRow())
        contentStack.addArrangedSubview(makeControlCard(title: "Frame Rate", subtitle: "Create smoother motion", control: fpsControl))
        contentStack.addArrangedSubview(makeControlCard(title: "Resolution", subtitle: "Native detail, 2K, or 4K", control: qualityControl))
        contentStack.addArrangedSubview(makeAISection())
        contentStack.addArrangedSubview(makeControlCard(title: "Motion Engine", subtitle: "Smooth synthesizes in-between frames", control: motionControl))
        contentStack.addArrangedSubview(makeLibraryCard())

        fpsControl.addTarget(self, action: #selector(fpsChanged), for: .valueChanged)
        qualityControl.addTarget(self, action: #selector(qualityChanged), for: .valueChanged)
        motionControl.addTarget(self, action: #selector(motionChanged), for: .valueChanged)
        aiSwitch.addTarget(self, action: #selector(aiChanged), for: .valueChanged)

        setupBottomAction()
        setupProgressOverlay()
    }

    private func makeHeader() -> UIView {
        let wrap = UIView()
        let title = UILabel()
        title.text = "ScreenFlow"
        title.textColor = .white
        title.font = .systemFont(ofSize: 34, weight: .bold)

        let sub = UILabel()
        sub.text = "FPS + AI Super Resolution"
        sub.textColor = UIColor.white.withAlphaComponent(0.48)
        sub.font = .systemFont(ofSize: 15, weight: .medium)

        let badge = UILabel()
        badge.text = "NATIVE"
        badge.textColor = .white
        badge.font = .systemFont(ofSize: 11, weight: .heavy)
        badge.textAlignment = .center
        badge.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        badge.layer.cornerRadius = 15
        badge.clipsToBounds = true

        [title, sub, badge].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; wrap.addSubview($0) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: wrap.topAnchor),
            title.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            badge.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            badge.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            badge.widthAnchor.constraint(equalToConstant: 76),
            badge.heightAnchor.constraint(equalToConstant: 30),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            sub.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            sub.bottomAnchor.constraint(equalTo: wrap.bottomAnchor)
        ])
        return wrap
    }

    private func makePreview() -> UIView {
        previewContainer.backgroundColor = UIColor(white: 0.055, alpha: 1)
        previewContainer.layer.cornerRadius = 24
        previewContainer.layer.cornerCurve = .continuous
        previewContainer.clipsToBounds = true
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.heightAnchor.constraint(equalToConstant: SFNativeBridge.isModernLargeIPhone() ? 360 : 320).isActive = true

        previewPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(previewPlaceholder)
        NSLayoutConstraint.activate([
            previewPlaceholder.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewPlaceholder.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewPlaceholder.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewPlaceholder.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor)
        ])

        previewIcon.tintColor = .white
        previewIcon.contentMode = .scaleAspectFit
        previewIcon.translatesAutoresizingMaskIntoConstraints = false
        previewTitle.text = "Add a video"
        previewTitle.font = .systemFont(ofSize: 26, weight: .bold)
        previewTitle.textColor = .white
        previewTitle.textAlignment = .center
        previewTitle.translatesAutoresizingMaskIntoConstraints = false
        previewMeta.text = "Photos or Files"
        previewMeta.font = .systemFont(ofSize: 15, weight: .medium)
        previewMeta.textColor = UIColor.white.withAlphaComponent(0.45)
        previewMeta.textAlignment = .center
        previewMeta.translatesAutoresizingMaskIntoConstraints = false

        previewPlaceholder.addSubview(previewIcon)
        previewPlaceholder.addSubview(previewTitle)
        previewPlaceholder.addSubview(previewMeta)
        NSLayoutConstraint.activate([
            previewIcon.centerXAnchor.constraint(equalTo: previewPlaceholder.centerXAnchor),
            previewIcon.centerYAnchor.constraint(equalTo: previewPlaceholder.centerYAnchor, constant: -42),
            previewIcon.widthAnchor.constraint(equalToConstant: 56),
            previewIcon.heightAnchor.constraint(equalToConstant: 56),
            previewTitle.topAnchor.constraint(equalTo: previewIcon.bottomAnchor, constant: 18),
            previewTitle.leadingAnchor.constraint(equalTo: previewPlaceholder.leadingAnchor, constant: 20),
            previewTitle.trailingAnchor.constraint(equalTo: previewPlaceholder.trailingAnchor, constant: -20),
            previewMeta.topAnchor.constraint(equalTo: previewTitle.bottomAnchor, constant: 7),
            previewMeta.leadingAnchor.constraint(equalTo: previewPlaceholder.leadingAnchor, constant: 20),
            previewMeta.trailingAnchor.constraint(equalTo: previewPlaceholder.trailingAnchor, constant: -20)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(openPhotos))
        previewPlaceholder.addGestureRecognizer(tap)
        return previewContainer
    }

    private func makeQuickImportRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually

        let photos = actionButton(title: "Photos", icon: "photo.on.rectangle.angled", primary: true)
        photos.addTarget(self, action: #selector(openPhotos), for: .touchUpInside)
        let files = actionButton(title: "Files", icon: "folder", primary: false)
        files.addTarget(self, action: #selector(openFiles), for: .touchUpInside)
        row.addArrangedSubview(photos)
        row.addArrangedSubview(files)
        row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        return row
    }

    private func makeControlCard(title: String, subtitle: String, control: UISegmentedControl) -> UIView {
        let card = cardView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let t = UILabel()
        t.text = title
        t.textColor = .white
        t.font = .systemFont(ofSize: 20, weight: .bold)
        let s = UILabel()
        s.text = subtitle
        s.textColor = UIColor.white.withAlphaComponent(0.42)
        s.font = .systemFont(ofSize: 13, weight: .medium)
        control.selectedSegmentTintColor = .white
        control.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 15, weight: .bold)], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.58), .font: UIFont.systemFont(ofSize: 15, weight: .semibold)], for: .normal)
        control.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        control.heightAnchor.constraint(equalToConstant: 48).isActive = true

        stack.addArrangedSubview(t)
        stack.addArrangedSubview(s)
        stack.addArrangedSubview(control)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
        return card
    }

    private func makeAISection() -> UIView {
        let card = cardView()
        let icon = UIImageView(image: UIImage(systemName: "brain.head.profile"))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = UILabel()
        title.text = "AI Super Resolution"
        title.textColor = .white
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        let sub = UILabel()
        sub.text = "Core ML detail recovery before final upscale"
        sub.textColor = UIColor.white.withAlphaComponent(0.42)
        sub.font = .systemFont(ofSize: 13, weight: .medium)
        sub.numberOfLines = 2
        sub.translatesAutoresizingMaskIntoConstraints = false
        aiSwitch.onTintColor = .white
        aiSwitch.thumbTintColor = .black
        aiSwitch.translatesAutoresizingMaskIntoConstraints = false

        [icon, title, sub, aiSwitch].forEach(card.addSubview)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 34),
            icon.heightAnchor.constraint(equalToConstant: 34),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            title.trailingAnchor.constraint(lessThanOrEqualTo: aiSwitch.leadingAnchor, constant: -12),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            sub.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            sub.trailingAnchor.constraint(equalTo: aiSwitch.leadingAnchor, constant: -12),
            sub.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            aiSwitch.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            aiSwitch.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
        return card
    }

    private func makeLibraryCard() -> UIView {
        let button = actionButton(title: "Open ScreenFlow Library", icon: "square.stack.3d.up.fill", primary: false)
        button.addTarget(self, action: #selector(openLibrary), for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 58).isActive = true
        return button
    }

    private func setupBottomAction() {
        enhanceButton.translatesAutoresizingMaskIntoConstraints = false
        enhanceButton.configuration = .filled()
        enhanceButton.configuration?.baseBackgroundColor = .white
        enhanceButton.configuration?.baseForegroundColor = .black
        enhanceButton.configuration?.cornerStyle = .large
        enhanceButton.configuration?.image = UIImage(systemName: "wand.and.stars")
        enhanceButton.configuration?.imagePadding = 10
        enhanceButton.configuration?.title = "Enhance Video"
        enhanceButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        enhanceButton.addTarget(self, action: #selector(convertTapped), for: .touchUpInside)
        view.addSubview(enhanceButton)
        NSLayoutConstraint.activate([
            enhanceButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            enhanceButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            enhanceButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            enhanceButton.heightAnchor.constraint(equalToConstant: 62)
        ])
        updateConvertButton()
    }

    private func setupProgressOverlay() {
        progressOverlay.translatesAutoresizingMaskIntoConstraints = false
        progressOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        progressOverlay.alpha = 0
        progressOverlay.isHidden = true
        view.addSubview(progressOverlay)
        NSLayoutConstraint.activate([
            progressOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            progressOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        progressPercent.textColor = .white
        progressPercent.font = .systemFont(ofSize: 56, weight: .bold)
        progressPercent.textAlignment = .center
        progressPercent.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        progressLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        progressLabel.textAlignment = .center
        progressLabel.numberOfLines = 2
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressRing.progressTintColor = .white
        progressRing.trackTintColor = UIColor.white.withAlphaComponent(0.12)
        progressRing.translatesAutoresizingMaskIntoConstraints = false

        [progressPercent, progressLabel, progressRing].forEach(progressOverlay.addSubview)
        NSLayoutConstraint.activate([
            progressPercent.centerXAnchor.constraint(equalTo: progressOverlay.centerXAnchor),
            progressPercent.centerYAnchor.constraint(equalTo: progressOverlay.centerYAnchor, constant: -34),
            progressLabel.topAnchor.constraint(equalTo: progressPercent.bottomAnchor, constant: 14),
            progressLabel.leadingAnchor.constraint(equalTo: progressOverlay.leadingAnchor, constant: 34),
            progressLabel.trailingAnchor.constraint(equalTo: progressOverlay.trailingAnchor, constant: -34),
            progressRing.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 28),
            progressRing.leadingAnchor.constraint(equalTo: progressOverlay.leadingAnchor, constant: 54),
            progressRing.trailingAnchor.constraint(equalTo: progressOverlay.trailingAnchor, constant: -54)
        ])
    }

    private func cardView() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.055, alpha: 1)
        v.layer.cornerRadius = 22
        v.layer.cornerCurve = .continuous
        v.layer.borderColor = UIColor.white.withAlphaComponent(0.06).cgColor
        v.layer.borderWidth = 1
        return v
    }

    private func actionButton(title: String, icon: String, primary: Bool) -> UIButton {
        let b = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: icon)
        config.imagePadding = 9
        config.baseBackgroundColor = primary ? .white : UIColor.white.withAlphaComponent(0.07)
        config.baseForegroundColor = primary ? .black : .white
        config.cornerStyle = .large
        b.configuration = config
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        return b
    }

    private func syncControlsFromModel() {
        fpsControl.selectedSegmentIndex = 2
        qualityControl.selectedSegmentIndex = 2
        motionControl.selectedSegmentIndex = 1
        aiSwitch.isOn = true
        model.targetFPS = 60
        model.quality = .fourK
        model.mode = .smooth
        model.upscaleEngine = .ai
    }

    @objc private func fpsChanged() {
        model.targetFPS = [24, 30, 60, 120][fpsControl.selectedSegmentIndex]
        SFNativeBridge.impactSelection()
        updateConvertButton()
    }

    @objc private func qualityChanged() {
        model.quality = [.enhanced, .twoK, .fourK][qualityControl.selectedSegmentIndex]
        SFNativeBridge.impactSelection()
        updateConvertButton()
    }

    @objc private func motionChanged() {
        model.mode = motionControl.selectedSegmentIndex == 1 ? .smooth : .simple
        SFNativeBridge.impactSelection()
    }

    @objc private func aiChanged() {
        model.upscaleEngine = aiSwitch.isOn ? .ai : .standard
        SFNativeBridge.impactSelection()
    }

    private func updateConvertButton() {
        let quality = qualityControl.selectedSegmentIndex == 0 ? "Native" : (qualityControl.selectedSegmentIndex == 1 ? "2K" : "4K")
        enhanceButton.configuration?.title = model.input == nil ? "Choose a Video" : "Enhance · \(model.targetFPS) FPS · \(quality)"
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
        provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, error in
            guard let self, let url else { return }
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("screenflow_input_\(UUID().uuidString).\(ext)")
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
        currentPlayer = AVPlayer(url: info.url)
        playerViewController.player = currentPlayer
        addChild(playerViewController)
        let pv = playerViewController.view!
        pv.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(pv)
        NSLayoutConstraint.activate([
            pv.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            pv.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            pv.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            pv.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor)
        ])
        playerViewController.didMove(toParent: self)
        updateConvertButton()
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
                showCompletion(out)
            }
        }
    }

    private func showProgress() {
        progressOverlay.isHidden = false
        UIView.animate(withDuration: 0.2) { self.progressOverlay.alpha = 1 }
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let p = Float(max(0, min(1, self.model.progress)))
            self.progressRing.setProgress(p, animated: true)
            self.progressPercent.text = "\(Int(p * 100))%"
            self.progressLabel.text = self.model.stageText.isEmpty ? "Processing on-device" : self.model.stageText
        }
    }

    private func hideProgress() {
        progressTimer?.invalidate()
        progressTimer = nil
        UIView.animate(withDuration: 0.2, animations: { self.progressOverlay.alpha = 0 }) { _ in
            self.progressOverlay.isHidden = true
        }
    }

    private func showCompletion(_ info: VideoModel.Info) {
        let alert = UIAlertController(title: "Saved to Library", message: "\(info.resolutionText) · \(info.fpsText) · \(info.sizeText)", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Save to Photos", style: .default) { _ in self.model.saveToPhotos() })
        alert.addAction(UIAlertAction(title: "Open Library", style: .default) { _ in self.openLibrary() })
        alert.addAction(UIAlertAction(title: "Done", style: .cancel))
        if let pop = alert.popoverPresentationController { pop.sourceView = enhanceButton; pop.sourceRect = enhanceButton.bounds }
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
