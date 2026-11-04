import Combine
import UIKit
import WidgetKit

/// Disk-backed history of captures. Images are written as PNG (lossless — these
/// are screenshots, not photographs) with a small JPEG thumbnail alongside so
/// the library grid never has to decode a full-resolution screenshot.
final class SnapStore: ObservableObject {
    static let shared = SnapStore()

    @Published private(set) var snaps: [Snap] = []
    @Published private(set) var storageIssue: String?
    private var indexNeedsRecovery = false
    private var lastPublishedFavorites: [SavedReferenceSummary]?

    enum StorageError: LocalizedError {
        case damagedIndex, encoding
        var errorDescription: String? {
            switch self {
            case .damagedIndex: return "Cod couldn't read the Library index. Existing files are unchanged and Library edits are paused. Try loading it again or reopen Cod. Delete Everything can reset it, but only choose that if you want to remove all saved Library items."
            case .encoding: return "Cod couldn't encode this Library image."
            }
        }
    }

    private let root: URL
    private let indexURL: URL
    private let fileManager = FileManager.default
    private let imageCache = NSCache<NSString, UIImage>()
    private let ioQueue = DispatchQueue(label: "com.josh.cod.snapstore", qos: .userInitiated)
    private var historyGeneration = 0
    private let publishesFavorites: Bool

    init(directoryName: String = "Snaps", baseDirectory: URL? = nil) {
        publishesFavorites = baseDirectory == nil && directoryName == "Snaps"
        let base = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent(directoryName, isDirectory: true)
        indexURL = root.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        imageCache.totalCostLimit = 64 * 1024 * 1024
        imageCache.countLimit = 24
        load()
        if publishesFavorites, !indexNeedsRecovery { publishFavorites() }
    }

    // MARK: - Reading

    func image(for snap: Snap) -> UIImage? {
        cachedImage(named: snap.imageFilename)
    }

    func thumbnail(for snap: Snap) -> UIImage? {
        if let cached = imageCache.object(forKey: snap.thumbnailFilename as NSString) { return cached }
        // A missing thumbnail must not decode the full original in the grid.
        let thumbnail = UIImage.decodedImage(at: root.appendingPathComponent(snap.thumbnailFilename), maximumEdge: 400)
            ?? UIImage.decodedImage(at: root.appendingPathComponent(snap.imageFilename), maximumEdge: 400)
        if let thumbnail {
            imageCache.setObject(thumbnail, forKey: snap.thumbnailFilename as NSString, cost: Self.decodedMemoryCost(thumbnail))
        }
        return thumbnail
    }

    func videoURL(for snap: Snap) -> URL? {
        snap.videoFilename.map { root.appendingPathComponent($0) }
    }

