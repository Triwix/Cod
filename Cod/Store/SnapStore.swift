import Combine
import UIKit

/// Disk-backed history of captures. Images are written as PNG (lossless — these
/// are screenshots, not photographs) with a small JPEG thumbnail alongside so
/// the library grid never has to decode a full-resolution screenshot.
final class SnapStore: ObservableObject {
    static let shared = SnapStore()

    @Published private(set) var snaps: [Snap] = []

    private let root: URL
    private let indexURL: URL
    private let fileManager = FileManager.default
    private let imageCache = NSCache<NSString, UIImage>()
    private let ioQueue = DispatchQueue(label: "com.josh.cod.snapstore", qos: .userInitiated)

    init(directoryName: String = "Snaps", baseDirectory: URL? = nil) {
        let base = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent(directoryName, isDirectory: true)
        indexURL = root.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        imageCache.totalCostLimit = 64 * 1024 * 1024
        load()
    }

    // MARK: - Reading

    func image(for snap: Snap) -> UIImage? {
        cachedImage(named: snap.imageFilename)
    }

    func thumbnail(for snap: Snap) -> UIImage? {
        cachedImage(named: snap.thumbnailFilename) ?? image(for: snap)
    }

    private func cachedImage(named filename: String) -> UIImage? {
        if let hit = imageCache.object(forKey: filename as NSString) { return hit }
        let url = root.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: filename as NSString, cost: data.count)
        return image
    }

    // MARK: - Writing

    @discardableResult
    func add(
        image: UIImage,
        origin: Snap.Origin,
        recognizedText: String? = nil,
        barcodes: [String] = [],
        limit: HistoryLimit = AppSettings.shared.historyLimit
    ) -> Snap {
        var snap = Snap(
            pixelWidth: Int(image.size.width * image.scale),
            pixelHeight: Int(image.size.height * image.scale),
            origin: origin
        )
        snap.recognizedText = recognizedText
        snap.barcodes = barcodes

        write(image: image, for: snap)
        snaps.insert(snap, at: 0)
        trim(to: limit, persist: false)
        persistIndex()
        return snap
    }

    func update(_ snap: Snap) {
        guard let index = snaps.firstIndex(where: { $0.id == snap.id }) else { return }
        snaps[index] = snap
        persistIndex()
    }

    func setRecognizedText(_ text: String?, for snapID: Snap.ID) {
        guard let index = snaps.firstIndex(where: { $0.id == snapID }) else { return }
        snaps[index].recognizedText = text
        persistIndex()
    }

    func setBarcodes(_ payloads: [String], for snapID: Snap.ID) {
        guard let index = snaps.firstIndex(where: { $0.id == snapID }) else { return }
        snaps[index].barcodes = payloads
        persistIndex()
    }

    func delete(_ snap: Snap) {
        snaps.removeAll { $0.id == snap.id }
        removeFiles(for: snap)
        persistIndex()
    }

    func delete(ids: Set<Snap.ID>) {
        let doomed = snaps.filter { ids.contains($0.id) }
        snaps.removeAll { ids.contains($0.id) }
        doomed.forEach(removeFiles(for:))
        persistIndex()
    }

    func clear() {
        let doomed = snaps
        snaps.removeAll()
        doomed.forEach(removeFiles(for:))
        persistIndex()
    }

    /// Applies the configured history cap. `.off` keeps nothing on disk — the
    /// snippet you're actively working with is held in memory by the session.
    func trim(to limit: HistoryLimit, persist: Bool = true) {
        let keep: Int
        switch limit {
        case .unlimited: return
        case .off: keep = 0
        default: keep = limit.rawValue
        }
        guard snaps.count > keep else { return }
        let doomed = Array(snaps[keep...])
        snaps = Array(snaps.prefix(keep))
        doomed.forEach(removeFiles(for:))
        if persist { persistIndex() }
    }

    var diskUsage: Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return contents.reduce(into: Int64(0)) { total, url in
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    // MARK: - Persistence

    private func write(image: UIImage, for snap: Snap) {
        imageCache.setObject(image, forKey: snap.imageFilename as NSString)
        let thumb = image.fitted(within: CGSize(width: 400, height: 400))
        imageCache.setObject(thumb, forKey: snap.thumbnailFilename as NSString)

        let imageURL = root.appendingPathComponent(snap.imageFilename)
        let thumbURL = root.appendingPathComponent(snap.thumbnailFilename)
        ioQueue.async {
            if let data = image.pngData() { try? data.write(to: imageURL, options: .atomic) }
            if let data = thumb.jpegData(compressionQuality: 0.8) { try? data.write(to: thumbURL, options: .atomic) }
        }
    }

    private func removeFiles(for snap: Snap) {
        imageCache.removeObject(forKey: snap.imageFilename as NSString)
        imageCache.removeObject(forKey: snap.thumbnailFilename as NSString)
        let urls = [
            root.appendingPathComponent(snap.imageFilename),
            root.appendingPathComponent(snap.thumbnailFilename),
        ]
        ioQueue.async { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
    }

    private func persistIndex() {
        let snapshot = snaps
        let url = indexURL
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Snap].self, from: data)
        else { return }
        // Drop entries whose backing file vanished (e.g. a restore or a crash
        // between the index write and the image write).
        snaps = decoded.filter { fileManager.fileExists(atPath: root.appendingPathComponent($0.imageFilename).path) }
    }

    /// Test/support hook for callers that need a durable snapshot before
    /// inspecting the store. Production writes remain asynchronous.
    func waitForPendingWrites() {
        ioQueue.sync {}
    }
}

extension UIImage {
    /// Aspect-fit resize used for thumbnails. Never upscales.
    func fitted(within bounds: CGSize) -> UIImage {
        let ratio = min(bounds.width / size.width, bounds.height / size.height, 1)
        guard ratio < 1 else { return self }
        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
