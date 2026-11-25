import Foundation

extension Notification.Name {
    /// Lời tự tạo vừa được lưu / xoá. userInfo["videoId"] cho biết bài nào.
    static let customLyricsChanged = Notification.Name("MochyiOSCustomLyricsChanged")
}

/// Lời bài hát do người dùng tự tạo, lưu thành tệp .lrc ở Documents/CustomLyrics/ (xem được và sao lưu được trong ứng dụng Tệp).
/// Mỗi bài một tệp, gắn với `Song.videoId`. Lời ở đây luôn được ưu tiên số 1, trước mọi nguồn trực tuyến (xem LyricsService).
enum CustomLyricsStore {
    /// Documents/CustomLyrics/
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CustomLyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    /// Tên tệp an toàn từ videoId. Hệ thống tệp của iOS không phân biệt hoa/thường, mà mã YouTube thì có
    /// (aB… và Ab… là hai bài khác nhau), nên chữ hoa được mã hoá thành "~" + chữ thường để hai bài không đè tệp của nhau.
    static func fileName(for videoId: String) -> String {
        var out = ""
        for scalar in videoId.unicodeScalars {
            switch scalar {
            case "a"..."z", "0"..."9", "-", "_":
                out.unicodeScalars.append(scalar)
            case "A"..."Z":
                out += "~" + String(scalar).lowercased()
            default:
                out += "_"
            }
        }
        return out + ".lrc"
    }

    static func fileURL(videoId: String) -> URL {
        return directory.appendingPathComponent(fileName(for: videoId))
    }

    static func exists(videoId: String) -> Bool {
        return FileManager.default.fileExists(atPath: fileURL(videoId: videoId).path)
    }

    /// Nội dung tệp .lrc (nil nếu chưa có hoặc rỗng).
    static func load(videoId: String) -> String? {
        guard let data = try? Data(contentsOf: fileURL(videoId: videoId)) else { return nil }
        var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .windowsCP1252)
        if let t = text, t.hasPrefix("\u{FEFF}") { text = String(t.dropFirst()) }   // bỏ BOM
        guard let result = text, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return result
    }

    /// Ghi lời (UTF-8). Văn bản có mốc [mm:ss.xx] thì thành lời đồng bộ, không có thì thành lời thường.
    static func save(_ text: String, videoId: String) throws {
        let clean = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard let data = clean.data(using: .utf8) else { throw NSError(domain: "CustomLyrics", code: 1, userInfo: nil) }
        try data.write(to: fileURL(videoId: videoId), options: .atomic)
        changed(videoId)
    }

    static func delete(videoId: String) {
        let existed = exists(videoId: videoId)
        try? FileManager.default.removeItem(at: fileURL(videoId: videoId))
        if existed { changed(videoId) }
    }

    private static func changed(_ videoId: String) {
        LyricsService.shared.invalidate(videoId: videoId)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .customLyricsChanged, object: nil, userInfo: ["videoId": videoId])
        }
    }

    /// Chuyển thành kết quả lời dùng chung với các nguồn trực tuyến.
    static func result(videoId: String) -> LyricsResult? {
        guard let text = load(videoId: videoId) else { return nil }
        let synced = LyricsService.parseLRC(text)
        let plain = plainText(from: text)
        if synced.isEmpty && plain.isEmpty { return nil }
        return LyricsResult(synced: synced, plain: plain.isEmpty ? nil : plain, source: L("Lời tự tạo"))
    }

    /// Bỏ mốc thời gian, thẻ từng từ và dòng tiêu đề ([ti:], [ar:]…) để còn lại lời thuần.
    static func plainText(from text: String) -> String {
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            if isHeader(raw) { continue }
            var line = raw.replacingOccurrences(of: "\\[\\d{1,3}:\\d{1,2}(?:[.:]\\d{1,3})?\\]", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "<\\d{1,3}:\\d{1,2}(?:[.:]\\d{1,3})?>", with: "", options: .regularExpression)
            lines.append(line.trimmingCharacters(in: .whitespaces))
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Dòng thẻ thông tin của LRC: [ti:…] [ar:…] [al:…] [by:…] [offset:…] …
    static func isHeader(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.range(of: "^\\[(ti|ar|al|au|by|re|ve|length|offset|id):[^\\]]*\\]$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Định dạng mốc LRC "[mm:ss.xx]" (phần trăm giây, cắt xuống để không vượt quá thời điểm thật).
    static func stamp(_ seconds: Double) -> String {
        let centis = max(0, Int((seconds * 100).rounded(.down)))
        return String(format: "[%02d:%02d.%02d]", centis / 6000, (centis / 100) % 60, centis % 100)
    }
}
