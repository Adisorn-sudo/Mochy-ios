import UIKit

/// Một dòng trong bảng đóng dấu: cột mốc thời gian + nội dung.
private final class SyncLineCell: UITableViewCell {
    static let reuseId = "SyncLineCell"
    let stampLabel = UILabel()
    let lineLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        selectionStyle = .none
        stampLabel.translatesAutoresizingMaskIntoConstraints = false
        stampLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        stampLabel.textAlignment = .left
        lineLabel.translatesAutoresizingMaskIntoConstraints = false
        lineLabel.numberOfLines = 0
        lineLabel.font = Theme.regular(17)
        contentView.addSubview(stampLabel)
        contentView.addSubview(lineLabel)
        NSLayoutConstraint.activate([
            stampLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stampLabel.widthAnchor.constraint(equalToConstant: 84),
            stampLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            lineLabel.leadingAnchor.constraint(equalTo: stampLabel.trailingAnchor, constant: 8),
            lineLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            lineLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            lineLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9)
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) chưa được hỗ trợ")
    }

    func configure(time: Double?, text: String, isNext: Bool, isPlayingNow: Bool) {
        if let time = time {
            let centis = Int((time * 100).rounded(.down))
            stampLabel.text = String(format: "%02d:%02d.%02d", centis / 6000, (centis / 100) % 60, centis % 100)
            stampLabel.textColor = Theme.accent
        } else {
            stampLabel.text = "--:--.--"
            stampLabel.textColor = Theme.secondaryText
        }
        lineLabel.text = text.isEmpty ? "♪" : text
        lineLabel.textColor = time == nil ? Theme.secondaryText : Theme.primaryText
        lineLabel.font = isPlayingNow ? Theme.bold(17) : Theme.regular(17)
        // Dòng sắp được đóng dấu: nền nổi bật + vạch cam bên trái.
        contentView.backgroundColor = isNext ? Theme.chip : UIColor.clear
    }
}

/// Soạn lời bài hát của riêng bạn, lưu thành Documents/CustomLyrics/<videoId>.lrc. Hai chế độ:
///  1) Văn bản: gõ / dán lời thường (hoặc dán nguyên nội dung .lrc).
///  2) Đồng bộ thời gian (LRC Sync Maker): vừa nghe nhạc vừa bấm "Stamp Time" để gắn [mm:ss.xx] vào từng dòng
///     theo đúng vị trí phát thật của PlayerEngine.
final class CustomLyricsEditorViewController: UIViewController, UITextViewDelegate, UITableViewDataSource, UITableViewDelegate {
    private struct Line {
        var text: String
        var time: Double?
    }

    private enum EditorMode: Int {
        case text = 0
        case sync = 1
    }

