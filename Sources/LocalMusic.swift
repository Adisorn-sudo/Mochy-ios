import UIKit
import AVFoundation

/// Nhạc nhập từ máy: sao chép tệp vào Documents/LocalMusic/, đọc thẻ (tên bài, nghệ sĩ, album, ảnh bìa, độ dài) bằng AVAsset
/// rồi tạo `LocalTrack` lưu vào `Library`. Tệp luôn được SAO CHÉP vào thư mục của app vì quyền đọc tệp mà bộ chọn tệp cấp
/// chỉ là tạm thời (hết hạn khi đóng app hoặc khi tệp tạm bị dọn).
enum LocalMusicStore {
    /// Các đuôi tệp được nhận.
    static let allowedExtensions: Set<String> = ["mp3", "m4a", "wav", "flac"]

    /// Scheme riêng để Song.thumbnailURL trỏ tới ảnh bìa trên đĩa mà không phải lưu đường dẫn tuyệt đối.
    static let artworkScheme = "mochylocal"

    // MARK: - Thư mục

    static var documentsDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Documents/LocalMusic/
    static var directory: URL {
        let dir = documentsDirectory.appendingPathComponent("LocalMusic", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    /// Documents/LocalMusic/Artwork/
    static var artworkDirectory: URL {
        let dir = directory.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    static func fileURL(for track: LocalTrack) -> URL {
        return directory.appendingPathComponent(track.fileName)
    }

    private static func artworkFile(id: String) -> URL {
        return artworkDirectory.appendingPathComponent(id + ".jpg")
    }

    /// URL "mochylocal://artwork/<id>" dùng làm thumbnailURL của Song; ImageLoader biết đọc ra ảnh trên đĩa.
    static func artworkURL(id: String) -> URL? {
        return URL(string: "\(artworkScheme)://artwork/\(id)")
    }

    /// Đổi URL dạng mochylocal://artwork/<id> thành tệp ảnh thật.
    static func artworkFile(forArtworkURL url: URL) -> URL? {
        guard url.scheme == artworkScheme else { return nil }
        let id = url.lastPathComponent
        guard !id.isEmpty else { return nil }
        if url.host == "custom" { return CustomArtworkStore.file(forBaseName: id) }   // ảnh tự chọn
        return artworkFile(id: id)
    }

    static func deleteFiles(for track: LocalTrack) {
        try? FileManager.default.removeItem(at: fileURL(for: track))
        try? FileManager.default.removeItem(at: artworkFile(id: track.id))
    }

    /// Tổng dung lượng nhạc máy (byte).
    static func totalBytes() -> Int64 {
        return Library.shared.localTracks.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - Kết quả nhập

    struct Failure {
        let name: String
        let reason: String
    }

    struct Summary {
        var added: [LocalTrack] = []
        var duplicates = 0
        var failures: [Failure] = []
    }

    private static let importQueue = DispatchQueue(label: "mochyios.localmusic.import", qos: .userInitiated)

    /// Nhập nhiều tệp. `progress(done, total)` và `completion` luôn chạy ở luồng chính.
    static func importFiles(_ urls: [URL], progress: ((Int, Int) -> Void)? = nil, completion: @escaping (Summary) -> Void) {
        importQueue.async {
            var summary = Summary()
            let total = urls.count
            for (index, url) in urls.enumerated() {
                DispatchQueue.main.async { progress?(index, total) }
                switch importOne(url) {
                case .added(let track):
                    // Hai tệp giống nhau trong cùng một lần chọn cũng chỉ giữ một.
                    if summary.added.contains(where: { isSame($0, track) }) {
                        deleteFiles(for: track)
                        summary.duplicates += 1
                    } else {
                        summary.added.append(track)
                    }
                case .duplicate: summary.duplicates += 1
                case .failed(let reason): summary.failures.append(Failure(name: url.lastPathComponent, reason: reason))
                }
            }
            DispatchQueue.main.async {
                Library.shared.addLocalTracks(summary.added)
                progress?(total, total)
                completion(summary)
            }
        }
    }

    /// Quét thư mục Documents/LocalMusic: nhận các tệp nhạc bạn tự chép vào bằng ứng dụng Tệp / Filza / iTunes mà app chưa biết.
    static func scanFolder(progress: ((Int, Int) -> Void)? = nil, completion: @escaping (Summary) -> Void) {
        let known = Set(Library.shared.localTracks.map { $0.fileName })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let urls = names.filter { name in
            let url = directory.appendingPathComponent(name)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return !isDir.boolValue && !known.contains(name) && allowedExtensions.contains(url.pathExtension.lowercased())
        }.map { directory.appendingPathComponent($0) }
        importFiles(urls, progress: progress, completion: completion)
    }

    /// Hai bản ghi cùng là một bài: cùng dung lượng, độ dài, tên bài và nghệ sĩ.
    static func isSame(_ a: LocalTrack, _ b: LocalTrack) -> Bool {
        return a.fileSize == b.fileSize && abs(a.duration - b.duration) < 0.5
            && a.title.lowercased() == b.title.lowercased() && a.artist.lowercased() == b.artist.lowercased()
    }

    private enum Outcome {
        case added(LocalTrack)
        case duplicate
        case failed(String)
    }

    /// Chạy ở luồng nền (đọc thẻ bằng AVAsset có chờ đồng bộ).
    private static func importOne(_ source: URL) -> Outcome {
        let ext = source.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            return .failed(L("Định dạng không được hỗ trợ (chỉ nhận MP3, M4A, WAV, FLAC)"))
        }
        // Tệp từ bộ chọn nằm ngoài sandbox cần mở quyền tạm thời trong lúc đọc.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let id = Song.localPrefix + UUID().uuidString.lowercased()
        let fileName = id + "." + ext
        let destination = directory.appendingPathComponent(fileName)
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            if source.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path {
                try fm.moveItem(at: source, to: destination)      // tệp đã nằm sẵn trong LocalMusic (quét thư mục)
            } else {
                try fm.copyItem(at: source, to: destination)
            }
        } catch {
            return .failed(L("Không sao chép được tệp: ") + error.localizedDescription)
        }

        let meta = readMetadata(destination, originalName: source.deletingPathExtension().lastPathComponent)
        guard meta.playable, meta.duration > 0 else {
            try? fm.removeItem(at: destination)
            return .failed(L("Không đọc được tệp âm thanh này"))
        }

        var hasArtwork = false
        if let data = meta.artwork, let jpeg = scaledJPEG(from: data, maxSide: 1000) {
            hasArtwork = (try? jpeg.write(to: artworkFile(id: id), options: .atomic)) != nil
        }
        var size: Int64 = 0
        if let attributes = try? fm.attributesOfItem(atPath: destination.path), let number = attributes[.size] as? NSNumber {
            size = number.int64Value
        }
        let track = LocalTrack(id: id, fileName: fileName, originalName: source.lastPathComponent, title: meta.title,
                               artist: meta.artist, album: meta.album, duration: meta.duration, hasArtwork: hasArtwork,
                               fileSize: size, added: Date())
        var isDuplicate = false
        DispatchQueue.main.sync { isDuplicate = Library.shared.hasLocalDuplicate(of: track) }
        if isDuplicate {
            deleteFiles(for: track)
            return .duplicate
        }
        return .added(track)
    }

    // MARK: - Đọc thẻ bằng AVAsset

    private struct Metadata {
        var title = ""
        var artist = ""
        var album = ""
        var duration: Double = 0
        var playable = false
        var artwork: Data?
    }

    private static func loadValues(of item: AVMetadataItem) {
        let semaphore = DispatchSemaphore(value: 0)
        item.loadValuesAsynchronously(forKeys: ["value", "stringValue", "dataValue"]) { semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 5)
    }

    private static func text(_ items: [AVMetadataItem], _ identifier: AVMetadataIdentifier) -> String? {
        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
            loadValues(of: item)
            if let value = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        return nil
    }

    private static func readMetadata(_ url: URL, originalName: String) -> Metadata {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let semaphore = DispatchSemaphore(value: 0)
        asset.loadValuesAsynchronously(forKeys: ["duration", "playable", "commonMetadata", "metadata"]) { semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 30)

        var meta = Metadata()
        let seconds = asset.duration.seconds
        meta.duration = seconds.isFinite ? seconds : 0
        meta.playable = asset.isPlayable

        let common = asset.commonMetadata
        var title = text(common, .commonIdentifierTitle)
        var artist = text(common, .commonIdentifierArtist)
        if artist == nil { artist = text(common, .commonIdentifierCreator) }
        let album = text(common, .commonIdentifierAlbumName)

        // Ảnh bìa: thẻ ID3 (APIC) và iTunes (covr) đều lộ ra qua định danh chung.
        for item in AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork) {
            loadValues(of: item)
            if let data = item.dataValue {
                meta.artwork = data
            } else if let data = item.value as? Data {
                meta.artwork = data
            } else if let dict = item.value as? [String: Any], let data = dict["data"] as? Data {
                meta.artwork = data
            }
            if meta.artwork != nil { break }
        }

        // Không có thẻ (hay gặp ở FLAC/WAV): đoán từ tên tệp, dạng "Nghệ sĩ - Tên bài".
        let base = originalName.trimmingCharacters(in: .whitespacesAndNewlines)
        if title == nil {
            if artist == nil, let range = base.range(of: " - ") {
                let left = String(base[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let right = String(base[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !left.isEmpty && !right.isEmpty {
                    artist = left
                    title = right
                }
            }
            if title == nil { title = base.isEmpty ? L("Không có tên") : base }
        }
        meta.title = title ?? base
        meta.artist = artist ?? ""
        meta.album = album ?? ""
        return meta
    }

    /// Thu nhỏ ảnh bìa (tối đa maxSide px) rồi nén JPEG để thư viện không phình ra.
    private static func scaledJPEG(from data: Data, maxSide: CGFloat) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let longest = max(image.size.width, image.size.height)
        var target = image.size
        if longest > maxSide {
            let ratio = maxSide / longest
            target = CGSize(width: floor(image.size.width * ratio), height: floor(image.size.height * ratio))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.85)
    }
}

/// Mở bộ chọn tệp (UIDocumentPickerViewController) để chọn nhiều tệp nhạc, nhập chúng và báo kết quả.
final class LocalMusicImporter: NSObject, UIDocumentPickerDelegate {
    private static var active: LocalMusicImporter?

    private weak var presenter: UIViewController?
    private let onProgress: ((Int, Int) -> Void)?
    private let onFinish: (LocalMusicStore.Summary) -> Void

    private init(presenter: UIViewController, onProgress: ((Int, Int) -> Void)?, onFinish: @escaping (LocalMusicStore.Summary) -> Void) {
        self.presenter = presenter
        self.onProgress = onProgress
        self.onFinish = onFinish
    }

    /// `onFinish` chạy ở luồng chính sau khi nhập xong.
    static func present(from vc: UIViewController, onProgress: ((Int, Int) -> Void)? = nil,
                        onFinish: @escaping (LocalMusicStore.Summary) -> Void) {
        let importer = LocalMusicImporter(presenter: vc, onProgress: onProgress, onFinish: onFinish)
        active = importer
        // "public.data" đứng cuối để FLAC luôn chọn được (không phải bản iOS nào cũng gắn FLAC vào public.audio);
        // đuôi tệp được kiểm lại khi nhập.
        let types = ["public.audio", "public.mp3", "public.mpeg-4-audio", "com.microsoft.waveform-audio", "org.xiph.flac", "public.data"]
        let picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
        picker.delegate = importer
        picker.allowsMultipleSelection = true
        vc.present(picker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        LocalMusicStore.importFiles(urls, progress: onProgress) { [weak self] summary in
            guard let self = self else { return }
            self.onFinish(summary)
            LocalMusicImporter.active = nil
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        LocalMusicImporter.active = nil
    }

    /// Câu tóm tắt kết quả nhập (dùng chung cho các màn hình).
    static func message(for summary: LocalMusicStore.Summary) -> String {
        var lines: [String] = []
        if !summary.added.isEmpty { lines.append(LF("Đã nhập %@ bài.", "\(summary.added.count)")) }
        if summary.duplicates > 0 { lines.append(LF("Bỏ qua %@ bài đã có.", "\(summary.duplicates)")) }
        if !summary.failures.isEmpty {
            lines.append(LF("Không nhập được %@ tệp:", "\(summary.failures.count)"))
            for failure in summary.failures.prefix(5) { lines.append("• \(failure.name) – \(failure.reason)") }
        }
        return lines.isEmpty ? L("Không có tệp nào được nhập.") : lines.joined(separator: "\n")
    }
}
