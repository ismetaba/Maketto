import Foundation
import Observation
import UIKit

/// The user's own catalog pieces (name, size, optional photo), persisted as a
/// small JSON file next to the store. Built-in presets live in
/// `FurnitureCatalog` and are never written here.
@MainActor
@Observable
final class FurnitureLibrary {
    private(set) var custom: [FurnitureTemplate] = []
    private let fileURL: URL?

    /// `fileURL == nil` keeps the library in memory only (previews, tests).
    init(fileURL: URL? = FurnitureLibrary.defaultURL) {
        self.fileURL = fileURL
        load()
    }

    nonisolated static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "FurnitureLibrary.json")
    }

    func template(id: String) -> FurnitureTemplate? {
        custom.first { $0.id == id } ?? FurnitureCatalog.presets.first { $0.id == id }
    }

    /// Add a new custom piece. Returns false if it could not be saved.
    @discardableResult
    func add(name: String, category: FurnitureCategory, shape: FurnitureShape,
             width: Double, depth: Double, height: Double, photoID: String?) -> FurnitureTemplate? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = FurnitureTemplate(
            id: "custom.\(UUID().uuidString)",
            name: trimmed.isEmpty ? category.displayName : String(trimmed.prefix(40)),
            category: category, shape: shape,
            width: Self.clamp(width), depth: Self.clamp(depth),
            height: min(max(height, 0.005), 6),
            armDepth: shape == .lShape ? min(0.95, min(width, depth) * 0.45) : nil,
            photoID: photoID, isCustom: true
        )
        custom.insert(template, at: 0)
        guard persist() else {
            custom.removeAll { $0.id == template.id }
            return nil
        }
        return template
    }

    /// Photos the catalog itself still uses.
    var photoIDs: Set<String> { Set(custom.compactMap(\.photoID)) }

    /// Remove a custom piece. Returns its photo id (the file is left for the
    /// launch-time sweep, since placed pieces may still show it).
    @discardableResult
    func delete(id: String) -> String? {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = custom.remove(at: index)
        if !persist() { custom.insert(removed, at: index); return nil }
        return removed.photoID
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0.05), 20) }

    // MARK: - Persistence

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        custom = (try? JSONDecoder().decode([FurnitureTemplate].self, from: data)) ?? []
    }

    private func persist() -> Bool {
        guard let fileURL else { return true }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(custom).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// JPEG photos of custom furniture, stored as files (never inside the store).
@MainActor
enum FurniturePhotoStore {
    private static let cache = NSCache<NSString, UIImage>()

    static var directory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "FurniturePhotos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for id: String) -> URL { directory.appending(path: id) }

    /// Downscale (longest side ≤ 1024 px), JPEG-encode and store. Returns the
    /// new photo id, or nil on failure.
    static func save(_ image: UIImage) -> String? {
        let scaled = downscaled(image, maxSide: 1024)
        guard let data = scaled.jpegData(compressionQuality: 0.82) else { return nil }
        let id = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: url(for: id), options: .atomic)
        } catch {
            return nil
        }
        cache.setObject(scaled, forKey: id as NSString)
        return id
    }

    static func image(for id: String) -> UIImage? {
        if let hit = cache.object(forKey: id as NSString) { return hit }
        guard let image = UIImage(contentsOfFile: url(for: id).path(percentEncoded: false)) else { return nil }
        cache.setObject(image, forKey: id as NSString)
        return image
    }

    static func delete(_ id: String) {
        cache.removeObject(forKey: id as NSString)
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// Delete every stored photo not in `keeping`. Only call when no editor
    /// session can hold unsaved references (i.e. at launch).
    static func removeUnreferenced(keeping: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        for name in files where name.hasSuffix(".jpg") && !keeping.contains(name) {
            delete(name)
        }
    }

    private static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