    @discardableResult
    @MainActor func add(video: VideoReference, limit: HistoryLimit) async throws -> Snap? {
        guard limit != .off else { return nil }
        guard !indexNeedsRecovery else { throw StorageError.damagedIndex }
        var snap = Snap(pixelWidth: Int(video.poster.pixelSize.width), pixelHeight: Int(video.poster.pixelSize.height), origin: .imported)
        snap.videoExtension = video.url.pathExtension
        guard let filename = snap.videoFilename else { throw VideoImportError.unsupported }
        let generation = historyGeneration
        let source = video.url
        let destination = root.appendingPathComponent(filename)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ioQueue.async {
                do { try FileManager.default.copyItem(at: source, to: destination); continuation.resume() }
                catch {
                    try? FileManager.default.removeItem(at: destination)
                    continuation.resume(throwing: error)
                }
            }
        }
        guard generation == historyGeneration else {
            try? fileManager.removeItem(at: destination)
            throw CancellationError()
        }
        write(image: video.poster, for: snap)
        snaps.insert(snap, at: 0)
        trim(to: limit, persist: false)
        persistIndex()
        return snap
    }

    private func cachedImage(named filename: String) -> UIImage? {
        if let hit = imageCache.object(forKey: filename as NSString) { return hit }
        let url = root.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: filename as NSString, cost: Self.decodedMemoryCost(image))
        return image
    }

    /// PNG/JPEG byte counts can be tiny for a large screenshot. Account for
    /// decoded pixels, including newly saved images, rather than compressed data.
    static func decodedMemoryCost(_ image: UIImage) -> Int {
        if let bitmap = image.cgImage {
            let (bytes, overflow) = bitmap.bytesPerRow.multipliedReportingOverflow(by: bitmap.height)
            return overflow ? Int.max : max(1, bytes)
        }
        let bytes = Double(image.size.width) * Double(image.size.height) * pow(Double(image.scale), 2) * 4
        guard bytes.isFinite, bytes >= 0, bytes < Double(Int.max) else { return Int.max }
        return max(1, Int(bytes.rounded(.up)))
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

        guard !indexNeedsRecovery else { return snap }

        write(image: image, for: snap)
        snaps.insert(snap, at: 0)
        trim(to: limit, persist: false)
        persistIndex()
        return snap
    }

    func update(_ snap: Snap) {
        guard !indexNeedsRecovery else { return }
        guard let index = snaps.firstIndex(where: { $0.id == snap.id }) else { return }
        snaps[index] = snap
        persistIndex()
    }

    func setRecognizedText(_ text: String?, for snapID: Snap.ID) {
        guard !indexNeedsRecovery else { return }
        guard let index = snaps.firstIndex(where: { $0.id == snapID }) else { return }
        snaps[index].recognizedText = text
        persistIndex()
    }

    func toggleFavorite(_ id: Snap.ID) {
        guard !indexNeedsRecovery else { return }
        guard let index = snaps.firstIndex(where: { $0.id == id }) else { return }
        snaps[index].isFavorite.toggle()
        snaps[index].favoriteOrder = snaps[index].isFavorite
            ? (snaps.compactMap(\.favoriteOrder).max() ?? -1) + 1 : nil
        persistIndex()
    }

    var favorites: [Snap] {
        snaps.filter(\.isFavorite).sorted {
            if $0.favoriteOrder != $1.favoriteOrder { return ($0.favoriteOrder ?? 0) < ($1.favoriteOrder ?? 0) }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var historyCount: Int { snaps.filter { !$0.isFavorite }.count }
    var canRetryLoading: Bool { indexNeedsRecovery }

    func retryLoading() {
        guard indexNeedsRecovery else { return }
        indexNeedsRecovery = false
        storageIssue = nil
        load()
        if publishesFavorites, !indexNeedsRecovery { publishFavorites() }
    }

    /// Favorites are deliberate saves, independent of automatic history.
    func clearHistory() {
        guard !indexNeedsRecovery else { return }
        historyGeneration += 1
        let doomed = snaps.filter { !$0.isFavorite }
        snaps.removeAll { !$0.isFavorite }
        doomed.forEach(removeFiles(for:))
        persistIndex()
    }

    func delete(_ snap: Snap) {
        guard !indexNeedsRecovery else { return }
        snaps.removeAll { $0.id == snap.id }
        removeFiles(for: snap)
        persistIndex()
    }

    func clear() {
        historyGeneration += 1
        indexNeedsRecovery = false
        storageIssue = nil
        let doomed = snaps
        snaps.removeAll()
        doomed.forEach(removeFiles(for:))
        persistIndex()
        // Explicit full deletion also removes recognized orphaned payloads left
        // by an interrupted save. Never remove unknown files or subdirectories.
        let directory = root
        let generation = historyGeneration
        ioQueue.async { [weak self] in
            do {
                let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
                for file in files {
                    let name = file.lastPathComponent
                    let owned = OwnedMediaFile.matches(name, extensions: ["png", "mp4", "mov", "m4v"])
                        || OwnedMediaFile.matches(name, extensions: ["jpg"], suffix: "-thumb")
                    guard owned, (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
                    try FileManager.default.removeItem(at: file)
                }
            } catch { self?.reportStorageFailure(generation: generation) }
        }
    }

    /// The history cap applies to non-favorites only, including when Off.
    func trim(to limit: HistoryLimit, persist: Bool = true) {
        guard !indexNeedsRecovery else { return }
        if persist { historyGeneration += 1 }
        let keep: Int
        switch limit {
        case .unlimited: return
        case .off: keep = 0
        default: keep = limit.rawValue
        }
        var remaining = keep
        let doomed = snaps.filter { snap in
            if snap.isFavorite { return false }
            if remaining > 0 { remaining -= 1; return false }
            return true
        }
        guard !doomed.isEmpty else { return }
        let removed = Set(doomed.map(\.id))
        snaps.removeAll { removed.contains($0.id) }
        doomed.forEach(removeFiles(for:))
        if persist { persistIndex() }
    }

    /// Queue behind pending saves/removals and keep directory enumeration out
    /// of SwiftUI's body. Callers discard cancelled/stale view tasks.
    func diskUsage() async -> Int64 {
        let root = root
        return await withCheckedContinuation { continuation in
            ioQueue.async {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: [.fileSizeKey]
                )) ?? []
                let bytes = contents.reduce(into: Int64(0)) { total, url in
                    total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
                continuation.resume(returning: bytes)
            }
        }
    }

    // MARK: - Persistence

    private func write(image: UIImage, for snap: Snap) {
        imageCache.setObject(image, forKey: snap.imageFilename as NSString, cost: Self.decodedMemoryCost(image))
        let thumb = image.fitted(within: CGSize(width: 400, height: 400))
        imageCache.setObject(thumb, forKey: snap.thumbnailFilename as NSString, cost: Self.decodedMemoryCost(thumb))

        let imageURL = root.appendingPathComponent(snap.imageFilename)
        let thumbURL = root.appendingPathComponent(snap.thumbnailFilename)
        let generation = historyGeneration
        ioQueue.async { [weak self] in
            do {
                guard let data = image.pngData(), let thumbnail = thumb.jpegData(compressionQuality: 0.8) else { throw StorageError.encoding }
                try data.write(to: imageURL, options: .atomic)
                try thumbnail.write(to: thumbURL, options: .atomic)
            } catch { self?.reportStorageFailure(generation: generation) }
        }
    }

    private func removeFiles(for snap: Snap) {
        imageCache.removeObject(forKey: snap.imageFilename as NSString)
        imageCache.removeObject(forKey: snap.thumbnailFilename as NSString)
        var urls = [
            root.appendingPathComponent(snap.imageFilename),
            root.appendingPathComponent(snap.thumbnailFilename),
        ]
        if let video = videoURL(for: snap) { urls.append(video) }
        let generation = historyGeneration
        ioQueue.async { [weak self] in
            for url in urls where FileManager.default.fileExists(atPath: url.path) {
                do { try FileManager.default.removeItem(at: url) }
                catch { self?.reportStorageFailure(generation: generation) }
            }
        }
    }

    private func persistIndex() {
        guard !indexNeedsRecovery else { return }
        if publishesFavorites { publishFavorites() }
        let snapshot = snaps
        let url = indexURL
        let generation = historyGeneration
        ioQueue.async { [weak self] in
            do { try JSONEncoder().encode(snapshot).write(to: url, options: .atomic) }
            catch { self?.reportStorageFailure(generation: generation) }
        }
    }

    private func publishFavorites() {
        let entries = favorites.map {
            SavedReferenceSummary(id: $0.id, name: "\($0.isVideo ? "Video" : "Image") · \($0.createdAt.formatted(date: .abbreviated, time: .shortened))", detail: "Library favorite")
        }
        guard entries != lastPublishedFavorites else { return }
        do {
            try SavedReferenceCatalog.publishFavorites(entries)
            lastPublishedFavorites = entries
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
        } catch { CodDiagnosticLog.record("Couldn't refresh favorite controls: \(error.localizedDescription)") }
    }

    private func load() {
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        let decoded: [Snap]
        do { decoded = try JSONDecoder().decode([Snap].self, from: Data(contentsOf: indexURL)) }
        catch {
            indexNeedsRecovery = true
            storageIssue = StorageError.damagedIndex.localizedDescription
            return
        }
        // Drop entries whose backing file vanished (e.g. a restore or a crash
        // between the index write and the image write).
        snaps = decoded.filter {
            fileManager.fileExists(atPath: root.appendingPathComponent($0.imageFilename).path)
            && (!$0.isVideo || videoURL(for: $0).map { fileManager.fileExists(atPath: $0.path) } == true)
        }
        // Existing favorites get a stable order once, without losing either
        // the saved media or their favorite status. New favorites append.
        var nextOrder = (snaps.compactMap(\.favoriteOrder).max() ?? -1) + 1
        var migrated = false
        for index in snaps.indices.reversed() where snaps[index].isFavorite && snaps[index].favoriteOrder == nil {
            snaps[index].favoriteOrder = nextOrder
            nextOrder += 1
            migrated = true
        }
        if migrated { persistIndex() }
    }

    /// Test/support hook for callers that need a durable snapshot before
    /// inspecting the store. Production writes remain asynchronous.
    func waitForPendingWrites() {
        ioQueue.sync {}
    }

    private func reportStorageFailure(generation: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.historyGeneration else { return }
            self.storageIssue = "Some Library changes couldn't be saved or removed. Check available device storage and try again. Don't rely on a new Library item until it is available after reopening Cod. Originals in Photos and Files are unchanged."
        }
    }
}
