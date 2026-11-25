import UIKit

/// Nhập playlist từ link Spotify / Apple Music / Deezer / SoundCloud / YouTube Music, ghép bài trên YouTube Music.
final class ImportViewController: UIViewController {
    private let field = UITextField()
    private let button = UIButton(type: .system)
    private let status = UILabel()
    private let bar = UIProgressView(progressViewStyle: .default)
    private let missedView = UITextView()
    private var busy = false
    private let localStatus = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("Nhập nhạc & playlist")
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never

        let intro = UILabel()
        intro.numberOfLines = 0
        intro.font = Theme.regular(14)
        intro.textColor = Theme.secondaryText
        intro.text = L("Dán link playlist/album/bài hát từ Spotify, Apple Music, Deezer, SoundCloud hoặc YouTube Music. Playlist phải ở chế độ công khai. Mochy sẽ ghép từng bài sang YouTube Music. Nhập lại cùng một link sẽ chỉ thêm các bài mới (đồng bộ).")

        field.placeholder = "https://open.spotify.com/playlist/…"
        field.font = Theme.regular(16)
        field.textColor = Theme.primaryText
        field.backgroundColor = Theme.card
        field.layer.cornerRadius = 12
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = .URL
        field.clearButtonMode = .whileEditing
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 10))
        field.leftViewMode = .always
        field.heightAnchor.constraint(equalToConstant: 48).isActive = true

        button.setTitle(L("Dán từ clipboard"), for: .normal)
        button.titleLabel?.font = Theme.bold(15)
        button.tintColor = Theme.accent
        button.addTarget(self, action: #selector(pasteLink), for: .touchUpInside)

        let go = UIButton(type: .system)
        go.setTitle(L("Nhập"), for: .normal)
        go.titleLabel?.font = Theme.bold(17)
        go.setTitleColor(.white, for: .normal)
        go.backgroundColor = Theme.accent
        go.layer.cornerRadius = 12
        go.heightAnchor.constraint(equalToConstant: 48).isActive = true
        go.addTarget(self, action: #selector(start), for: .touchUpInside)

        status.numberOfLines = 0
        status.font = Theme.regular(15)
        status.textColor = Theme.primaryText
        bar.progressTintColor = Theme.accent
        bar.isHidden = true

        missedView.isEditable = false
        missedView.backgroundColor = Theme.card
        missedView.textColor = Theme.secondaryText
        missedView.font = Theme.regular(13)
        missedView.layer.cornerRadius = 12
        missedView.isHidden = true

        // --- Nhập nhạc từ máy ---
        let localTitle = UILabel()
        localTitle.font = Theme.heavy(20)
        localTitle.textColor = Theme.primaryText
        localTitle.text = L("Nhạc từ máy")
        let localIntro = UILabel()
        localIntro.numberOfLines = 0
        localIntro.font = Theme.regular(14)
        localIntro.textColor = Theme.secondaryText
        localIntro.text = L("Chọn tệp MP3, M4A, WAV hoặc FLAC trong máy. Mochy sao chép tệp vào thư mục Documents/LocalMusic của app, đọc tên bài, nghệ sĩ, ảnh bìa rồi thêm vào mục \"Nhạc trong máy\" trong Thư viện.")
        let pick = UIButton(type: .system)
        pick.setTitle(L("Chọn tệp nhạc…"), for: .normal)
        pick.titleLabel?.font = Theme.bold(17)
        pick.setTitleColor(.white, for: .normal)
        pick.backgroundColor = Theme.accent
        pick.layer.cornerRadius = 12
        pick.heightAnchor.constraint(equalToConstant: 48).isActive = true
        pick.addTarget(self, action: #selector(pickLocalFiles), for: .touchUpInside)
        let scan = UIButton(type: .system)
        scan.setTitle(L("Quét thư mục LocalMusic"), for: .normal)
        scan.titleLabel?.font = Theme.bold(15)
        scan.tintColor = Theme.accent
        scan.addTarget(self, action: #selector(scanLocalFolder), for: .touchUpInside)
        localStatus.numberOfLines = 0
        localStatus.font = Theme.regular(15)
        localStatus.textColor = Theme.primaryText
        let playlistTitle = UILabel()
        playlistTitle.font = Theme.heavy(20)
        playlistTitle.textColor = Theme.primaryText
        playlistTitle.text = L("Playlist từ link")

        let stack = UIStackView(arrangedSubviews: [localTitle, localIntro, pick, scan, localStatus, playlistTitle, intro, field, button, go, bar, status, missedView])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)
        scroll.addSubview(stack)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: g.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -120),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
            missedView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        view.addGestureRecognizer(UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:))))
    }

    @objc private func pickLocalFiles() {
        LocalMusicImporter.present(from: self, onProgress: { [weak self] done, total in
            self?.localStatus.text = LF("Đang nhập %@/%@…", "\(min(done + 1, total))", "\(total)")
        }, onFinish: { [weak self] summary in
            self?.localStatus.text = LocalMusicImporter.message(for: summary)
        })
    }

    @objc private func scanLocalFolder() {
        localStatus.text = L("Đang quét thư mục…")
        LocalMusicStore.scanFolder(progress: { [weak self] done, total in
            self?.localStatus.text = LF("Đang nhập %@/%@…", "\(min(done + 1, total))", "\(total)")
        }, completion: { [weak self] summary in
            self?.localStatus.text = (summary.added.isEmpty && summary.failures.isEmpty && summary.duplicates == 0)
                ? L("Không có tệp mới trong thư mục LocalMusic.") : LocalMusicImporter.message(for: summary)
        })
    }

    @objc private func pasteLink() {
        if let text = UIPasteboard.general.string { field.text = text }
    }

    @objc private func start() {
        if busy { return }
        view.endEditing(true)
        guard let url = PlaylistImporter.extractURL(field.text ?? "") else {
            status.text = L("Không thấy link hợp lệ.")
            return
        }
        busy = true
        missedView.isHidden = true
        bar.isHidden = false
        bar.progress = 0
        status.text = L("Đang đọc playlist…")
        PlaylistImporter.shared.fetch(url) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.finish(LF("Lỗi: %@", "\(error.message)"))
            case .success(let collection):
                self.run(collection, link: url.absoluteString)
            }
        }
    }

    private func run(_ collection: ImportedCollection, link: String) {
        if !collection.directSongs.isEmpty && collection.tracks.isEmpty {
            save(collection, songs: collection.directSongs, missed: [], link: link)
            return
        }
        status.text = LF("Đang ghép %@ bài…", "\(collection.tracks.count)")
        PlaylistImporter.shared.match(collection, progress: { [weak self] done, total in
            DispatchQueue.main.async {
                self?.bar.progress = total > 0 ? Float(done) / Float(total) : 0
                self?.status.text = LF("Đang ghép bài %@/%@…", "\(done)", "\(total)")
            }
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                self?.save(collection, songs: result.songs, missed: result.missed, link: link)
            }
        })
    }

    private func save(_ collection: ImportedCollection, songs: [Song], missed: [ImportedTrack], link: String) {
        if songs.isEmpty {
            finish(L("Không ghép được bài nào."))
            return
        }
        let result = Library.shared.importPlaylist(name: collection.name, songs: songs, sourceURL: link)
        var text = LF("Xong: playlist “%@” – thêm %@ bài (từ %@).", "\(result.playlist.name)", "\(result.added)", "\(collection.source)")
        if collection.truncated { text += L("\nLưu ý: nguồn này chỉ cho lấy tối đa khoảng 100 bài đầu.") }
        if !missed.isEmpty {
            text += LF("\nKhông ghép được %@ bài.", "\(missed.count)")
            missedView.text = missed.map { "• \($0.title) – \($0.artist)" }.joined(separator: "\n")
            missedView.isHidden = false
        }
        finish(text)
    }

    private func finish(_ text: String) {
        busy = false
        bar.isHidden = true
        status.text = text
    }
}
