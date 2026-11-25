import Foundation

/// Một bài hát trong kết quả tìm kiếm / hàng đợi / thư viện.
struct Song: Codable, Hashable {
    let videoId: String
    let title: String
    let artist: String
    let subtitle: String      // "Nghệ sĩ · Album · 3:45"
    let duration: String?     // "3:45" nếu có
    let thumbnailURL: URL?
    var explicit: Bool? = nil
    var artistId: String? = nil   // browseId của nghệ sĩ trên YouTube Music (nếu biết)

    /// Ảnh bìa lớn hơn (dùng cho màn hình đang phát).
    var largeThumbnailURL: URL? {
        if let custom = CustomArtworkStore.url(for: videoId) { return custom }   // ảnh người dùng tự chọn
        guard let url = thumbnailURL else { return nil }
        let big = url.absoluteString.replacingOccurrences(of: "=w226-h226", with: "=w544-h544")
        return URL(string: big) ?? url
    }

    /// Ảnh bìa nhỏ để hiển thị: ảnh người dùng tự chọn (nếu có) hoặc ảnh gốc.
    var displayThumbnailURL: URL? {
        return CustomArtworkStore.url(for: videoId) ?? thumbnailURL
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        return lhs.videoId == rhs.videoId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(videoId)
    }
}

extension Song {
    /// Tiền tố videoId của bài nhập từ máy (khác hẳn mã YouTube, nên không bao giờ trùng).
    static let localPrefix = "local-"

    /// Bài này là tệp nhạc nhập từ máy (phát bằng file URL), không phải luồng YouTube Music.
    var isLocalFile: Bool {
        return videoId.hasPrefix(Song.localPrefix)
    }
}

/// Một tệp nhạc nhập từ máy. Tệp âm thanh nằm ở Documents/LocalMusic/<id>.<đuôi>, ảnh bìa ở Documents/LocalMusic/Artwork/<id>.jpg.
/// Chỉ lưu tên tệp (không lưu đường dẫn tuyệt đối) vì đường dẫn của app đổi sau mỗi lần cài lại / cập nhật.
struct LocalTrack: Codable, Hashable {
    let id: String               // cũng là videoId của Song, dạng "local-<UUID>"
    var fileName: String         // tên tệp trong Documents/LocalMusic/
    var originalName: String     // tên tệp gốc người dùng chọn
    var title: String
    var artist: String           // rỗng nếu tệp không có thẻ nghệ sĩ
    var album: String
    var duration: Double         // giây
    var hasArtwork: Bool
    var fileSize: Int64
    let added: Date

    /// Mô hình bài hát dùng chung với phần còn lại của app (hàng đợi, yêu thích, playlist, màn hình đang phát…).
    var song: Song {
        var parts: [String] = [artist.isEmpty ? L("Không rõ nghệ sĩ") : artist]
        if !album.isEmpty { parts.append(album) }
        parts.append(formatTime(duration))
        return Song(videoId: id, title: title, artist: artist, subtitle: parts.joined(separator: " · "),
                    duration: formatTime(duration), thumbnailURL: hasArtwork ? LocalMusicStore.artworkURL(id: id) : nil)
    }

    static func == (lhs: LocalTrack, rhs: LocalTrack) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct Playlist: Codable {
    let id: String
    var name: String
    var songs: [Song]
    let created: Date
    var sourceURL: String? = nil   // link gốc nếu playlist được nhập từ Spotify/Apple Music/…
}

struct HistoryEntry: Codable {
    let song: Song
    let date: Date
}

/// Một hàng ngang bài hát trên trang chủ.
struct Shelf: Codable {
    let title: String
    let songs: [Song]
}

/// Lỗi có thông điệp tiếng Việt để hiện thẳng lên màn hình (giúp tìm lỗi trên máy thật).
enum MochyError: Error, LocalizedError {
    case http(Int, String, String)
    case badResponse(String)
    case noStream(String)
    case playback(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let host, let snippet):
            return LF("Máy chủ %@ trả về HTTP %@\n%@", "\(host)", "\(code)", "\(snippet)")
        case .badResponse(let s):
            return LF("Phản hồi không hợp lệ: %@", "\(s)")
        case .noStream(let s):
            return s
        case .playback(let s):
            return s
        }
    }
}

/// Luồng âm thanh đã giải ra được từ YouTube Music.
struct StreamInfo {
    let url: URL
    let userAgent: String
    let mimeType: String
    let clientName: String
    let bitrate: Int       // bit/giây, 0 nếu không rõ
    let sampleRate: Int    // Hz, 0 nếu không rõ
    var durationSeconds: Double = 0  // độ dài thật theo YouTube, 0 nếu không rõ
    var videoURL: URL? = nil    // luồng video (không tiếng) của MV, nếu có
    var unverified = false      // không client nào qua kiểm tra byte cuối
    var contentLength: Int64 = 0  // byte, 0 nếu không rõ

    var codecLabel: String {
        return mimeType.hasPrefix("audio/mp4") ? "AAC" : "MP4"
    }

    /// Ví dụ "AAC · 44,1 kHz · 131 kbps" (kiểu "Stats for nerds" của Mochy).
    var badge: String {
        var parts = [codecLabel]
        if sampleRate > 0 {
            parts.append(String(format: "%.1f kHz", Double(sampleRate) / 1000.0).replacingOccurrences(of: ".", with: ","))
        }
        if bitrate > 0 { parts.append("\(bitrate / 1000) kbps") }
        parts.append(unverified ? clientName + L(" (bị cắt)") : clientName)
        return parts.joined(separator: " · ")
    }
}