    private let song: Song
    private let startInSync: Bool
    private var mode: EditorMode = .text
    private var lines: [Line] = []
    private var headerLines: [String] = []     // [ti:…] [ar:…] giữ nguyên khi qua lại giữa hai chế độ
    private var pointer = 0                    // dòng sẽ được đóng dấu tiếp theo
    private var dirty = false
    private var clock: Timer?
    private var offset: Double = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "lyrics.stampOffset") == nil { return 0.15 }
        return min(max(defaults.double(forKey: "lyrics.stampOffset"), 0), 0.6)
    }()

    // Giao diện
    private let modeControl = UISegmentedControl(items: [L("Văn bản"), L("Đồng bộ thời gian")])
    private let textView = UITextView()
    private let syncContainer = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let panel = UIView()
    private let timeLabel = UILabel()
    private let durationLabel = UILabel()
    private let slider = UISlider()
    private let backFiveButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let forwardFiveButton = UIButton(type: .system)
    private let stampButton = UIButton(type: .system)
    private let backLineButton = UIButton(type: .system)
    private let offsetLabel = UILabel()
    private let offsetStepper = UIStepper()
    private let notPlayingLabel = UILabel()
    private let playSongButton = UIButton(type: .system)
    private var textBottom: NSLayoutConstraint!
    private var sliderDragging = false

    init(song: Song, startInSyncMode: Bool = false) {
        self.song = song
        self.startInSync = startInSyncMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) chưa được hỗ trợ")
    }

    deinit {
        clock?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    /// Mở trình soạn lời cho một bài (từ màn hình đang phát hoặc menu bài hát).
    static func present(for song: Song, from vc: UIViewController, startInSyncMode: Bool = false) {
        let editor = CustomLyricsEditorViewController(song: song, startInSyncMode: startInSyncMode)
        let nav = UINavigationController(rootViewController: editor)
        Theme.style(navigationBar: nav.navigationBar)
        nav.modalPresentationStyle = .fullScreen
        vc.present(nav, animated: true, completion: nil)
    }

    // MARK: - Vòng đời

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.statusBarStyle
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("Lời bài hát tự tạo")
        view.backgroundColor = Theme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: L("Huỷ"), style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: L("Lưu"), style: .done, target: self, action: #selector(saveTapped)),
            UIBarButtonItem(title: L("Thêm…"), style: .plain, target: self, action: #selector(moreTapped))
        ]
        buildLayout()

        if let existing = CustomLyricsStore.load(videoId: song.videoId) {
            textView.text = existing
        }
        modeControl.selectedSegmentIndex = 0
        if startInSync && !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            modeControl.selectedSegmentIndex = 1
            modeChanged()
        }
        applyMode()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(playerChanged), name: .playerStateChanged, object: nil)
        center.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        clock?.invalidate()
        clock = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(refreshClock), userInfo: nil, repeats: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            clock?.invalidate()
            clock = nil
        }
    }

    // MARK: - Dựng giao diện

    private func styleButton(_ button: UIButton, title: String, filled: Bool = false) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = Theme.bold(15)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.tintColor = Theme.accent
        button.translatesAutoresizingMaskIntoConstraints = false
        if filled {
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = Theme.accent
        } else {
            button.setTitleColor(Theme.accent, for: .normal)
            button.backgroundColor = Theme.chip
        }
        button.layer.cornerRadius = 12
    }

    private func buildLayout() {
        let guide = view.safeAreaLayoutGuide

        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.tintColor = Theme.accent
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        view.addSubview(modeControl)

        // Chế độ văn bản
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = Theme.card
        textView.textColor = Theme.primaryText
        textView.font = Theme.regular(17)
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.keyboardAppearance = Theme.isDark ? .dark : .light
        textView.tintColor = Theme.accent
        textView.delegate = self
        view.addSubview(textView)

        // Chế độ đồng bộ
        syncContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(syncContainer)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.separator
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SyncLineCell.self, forCellReuseIdentifier: SyncLineCell.reuseId)
        tableView.estimatedRowHeight = 44
        tableView.rowHeight = UITableView.automaticDimension
        tableView.tableFooterView = UIView()
        syncContainer.addSubview(tableView)

        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = Theme.card
        panel.layer.cornerRadius = 16
        syncContainer.addSubview(panel)

        for label in [timeLabel, durationLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
            label.textColor = Theme.secondaryText
            panel.addSubview(label)
        }
        durationLabel.textAlignment = .right
        timeLabel.text = "0:00.00"
        durationLabel.text = "0:00"

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumTrackTintColor = Theme.accent
        slider.addTarget(self, action: #selector(sliderBegan), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        panel.addSubview(slider)

        styleButton(backFiveButton, title: "−5 " + L("giây"))
        styleButton(forwardFiveButton, title: "+5 " + L("giây"))
        styleButton(playButton, title: "")
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        backFiveButton.addTarget(self, action: #selector(backFiveTapped), for: .touchUpInside)
        forwardFiveButton.addTarget(self, action: #selector(forwardFiveTapped), for: .touchUpInside)

        styleButton(stampButton, title: L("Stamp Time"), filled: true)
        stampButton.titleLabel?.font = Theme.heavy(19)
        stampButton.layer.cornerRadius = 14
        stampButton.addTarget(self, action: #selector(stampTapped), for: .touchUpInside)

        styleButton(backLineButton, title: L("Lùi một dòng"))
        backLineButton.addTarget(self, action: #selector(backLineTapped), for: .touchUpInside)

        offsetLabel.translatesAutoresizingMaskIntoConstraints = false
        offsetLabel.font = Theme.regular(13)
        offsetLabel.textColor = Theme.secondaryText
        offsetLabel.numberOfLines = 2
        offsetStepper.translatesAutoresizingMaskIntoConstraints = false
        offsetStepper.minimumValue = 0
        offsetStepper.maximumValue = 0.6
        offsetStepper.stepValue = 0.05
        offsetStepper.value = offset
        offsetStepper.tintColor = Theme.accent
        offsetStepper.addTarget(self, action: #selector(offsetChanged), for: .valueChanged)
        updateOffsetLabel()

        notPlayingLabel.translatesAutoresizingMaskIntoConstraints = false
        notPlayingLabel.font = Theme.regular(13)
        notPlayingLabel.textColor = Theme.secondaryText
        notPlayingLabel.numberOfLines = 0
        notPlayingLabel.text = L("Bài này chưa được phát. Hãy phát bài để đóng dấu thời gian theo đúng vị trí đang nghe.")
        styleButton(playSongButton, title: L("Phát bài này"))
        playSongButton.addTarget(self, action: #selector(playSongTapped), for: .touchUpInside)

        [backFiveButton, playButton, forwardFiveButton, stampButton, backLineButton, offsetLabel, offsetStepper,
         notPlayingLabel, playSongButton].forEach { panel.addSubview($0) }

        textBottom = textView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12)
        NSLayoutConstraint.activate([
            modeControl.topAnchor.constraint(equalTo: guide.topAnchor, constant: 10),
            modeControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            modeControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            modeControl.heightAnchor.constraint(equalToConstant: 32),

            textView.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 10),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            textBottom,

            syncContainer.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 6),
            syncContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            syncContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            syncContainer.bottomAnchor.constraint(equalTo: guide.bottomAnchor),

            tableView.topAnchor.constraint(equalTo: syncContainer.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: syncContainer.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: syncContainer.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: panel.topAnchor, constant: -8),

            panel.leadingAnchor.constraint(equalTo: syncContainer.leadingAnchor, constant: 10),
            panel.trailingAnchor.constraint(equalTo: syncContainer.trailingAnchor, constant: -10),
            panel.bottomAnchor.constraint(equalTo: syncContainer.bottomAnchor, constant: -8),

            timeLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            timeLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            durationLabel.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
            durationLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            slider.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 4),
            slider.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),

            playButton.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 8),
            playButton.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 64),
            playButton.heightAnchor.constraint(equalToConstant: 44),
            backFiveButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            backFiveButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -12),
            backFiveButton.widthAnchor.constraint(equalToConstant: 92),
            backFiveButton.heightAnchor.constraint(equalToConstant: 44),
            forwardFiveButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            forwardFiveButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 12),
            forwardFiveButton.widthAnchor.constraint(equalToConstant: 92),
            forwardFiveButton.heightAnchor.constraint(equalToConstant: 44),

            notPlayingLabel.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 8),
            notPlayingLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            notPlayingLabel.trailingAnchor.constraint(equalTo: playSongButton.leadingAnchor, constant: -10),
            playSongButton.centerYAnchor.constraint(equalTo: notPlayingLabel.centerYAnchor),
            playSongButton.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            playSongButton.widthAnchor.constraint(equalToConstant: 110),
            playSongButton.heightAnchor.constraint(equalToConstant: 40),

            stampButton.topAnchor.constraint(equalTo: notPlayingLabel.bottomAnchor, constant: 10),
            stampButton.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            stampButton.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            stampButton.heightAnchor.constraint(equalToConstant: 58),

            backLineButton.topAnchor.constraint(equalTo: stampButton.bottomAnchor, constant: 10),
            backLineButton.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            backLineButton.widthAnchor.constraint(equalToConstant: 118),
            backLineButton.heightAnchor.constraint(equalToConstant: 40),
            backLineButton.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12),
            offsetStepper.centerYAnchor.constraint(equalTo: backLineButton.centerYAnchor),
            offsetStepper.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            offsetLabel.centerYAnchor.constraint(equalTo: backLineButton.centerYAnchor),
            offsetLabel.leadingAnchor.constraint(equalTo: backLineButton.trailingAnchor, constant: 10),
            offsetLabel.trailingAnchor.constraint(equalTo: offsetStepper.leadingAnchor, constant: -8)
        ])
    }

    // MARK: - Chế độ

    @objc private func modeChanged() {
        let target = EditorMode(rawValue: modeControl.selectedSegmentIndex) ?? .text
        if target == mode { return }
        if target == .sync {
            view.endEditing(true)
            let parsed = parse(textView.text ?? "")
            if parsed.lines.isEmpty {
                modeControl.selectedSegmentIndex = 0
                alert(L("Chưa có lời"), L("Hãy gõ hoặc dán lời bài hát ở chế độ Văn bản trước, mỗi dòng một câu."))
                return
            }
            lines = parsed.lines
            headerLines = parsed.headers
            pointer = lines.firstIndex(where: { $0.time == nil }) ?? lines.count
            mode = .sync
            tableView.reloadData()
            scrollToPointer(animated: false)
        } else {
            textView.text = compose()
            mode = .text
        }
        applyMode()
    }

    private func applyMode() {
        let sync = mode == .sync
        textView.isHidden = sync
        syncContainer.isHidden = !sync
        if !sync { textBottom.constant = -12 }
        refreshControls()
    }

    // MARK: - Chuyển đổi văn bản <-> dòng có mốc

    private static let stampRegex = try? NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]", options: [])
    private static let leadingStamps = try? NSRegularExpression(pattern: "^\\s*((?:\\[\\d{1,3}:\\d{1,2}(?:[.:]\\d{1,3})?\\]\\s*)+)(.*)$", options: [])

    private func parse(_ text: String) -> (lines: [Line], headers: [String]) {
        var out: [Line] = []
        var headers: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if CustomLyricsStore.isHeader(trimmed) { headers.append(trimmed); continue }
            let ns = trimmed as NSString
            let whole = NSRange(location: 0, length: ns.length)
            if let match = CustomLyricsEditorViewController.leadingStamps?.firstMatch(in: trimmed, options: [], range: whole) {
                let stamps = ns.substring(with: match.range(at: 1))
                var body = ns.substring(with: match.range(at: 2))
                body = body.replacingOccurrences(of: "<\\d{1,3}:\\d{1,2}(?:[.:]\\d{1,3})?>", with: "", options: .regularExpression)
                body = body.trimmingCharacters(in: .whitespaces)
                let times = CustomLyricsEditorViewController.times(in: stamps)
                if times.isEmpty {
                    out.append(Line(text: body, time: nil))
                } else {
                    for t in times { out.append(Line(text: body, time: t)) }   // nhiều mốc = lặp lại câu (điệp khúc)
                }
            } else {
                out.append(Line(text: trimmed, time: nil))
            }
        }
        // Lời toàn mốc thì xếp theo thời gian; lời lẫn lộn giữ thứ tự người dùng gõ.
        if !out.isEmpty && out.allSatisfy({ $0.time != nil }) {
            out.sort { ($0.time ?? 0) < ($1.time ?? 0) }
        }
        return (out, headers)
    }

    private static func times(in stamps: String) -> [Double] {
        guard let regex = stampRegex else { return [] }
        let ns = stamps as NSString
        return regex.matches(in: stamps, options: [], range: NSRange(location: 0, length: ns.length)).map { m in
            let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let seconds = Double(ns.substring(with: m.range(at: 2))) ?? 0
            var fraction = 0.0
            if m.range(at: 3).location != NSNotFound {
                let digits = ns.substring(with: m.range(at: 3))
                fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
            }
            return minutes * 60 + seconds + fraction
        }
    }

    private func compose() -> String {
        var out = headerLines
        for line in lines {
            if let t = line.time {
                out.append(CustomLyricsStore.stamp(t) + line.text)
            } else {
                out.append(line.text)
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Đồng hồ / điều khiển phát

    private var isCurrentSong: Bool {
        return PlayerEngine.shared.currentSong == song
    }

    @objc private func playerChanged() {
        refreshControls()
    }

    private func refreshControls() {
        let engine = PlayerEngine.shared
        let current = isCurrentSong
        let playing = current && engine.isPlaying
        playButton.setImage((playing ? Icons.pause(22) : Icons.play(22)).withRenderingMode(.alwaysTemplate), for: .normal)
        for control in [playButton, backFiveButton, forwardFiveButton, stampButton, backLineButton] {
            control.isEnabled = current
            control.alpha = current ? 1 : 0.4
        }
        slider.isEnabled = current
        notPlayingLabel.isHidden = current
        playSongButton.isHidden = current
        durationLabel.text = current && engine.duration > 0 ? formatTime(engine.duration) : formatTime(LyricsService.seconds(song.duration))
    }

    @objc private func refreshClock() {
        guard mode == .sync else { return }
        let engine = PlayerEngine.shared
        guard isCurrentSong else {
            timeLabel.text = "0:00.00"
            return
        }
        let position = engine.livePosition
        let centis = max(0, Int((position * 100).rounded(.down)))
        timeLabel.text = String(format: "%d:%02d.%02d", centis / 6000, (centis / 100) % 60, centis % 100)
        if !sliderDragging && engine.duration > 0 {
            slider.value = Float(min(1, max(0, position / engine.duration)))
        }
        // Làm đậm dòng đang được hát theo mốc đã đóng.
        let nowPlaying = lines.indices.last(where: { (lines[$0].time ?? .infinity) <= position })
        if nowPlaying != lastNowPlaying {
            lastNowPlaying = nowPlaying
            tableView.reloadData()
        }
    }

    private var lastNowPlaying: Int?

    @objc private func playTapped() {
        guard isCurrentSong else { return }
        Haptics.tap()
        PlayerEngine.shared.togglePlayPause()
    }

    @objc private func backFiveTapped() {
        guard isCurrentSong else { return }
        PlayerEngine.shared.seek(to: max(0, PlayerEngine.shared.livePosition - 5))
    }

    @objc private func forwardFiveTapped() {
        guard isCurrentSong else { return }
        PlayerEngine.shared.seek(to: PlayerEngine.shared.livePosition + 5)
    }

    @objc private func sliderBegan() {
        sliderDragging = true
    }

    @objc private func sliderEnded() {
        sliderDragging = false
        let engine = PlayerEngine.shared
        guard isCurrentSong, engine.duration > 0 else { return }
        engine.seek(to: Double(slider.value) * engine.duration)
    }

    @objc private func playSongTapped() {
        let engine = PlayerEngine.shared
        if let index = engine.queue.firstIndex(of: song) {
            engine.jump(to: index)
        } else {
            engine.playNext(song)
            if engine.currentSong != song { engine.next() }
        }
    }

    @objc private func offsetChanged() {
        offset = (offsetStepper.value * 100).rounded() / 100
        UserDefaults.standard.set(offset, forKey: "lyrics.stampOffset")
        updateOffsetLabel()
    }

    private func updateOffsetLabel() {
        offsetLabel.text = LF("Bù độ trễ tay bấm: %@ giây", String(format: "%.2f", offset))
    }

    // MARK: - Đóng dấu thời gian

    @objc private func stampTapped() {
        guard isCurrentSong else { return }
        guard pointer < lines.count else {
            Toast.show(L("Đã đóng dấu hết các dòng. Bấm Lưu để ghi lại."))
            return
        }
        // Người bấm luôn trễ một chút so với tai nghe thấy: trừ đi độ bù (mặc định 0,15 giây).
        let time = max(0, PlayerEngine.shared.livePosition - offset)
        lines[pointer].time = time
        dirty = true
        Haptics.tap()
        let done = pointer
        pointer += 1
        reload(rows: [done, pointer])
        scrollToPointer(animated: true)
        if pointer >= lines.count {
            Toast.show(L("Đã đóng dấu hết các dòng. Bấm Lưu để ghi lại."))
        }
    }

    @objc private func backLineTapped() {
        guard isCurrentSong, pointer > 0 else { return }
        let old = pointer
        pointer -= 1
        lines[pointer].time = nil
        dirty = true
        // Tua về đầu dòng trước đó để nghe lại rồi đóng dấu lại.
        let rewind = pointer > 0 ? (lines[pointer - 1].time ?? 0) : 0
        PlayerEngine.shared.seek(to: max(0, rewind))
        reload(rows: [pointer, old])
        scrollToPointer(animated: true)
    }

    private func reload(rows: [Int]) {
        let valid = rows.filter { $0 >= 0 && $0 < lines.count }
        guard !valid.isEmpty else { return }
        tableView.reloadRows(at: valid.map { IndexPath(row: $0, section: 0) }, with: .none)
    }

    private func scrollToPointer(animated: Bool) {
        guard !lines.isEmpty else { return }
        let row = min(pointer, lines.count - 1)
        tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: animated)
    }

    // MARK: - Bảng

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return lines.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SyncLineCell.reuseId, for: indexPath) as! SyncLineCell
        let line = lines[indexPath.row]
        cell.configure(time: line.time, text: line.text, isNext: indexPath.row == pointer, isPlayingNow: indexPath.row == lastNowPlaying)
        return cell
    }

    /// Chạm vào một dòng: đặt dòng đó làm dòng sắp đóng dấu (và nghe lại đoạn trước đó nếu đã có mốc).
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let old = pointer
        pointer = indexPath.row
        reload(rows: [old, pointer])
        if isCurrentSong, let time = lines[indexPath.row].time {
            PlayerEngine.shared.seek(to: max(0, time - 1.5))
        }
    }

    // MARK: - Hành động

    @objc private func cancelTapped() {
        guard dirty || hasUnsavedText else {
            finish()
            return
        }
        let sheet = UIAlertController(title: L("Bỏ các thay đổi chưa lưu?"), message: nil, preferredStyle: .alert)
        sheet.addAction(UIAlertAction(title: L("Tiếp tục soạn"), style: .cancel, handler: nil))
        sheet.addAction(UIAlertAction(title: L("Bỏ thay đổi"), style: .destructive) { [weak self] _ in self?.finish() })
        present(sheet, animated: true, completion: nil)
    }

    private var hasUnsavedText: Bool {
        let saved = CustomLyricsStore.load(videoId: song.videoId) ?? ""
        let current = mode == .sync ? compose() : (textView.text ?? "")
        return saved.trimmingCharacters(in: .whitespacesAndNewlines) != current.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finish() {
        view.endEditing(true)
        clock?.invalidate()
        clock = nil
        dismiss(animated: true, completion: nil)
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        let text = mode == .sync ? compose() : (textView.text ?? "")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if CustomLyricsStore.exists(videoId: song.videoId) {
                confirmDelete()
            } else {
                alert(L("Chưa có lời"), L("Hãy gõ hoặc dán lời bài hát trước khi lưu."))
            }
            return
        }
        if mode == .sync {
            let missing = lines.filter { $0.time == nil }.count
            let stamped = lines.count - missing
            if stamped > 0 && missing > 0 {
                let message = LF("Còn %@ dòng chưa có mốc thời gian. Các dòng này sẽ không hiện trong lời đồng bộ. Vẫn lưu?", "\(missing)")
                let sheet = UIAlertController(title: L("Chưa đóng dấu hết"), message: message, preferredStyle: .alert)
                sheet.addAction(UIAlertAction(title: L("Quay lại"), style: .cancel, handler: nil))
                sheet.addAction(UIAlertAction(title: L("Vẫn lưu"), style: .default) { [weak self] _ in self?.write(text) })
                present(sheet, animated: true, completion: nil)
                return
            }
        }
        write(text)
    }

    private func write(_ text: String) {
        do {
            try CustomLyricsStore.save(text, videoId: song.videoId)
            dirty = false
            Toast.show(L("Đã lưu lời bài hát"))
            finish()
        } catch {
            alert(L("Không lưu được"), error.localizedDescription)
        }
    }

    @objc private func moreTapped() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if mode == .text {
            sheet.addAction(UIAlertAction(title: L("Dán từ clipboard"), style: .default) { [weak self] _ in self?.pasteFromClipboard() })
            sheet.addAction(UIAlertAction(title: L("Bỏ hết mốc thời gian"), style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.textView.text = CustomLyricsStore.plainText(from: self.textView.text ?? "")
                self.dirty = true
            })
            if let cached = LyricsService.shared.cached(song.videoId), !CustomLyricsStore.exists(videoId: song.videoId) || textView.text.isEmpty,
               !cached.synced.isEmpty || !(cached.plain ?? "").isEmpty {
                sheet.addAction(UIAlertAction(title: L("Lấy lời đang hiển thị làm bản nháp"), style: .default) { [weak self] _ in
                    self?.useCurrentLyricsAsDraft(cached)
                })
            }
            sheet.addAction(UIAlertAction(title: L("Xoá hết văn bản"), style: .destructive) { [weak self] _ in
                self?.textView.text = ""
                self?.dirty = true
            })
        } else {
            sheet.addAction(UIAlertAction(title: L("Xoá hết mốc thời gian"), style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                for i in self.lines.indices { self.lines[i].time = nil }
                self.pointer = 0
                self.dirty = true
                self.tableView.reloadData()
                self.scrollToPointer(animated: true)
            })
        }
        if CustomLyricsStore.exists(videoId: song.videoId) {
            sheet.addAction(UIAlertAction(title: L("Xoá lời tự tạo của bài này"), style: .destructive) { [weak self] _ in
                self?.confirmDelete()
            })
        }
        sheet.addAction(UIAlertAction(title: L("Đóng"), style: .cancel, handler: nil))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(sheet, animated: true, completion: nil)
    }

    private func pasteFromClipboard() {
        guard let pasted = UIPasteboard.general.string, !pasted.isEmpty else {
            Toast.show(L("Clipboard đang trống"))
            return
        }
        if let range = textView.selectedTextRange, textView.isFirstResponder {
            textView.replace(range, withText: pasted)
        } else if (textView.text ?? "").isEmpty {
            textView.text = pasted
        } else {
            textView.text = (textView.text ?? "") + "\n" + pasted
        }
        dirty = true
    }

    private func useCurrentLyricsAsDraft(_ result: LyricsResult) {
        var out: [String] = []
        if !result.synced.isEmpty {
            for line in result.synced { out.append(CustomLyricsStore.stamp(line.time) + line.text) }
        } else if let plain = result.plain {
            out.append(plain)
        }
        textView.text = out.joined(separator: "\n")
        dirty = true
    }

    private func confirmDelete() {
        let sheet = UIAlertController(title: L("Xoá lời tự tạo của bài này?"),
                                      message: L("Bài sẽ quay lại dùng lời tìm trên mạng."), preferredStyle: .alert)
        sheet.addAction(UIAlertAction(title: L("Huỷ"), style: .cancel, handler: nil))
        sheet.addAction(UIAlertAction(title: L("Xoá"), style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            CustomLyricsStore.delete(videoId: self.song.videoId)
            self.dirty = false
            Toast.show(L("Đã xoá lời tự tạo"))
            self.finish()
        })
        present(sheet, animated: true, completion: nil)
    }

    private func alert(_ title: String, _ message: String) {
        let sheet = UIAlertController(title: title, message: message, preferredStyle: .alert)
        sheet.addAction(UIAlertAction(title: L("Đóng"), style: .cancel, handler: nil))
        present(sheet, animated: true, completion: nil)
    }

    // MARK: - Bàn phím / văn bản

    func textViewDidChange(_ textView: UITextView) {
        dirty = true
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.height - converted.minY)
        let hiding = note.name == UIResponder.keyboardWillHideNotification
        textBottom.constant = hiding ? -12 : -(max(0, overlap - view.safeAreaInsets.bottom) + 12)
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }
}
