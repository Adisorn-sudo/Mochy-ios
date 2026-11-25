import UIKit

extension Notification.Name {
    /// Nền lời / hiệu ứng sao vừa đổi.
    static let lyricBackdropChanged = Notification.Name("MochyiOSLyricBackdropChanged")
}

/// Kiểu nền của màn hình lời bài hát.
enum LyricBackdropStyle: Int {
    case artwork = 0   // màu chuyển động theo ảnh bìa (mặc định cũ)
    case black         // đen tuyền
    case color         // một màu tự chọn (chuyển sắc nhẹ)
    case photo         // ảnh tự chọn từ thư viện

    var title: String {
        switch self {
        case .artwork: return L("Theo ảnh bìa")
        case .black: return L("Đen tuyền")
        case .color: return L("Màu tuỳ chọn")
        case .photo: return L("Ảnh tự chọn")
        }
    }
}

extension AppSettings {
    static var lyricBackdropStyle: LyricBackdropStyle {
        get { return LyricBackdropStyle(rawValue: UserDefaults.standard.integer(forKey: "lyrics.backdrop.style")) ?? .artwork }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lyrics.backdrop.style") }
    }

    /// Màu nền tự chọn, lưu dạng "RRGGBB".
    static var lyricBackdropColor: UIColor {
        get {
            let hex = UserDefaults.standard.string(forKey: "lyrics.backdrop.color") ?? "2B1B5A"
            return UIColor(backdropHex: hex)
        }
        set { UserDefaults.standard.set(newValue.backdropHex, forKey: "lyrics.backdrop.color") }
    }

    /// Độ sáng / số lượng "sao" lấp lánh: 0 (tắt) ... 100.
    static var starLevel: Int {
        get {
            if UserDefaults.standard.object(forKey: "lyrics.stars") == nil { return 60 }
            return min(max(UserDefaults.standard.integer(forKey: "lyrics.stars"), 0), 100)
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), 100), forKey: "lyrics.stars") }
    }
}

extension UIColor {
    convenience init(backdropHex hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }

    var backdropHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(min(max(r, 0), 1) * 255))
        let gi = Int(round(min(max(g, 0), 1) * 255))
        let bi = Int(round(min(max(b, 0), 1) * 255))
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }

    fileprivate func backdropScaled(_ f: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, r * f), green: min(1, g * f), blue: min(1, b * f), alpha: 1)
    }
}

/// Ảnh nền tự chọn: Documents/CustomBackdrop/lyrics.jpg
enum BackdropStore {
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CustomBackdrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    static var file: URL { return directory.appendingPathComponent("lyrics.jpg") }

    static func load() -> UIImage? {
        return UIImage(contentsOfFile: file.path)
    }

    /// Thu nhỏ (tối đa 1600px cạnh dài) rồi lưu JPEG.
    static func save(_ image: UIImage) -> Bool {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return false }
        var target = image.size
        if longest > 1600 {
            let ratio = 1600 / longest
            target = CGSize(width: floor(image.size.width * ratio), height: floor(image.size.height * ratio))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.88),
              (try? data.write(to: file, options: .atomic)) != nil else { return false }
        return true
    }

    static func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .lyricBackdropChanged, object: nil)
        }
    }
}

/// Chọn ảnh từ thư viện làm nền lời.
final class BackdropPhotoPicker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private static var active: BackdropPhotoPicker?

    static func present(from vc: UIViewController) {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            Toast.show(L("Không mở được thư viện ảnh"))
            return
        }
        let picker = UIImagePickerController()
        let helper = BackdropPhotoPicker()
        active = helper
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        picker.delegate = helper
        vc.present(picker, animated: true, completion: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true) {
            if let image = image, BackdropStore.save(image) {
                AppSettings.lyricBackdropStyle = .photo
                BackdropStore.notifyChanged()
                Toast.show(L("Đã đổi nền lời"))
            } else {
                Toast.show(L("Không lưu được ảnh"))
            }
            BackdropPhotoPicker.active = nil
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { BackdropPhotoPicker.active = nil }
    }
}

/// Bảng chọn màu của iOS 14+ (iOS cũ hơn chỉ dùng các màu có sẵn trong menu).
@available(iOS 14.0, *)
final class BackdropColorPicker: NSObject, UIColorPickerViewControllerDelegate {
    private static var active: BackdropColorPicker?

    static func present(from vc: UIViewController) {
        let picker = UIColorPickerViewController()
        let helper = BackdropColorPicker()
        active = helper
        picker.delegate = helper
        picker.supportsAlpha = false
        picker.selectedColor = AppSettings.lyricBackdropColor
        vc.present(picker, animated: true, completion: nil)
    }

    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        AppSettings.lyricBackdropColor = viewController.selectedColor
        AppSettings.lyricBackdropStyle = .color
        BackdropStore.notifyChanged()
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        BackdropColorPicker.active = nil
    }
}

