import UIKit

extension Notification.Name {
    /// Ảnh bìa tự chọn của một bài vừa đổi / bị xoá. userInfo["videoId"] cho biết bài nào.
    static let customArtworkChanged = Notification.Name("MochyiOSCustomArtworkChanged")
}

/// Ảnh bìa do người dùng tự chọn cho BẤT KỲ bài nào (bài YouTube hay nhạc nhập từ máy).
/// Lưu ở Documents/CustomArtwork/<tên-an-toàn>.jpg và luôn được ưu tiên hơn ảnh gốc của bài.
enum CustomArtworkStore {
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CustomArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    /// Tên tệp (không đuôi). Dùng chung cách mã hoá chữ hoa với lời tự tạo để hai mã khác hoa/thường không đè nhau.
    static func baseName(for videoId: String) -> String {
        let lrc = CustomLyricsStore.fileName(for: videoId)
        return String(lrc.dropLast(4))
    }

    static func file(forBaseName name: String) -> URL {
        return directory.appendingPathComponent(name + ".jpg")
    }

    static func fileURL(videoId: String) -> URL {
        return file(forBaseName: baseName(for: videoId))
    }

    static func exists(videoId: String) -> Bool {
        return FileManager.default.fileExists(atPath: fileURL(videoId: videoId).path)
    }

    /// URL dạng mochylocal://custom/<tên>?t=<thời điểm sửa>. Phần ?t= làm bộ nhớ đệm ảnh tự làm mới khi đổi ảnh.
    static func url(for videoId: String) -> URL? {
        let file = fileURL(videoId: videoId)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) else { return nil }
        let stamp = Int(((attributes[.modificationDate] as? Date) ?? Date()).timeIntervalSince1970)
        return URL(string: "\(LocalMusicStore.artworkScheme)://custom/\(baseName(for: videoId))?t=\(stamp)")
    }

    /// Thu nhỏ (tối đa 1000px) rồi lưu JPEG.
    static func save(_ image: UIImage, videoId: String) -> Bool {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return false }
        var target = image.size
        if longest > 1000 {
            let ratio = 1000 / longest
            target = CGSize(width: floor(image.size.width * ratio), height: floor(image.size.height * ratio))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.88),
              (try? data.write(to: fileURL(videoId: videoId), options: .atomic)) != nil else { return false }
        changed(videoId)
        return true
    }

    static func delete(videoId: String) {
        let existed = exists(videoId: videoId)
        try? FileManager.default.removeItem(at: fileURL(videoId: videoId))
        if existed { changed(videoId) }
    }

    private static func changed(_ videoId: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .customArtworkChanged, object: nil, userInfo: ["videoId": videoId])
            NotificationCenter.default.post(name: .libraryChanged, object: nil)   // để các danh sách vẽ lại ảnh
        }
    }
}

/// Chọn ảnh từ thư viện ảnh (có khung cắt vuông) để làm ảnh bìa của một bài.
final class CustomArtworkPicker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private static var active: CustomArtworkPicker?
    private let song: Song

    private init(song: Song) {
        self.song = song
    }

    /// Hiện menu: chọn ảnh mới / xoá ảnh tự chọn.
    static func present(for song: Song, from vc: UIViewController) {
        let sheet = UIAlertController(title: L("Ảnh bìa bài hát"), message: song.title, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L("Chọn ảnh từ thư viện…"), style: .default) { _ in
            guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
                Toast.show(L("Không mở được thư viện ảnh"))
                return
            }
            let picker = UIImagePickerController()
            let helper = CustomArtworkPicker(song: song)
            active = helper
            picker.sourceType = .photoLibrary
            picker.allowsEditing = true      // khung cắt vuông
            picker.delegate = helper
            vc.present(picker, animated: true, completion: nil)
        })
        if CustomArtworkStore.exists(videoId: song.videoId) {
            sheet.addAction(UIAlertAction(title: L("Dùng lại ảnh bìa gốc"), style: .destructive) { _ in
                CustomArtworkStore.delete(videoId: song.videoId)
                Toast.show(L("Đã khôi phục ảnh bìa gốc"))
            })
        }
        sheet.addAction(UIAlertAction(title: L("Đóng"), style: .cancel, handler: nil))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = vc.view
            popover.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        vc.present(sheet, animated: true, completion: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true) { [song] in
            if let image = image, CustomArtworkStore.save(image, videoId: song.videoId) {
                Toast.show(L("Đã đổi ảnh bìa"))
            } else {
                Toast.show(L("Không lưu được ảnh"))
            }
            CustomArtworkPicker.active = nil
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { CustomArtworkPicker.active = nil }
    }
}
