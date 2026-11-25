import Foundation
import UIKit

extension Notification.Name {
    static let languageChanged = Notification.Name("MochyiOSLanguageChanged")
}

/// Ngôn ngữ giao diện của app. Văn bản gốc trong mã nguồn là tiếng Việt và được dùng làm "khoá" dịch:
/// khoá nào chưa có bản dịch thì hiện đúng chữ tiếng Việt gốc (không bao giờ hiện chuỗi trống).
enum AppLanguage: String, CaseIterable {
    case system = "system"
    case vietnamese = "vi"
    case english = "en"
    case thai = "th"

    /// Mã thư mục .lproj; nil với .system.
    var code: String? {
        return self == .system ? nil : rawValue
    }

    /// Tên hiển thị của ngôn ngữ (luôn bằng chính ngôn ngữ đó để người dùng tìm được dù đang ở ngôn ngữ nào).
    var displayName: String {
        switch self {
        case .system: return L("Theo hệ thống")
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        case .thai: return "ไทย"
        }
    }

    static let supported: [AppLanguage] = [.vietnamese, .english, .thai]
}

final class Localizer {
    static let shared = Localizer()

    private let defaults = UserDefaults.standard
    private let key = "ui.language"
    private let lock = NSLock()
    private var bundle: Bundle?
    private(set) var resolved: AppLanguage = .vietnamese

    private init() {
        reload()
    }

    /// Lựa chọn của người dùng (có thể là "theo hệ thống").
    var selected: AppLanguage {
        get { return AppLanguage(rawValue: defaults.string(forKey: key) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: key) }
    }

    /// Đổi ngôn ngữ: có hiệu lực ngay trong app (AppDelegate dựng lại giao diện khi nhận thông báo).
    /// Đồng thời ghi AppleLanguages để các hộp thoại do hệ thống vẽ (chọn tệp, chia sẻ…) cũng đổi sau khi mở lại app.
    func select(_ language: AppLanguage) {
        selected = language
        if let code = language.code {
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
        reload()
        NotificationCenter.default.post(name: .languageChanged, object: nil)
    }

    private func reload() {
        lock.lock()
        defer { lock.unlock() }
        let target = Localizer.resolve(selected)
        resolved = target
        if let path = Bundle.main.path(forResource: target.rawValue, ofType: "lproj") {
            bundle = Bundle(path: path)
        } else {
            bundle = nil
        }
    }

    /// "Theo hệ thống": lấy ngôn ngữ ưu tiên đầu tiên của máy mà app có (Thái, Anh, Việt); không có thì tiếng Anh.
    private static func resolve(_ choice: AppLanguage) -> AppLanguage {
        if choice != .system { return choice }
        for entry in Locale.preferredLanguages {
            let prefix = entry.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? entry
            if let match = AppLanguage.supported.first(where: { $0.rawValue == prefix.lowercased() }) {
                return match
            }
        }
        return .english
    }

    func string(_ key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        // Tiếng Việt là ngôn ngữ gốc của mã nguồn: khoá chính là bản tiếng Việt.
        if resolved == .vietnamese { return key }
        guard let bundle = bundle else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

/// Dịch một chuỗi cố định. Ví dụ: `L("Thư viện")`.
func L(_ key: String) -> String {
    return Localizer.shared.string(key)
}

/// Dịch chuỗi có tham số. Khoá dùng `%@` cho từng tham số theo thứ tự; bản dịch có thể đảo thứ tự bằng `%2$@`, `%1$@`.
/// Ví dụ: `LF("%@ bài · %@", "\(count)", size)`.
func LF(_ key: String, _ args: String...) -> String {
    let template = Array(L(key))
    var out = ""
    var sequential = 0
    var i = 0
    while i < template.count {
        let c = template[i]
        if c == "%", i + 1 < template.count {
            if template[i + 1] == "@" {
                if sequential < args.count { out += args[sequential] }
                sequential += 1
                i += 2
                continue
            }
            // Dạng có vị trí: %1$@, %2$@ …
            var j = i + 1
            var number = 0
            while j < template.count, template[j].isASCII, let digit = template[j].wholeNumberValue {
                number = number * 10 + digit
                j += 1
            }
            if j > i + 1, j + 1 < template.count, template[j] == "$", template[j + 1] == "@" {
                if number >= 1 && number <= args.count { out += args[number - 1] }
                i = j + 2
                continue
            }
        }
        out.append(c)
        i += 1
    }
    return out
}