/// Lớp nền phủ lên màu chuyển động theo bìa khi người dùng chọn nền khác (đen / màu / ảnh).
final class LyricsBackdropView: UIView {
    private let gradient = CAGradientLayer()
    private let photo = UIImageView()
    private let shade = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = UIColor(white: 0.02, alpha: 1)
        gradient.startPoint = CGPoint(x: 0.15, y: 0)
        gradient.endPoint = CGPoint(x: 0.85, y: 1)
        layer.addSublayer(gradient)
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        addSubview(photo)
        shade.backgroundColor = UIColor(white: 0, alpha: 0.38)   // giữ chữ trắng đọc rõ trên mọi ảnh
        addSubview(shade)
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        photo.frame = bounds
        shade.frame = bounds
    }

    func reload() {
        let style = AppSettings.lyricBackdropStyle
        isHidden = style == .artwork
        gradient.isHidden = true
        photo.isHidden = true
        photo.image = nil
        shade.isHidden = true
        switch style {
        case .artwork, .black:
            break
        case .color:
            let base = AppSettings.lyricBackdropColor
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradient.colors = [base.backdropScaled(0.95).cgColor, base.backdropScaled(0.28).cgColor]
            gradient.isHidden = false
            CATransaction.commit()
        case .photo:
            if let image = BackdropStore.load() {
                photo.image = image
                photo.isHidden = false
                shade.isHidden = false
            }   // chưa có ảnh thì hiện nền đen
        }
    }
}

/// Hiệu ứng những đốm sáng lấp lánh trôi nhẹ trên nền lời (giống video lyric).
final class StarFieldView: UIView {
    private static let dotImage: CGImage? = StarFieldView.makeDot()

    private var running = false
    private var builtSize = CGSize.zero
    private var builtLevel = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != builtSize { rebuild() }
    }

    /// Bật / tắt chạy (tắt thì gỡ hết hoạt ảnh để không tốn pin khi ở màn hình bìa).
    func setRunning(_ on: Bool) {
        guard on != running else { return }
        running = on
        rebuild()
    }

    /// Đọc lại mức sao từ cài đặt.
    func apply() {
        if AppSettings.starLevel != builtLevel { rebuild() }
    }

    private func clear() {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    private func rebuild() {
        clear()
        builtSize = bounds.size
        builtLevel = AppSettings.starLevel
        guard running, builtLevel > 0, bounds.width > 10, bounds.height > 10,
              let dot = StarFieldView.dotImage else { return }
        let level = CGFloat(builtLevel) / 100
        let count = max(8, Int(level * 80))
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for _ in 0..<count {
            let size: CGFloat = CGFloat.random(in: 3...9)   // chỉ là đốm sáng tròn, không có hình ngôi sao
            let star = CALayer()
            star.contents = dot
            star.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            let x = CGFloat.random(in: 0...bounds.width)
            let y = CGFloat.random(in: 0...bounds.height)
            star.position = CGPoint(x: x, y: y)
            star.opacity = 0
            let life = Double.random(in: 2.6...6.5)

            let twinkle = CAKeyframeAnimation(keyPath: "opacity")
            twinkle.values = [0, 1, 0.3, 1, 0]
            twinkle.keyTimes = [0, 0.22, 0.5, 0.78, 1]
            twinkle.duration = life
            twinkle.repeatCount = .infinity
            twinkle.beginTime = now + Double.random(in: 0...life)
            star.add(twinkle, forKey: "twinkle")

            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.65
            pulse.toValue = 1.15
            pulse.duration = life / 2
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            star.add(pulse, forKey: "pulse")

            let drift = CABasicAnimation(keyPath: "position.y")
            drift.fromValue = y
            drift.toValue = y - CGFloat.random(in: 14...48)
            drift.duration = Double.random(in: 7...14)
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            star.add(drift, forKey: "drift")

            layer.addSublayer(star)
        }
        CATransaction.commit()
    }

    /// Đốm tròn sáng, mép mềm.
    private static func makeDot() -> CGImage? {
        let s: CGFloat = 32
        let image = UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            let colors = [UIColor(white: 1, alpha: 1).cgColor,
                          UIColor(white: 1, alpha: 0.4).cgColor,
                          UIColor(white: 1, alpha: 0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.25, 1]) else { return }
            let c = CGPoint(x: s / 2, y: s / 2)
            ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: s / 2, options: [])
        }
        return image.cgImage
    }
}
