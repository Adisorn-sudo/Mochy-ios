import UIKit

extension String {
    /// Có ký tự tiếng Thái (U+0E00 – U+0E7F) trong chuỗi không.
    var containsThai: Bool {
        for scalar in unicodeScalars where scalar.value >= 0x0E00 && scalar.value <= 0x0E7F {
            return true
        }
        return false
    }
}

/// Font tiếng Thái dùng làm "font dự phòng" cho SF Pro Rounded (bản đóng kèm chỉ có chữ Latin + tiếng Việt, không có glyph Thái).
/// Thứ tự ưu tiên cho mỗi mức đậm:
///   1. Font Thái tròn đầu (looped) nếu bạn tự thêm vào app/Resources/Fonts/Thai/ (xem Info.plist) – hợp nhất với SF Pro Rounded.
///   2. Sukhumvit Set (font Thái của hệ thống từ iOS 13).
///   3. Thonburi (có sẵn từ iOS 6, dùng cho iOS 12).
/// Font dự phòng được khai báo bằng cascadeList nên iOS tự ghép đúng glyph, tránh lỗi sai độ đậm và dấu thanh / nguyên âm bị lệch khi font chính không có chữ Thái.
enum ThaiFont {
    // Tên PostScript, theo thứ tự 7 mức đậm: Light, Regular, Medium, Semibold, Bold, Heavy, Black.
    private static let bundled = [
        "NotoSansThaiLooped-Light", "NotoSansThaiLooped-Regular", "NotoSansThaiLooped-Medium", "NotoSansThaiLooped-SemiBold",
        "NotoSansThaiLooped-Bold", "NotoSansThaiLooped-ExtraBold", "NotoSansThaiLooped-Black"
    ]
    private static let sukhumvit = [
        "SukhumvitSet-Light", "SukhumvitSet-Text", "SukhumvitSet-Medium", "SukhumvitSet-SemiBold",
        "SukhumvitSet-Bold", "SukhumvitSet-Bold", "SukhumvitSet-Bold"
    ]
    private static let thonburi = [
        "Thonburi-Light", "Thonburi", "Thonburi", "Thonburi-Bold", "Thonburi-Bold", "Thonburi-Bold", "Thonburi-Bold"
    ]

    /// Danh sách font dự phòng cho một mức đậm (chỉ gồm font thật sự có trên máy).
    static func fallbacks(size: CGFloat, weightIndex: Int) -> [UIFontDescriptor] {
        let i = min(max(weightIndex, 0), 6)
        var out: [UIFontDescriptor] = []
        for list in [bundled, sukhumvit, thonburi] {
            if let font = UIFont(name: list[i], size: size) { out.append(font.fontDescriptor) }
        }
        return out
    }

    /// Chiều cao một dòng đủ chỗ cho dấu trên (dấu thanh, nguyên âm trên) và nguyên âm dưới của chữ Thái.
    static func lineHeight(for font: UIFont, text: String) -> CGFloat {
        if text.containsThai { return max(font.lineHeight, ceil(font.pointSize * 1.42)) }
        return font.lineHeight
    }

    /// Hệ số giãn dòng khi văn bản có chữ Thái (chữ Latin giữ nguyên để không đổi thiết kế cũ).
    static func lineHeightMultiple(for text: String) -> CGFloat {
        return text.containsThai ? 1.2 : 1.0
    }
}

/// Font SF Pro Rounded đóng kèm app (đã cắt còn chữ Latin + tiếng Việt). Bảy mức đậm từ Light đến Black;
/// nếu font chưa nạp được thì dùng font hệ thống cùng độ đậm. Chữ Thái được ghép từ font Thái dự phòng (xem ThaiFont).
enum RoundedFont {
    static let names = ["SFProRounded-Light", "SFProRounded-Regular", "SFProRounded-Medium", "SFProRounded-Semibold",
                        "SFProRounded-Bold", "SFProRounded-Heavy", "SFProRounded-Black"]
    static let weights: [UIFont.Weight] = [.light, .regular, .medium, .semibold, .bold, .heavy, .black]
    static var titles: [String] {
        return [L("Rất nhạt"), L("Nhạt"), L("Vừa"), L("Hơi đậm"), L("Đậm"), L("Rất đậm"), L("Đậm nhất")]
    }
    static let defaultLyricIndex = 6   // mặc định chọn mức đậm nhất

    private static var cache: [String: UIFont] = [:]
    private static let cacheLock = NSLock()

    static func font(_ size: CGFloat, index: Int) -> UIFont {
        let i = min(max(index, 0), names.count - 1)
        let key = "\(i)|\(size)"
        cacheLock.lock()
        if let hit = cache[key] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let result: UIFont
        if let base = UIFont(name: names[i], size: size) {
            let fallbacks = ThaiFont.fallbacks(size: size, weightIndex: i)
            if fallbacks.isEmpty {
                result = base
            } else {
                let descriptor = base.fontDescriptor.addingAttributes([UIFontDescriptor.AttributeName.cascadeList: fallbacks])
                result = UIFont(descriptor: descriptor, size: size)
            }
        } else {
            result = UIFont.systemFont(ofSize: size, weight: weights[i])
        }
        cacheLock.lock()
        cache[key] = result
        cacheLock.unlock()
        return result
    }
}
