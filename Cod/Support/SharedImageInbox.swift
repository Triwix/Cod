import Foundation
import ImageIO
import UIKit

/// Durable, local-only storage shared by the app and its Share extension.
/// No app launch, clipboard access, source-app inspection, or background PiP.
final class SharedImageInbox {
    static let shared = SharedImageInbox()
    static let capacity = 5
    static let maximumImageBytes = 32 * 1_024 * 1_024

    struct Entry: Identifiable {
        let id: UUID
        let receivedAt: Date?
        let thumbnail: UIImage?
    }

    enum InboxError: LocalizedError {
        case unavailable, full, unreadable, tooLarge

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Cod's shared inbox isn't available. The app and Share extension need the same App Group enabled in their signing profiles. You can still choose an image inside Cod."
            case .full:
                return "Cod's inbox is full. Open Cod and remove an image from Shared Images before sharing another."
            case .unreadable:
                return "Cod couldn't read this shared image. Remove it from the inbox and share it again."
            case .tooLarge:
                return "This image is too large to add to Cod's inbox. Try a smaller image."
            }
        }
    }

    private struct Record: Codable {
        let id: UUID
        let receivedAt: Date
        let png: Data
    }

    private let container: () -> URL?
    private let manager = FileManager.default

    /// Inject a dedicated temporary container in tests, never a user directory.
    init(container: @escaping () -> URL? = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "CodAppGroup") as? String,
              group.hasPrefix("group."), !group.contains("$(") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }) {
        self.container = container
    }

    @discardableResult
    func save(_ image: UIImage, receivedAt: Date = Date()) throws -> UUID {
        guard let png = image.pngData() else { throw InboxError.unreadable }
        return try savePNG(png, receivedAt: receivedAt)
    }

    @discardableResult
    func savePNG(_ png: Data, receivedAt: Date = Date()) throws -> UUID {
        guard png.count <= Self.maximumImageBytes else { throw InboxError.tooLarge }
        guard Self.thumbnail(png) != nil else { throw InboxError.unreadable }
        let id = UUID()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(Record(id: id, receivedAt: receivedAt, png: png))
        return try coordinated(write: true) { directory in
            guard try self.recordURLs(in: directory).count < Self.capacity else { throw InboxError.full }
            // One atomic record: readers can never see an image without its
            // metadata. Concurrent share sessions use distinct UUID filenames.
            try data.write(to: self.recordURL(id, in: directory), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return id
        }
    }

    func entries() throws -> [Entry] {
        try coordinated(write: false) { directory in
            try self.recordURLs(in: directory).compactMap { url -> Entry? in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
                // Keep unreadable records visible so the user can remove them.
                let record = try? self.decode(id, in: directory)
                return Entry(id: id, receivedAt: record?.receivedAt, thumbnail: record.flatMap { Self.thumbnail($0.png) })
            }.sorted {
                if $0.receivedAt == $1.receivedAt { return $0.id.uuidString < $1.id.uuidString }
                return ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast)
            }
        }
    }

    func image(for id: UUID) throws -> UIImage {
        try coordinated(write: false) { directory in
            let record = try self.decode(id, in: directory)
            guard let image = UIImage(data: record.png) else { throw InboxError.unreadable }
            return image
        }
    }

    /// Floating/cancelling never deletes the original. Removal is explicit.
    func remove(_ id: UUID) throws {
        try coordinated(write: true) { directory in
            let url = self.recordURL(id, in: directory)
            if self.manager.fileExists(atPath: url.path) { try self.manager.removeItem(at: url) }
        }
    }

    private func decode(_ id: UUID, in directory: URL) throws -> Record {
        let url = recordURL(id, in: directory)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumImageBytes + 4_096,
              let data = try? Data(contentsOf: url),
              let record = try? PropertyListDecoder().decode(Record.self, from: data),
              record.id == id, record.png.count <= Self.maximumImageBytes else { throw InboxError.unreadable }
        return record
    }

    private func recordURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("codimage")
    }

    private func recordURLs(in directory: URL) throws -> [URL] {
        try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter {
            $0.pathExtension == "codimage" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil
        }
    }

    private func coordinated<T>(write: Bool, operation: (URL) throws -> T) throws -> T {
        guard let root = container() else { throw InboxError.unavailable }
        let directory = root.appendingPathComponent("Shared Images", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excludedDirectory = directory
        try excludedDirectory.setResourceValues(values)
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var result: Result<T, Error>?
        let accessor: (URL) -> Void = { coordinatedURL in
            result = Result { try operation(coordinatedURL) }
        }
        if write {
            coordinator.coordinate(writingItemAt: directory, options: [], error: &error, byAccessor: accessor)
        } else {
            coordinator.coordinate(readingItemAt: directory, options: [], error: &error, byAccessor: accessor)
        }
        if let error { throw error }
        guard let result else { throw InboxError.unavailable }
        return try result.get()
    }

    private static func thumbnail(_ png: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(png as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 180,
            ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
