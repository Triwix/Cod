import Foundation
import UIKit

/// One latest-image request, not a user-managed inbox. Claims are persisted
/// before starting PiP so scene changes, restoration and app restarts can't
/// repeatedly float an old image. New shares supersede earlier requests.
final class QuickFloatHandoff {
    static let shared = QuickFloatHandoff()
    enum Mode: String, Codable { case float, crop }
    private enum State: String, Codable { case pending, claimed, retry }
    struct Payload {
        let id: UUID
        let image: UIImage
        let mode: Mode
        let createdAt: Date
        /// Shared text rendered to an image. Text cards are a Pro feature,
        /// so the app checks before floating; the extension can't.
        var isText = false
    }
    private struct Record: Codable {
        let id: UUID
        let png: Data
        let mode: Mode
        let createdAt: Date
        var state: State
        /// Missing in records written before build 34.
        var isText: Bool?
    }
    private let container: () -> URL?
    init(container: @escaping () -> URL? = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "CodAppGroup") as? String,
              group.hasPrefix("group."), !group.contains("$(") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }) { self.container = container }

    @discardableResult
    func store(_ image: UIImage, mode: Mode = .float, isText: Bool = false, now: Date = Date()) throws -> UUID {
        guard let encoded = Self.encoded(image) else { throw SharedImageInbox.InboxError.tooLarge }
        let record = Record(id: UUID(), png: encoded, mode: mode, createdAt: now, state: .pending,
                            isText: isText ? true : nil)
        try coordinate { url in try self.write(record, to: url) }
        CodDiagnosticLog.record("quick share stored id=\(record.id) bytes=\(encoded.count) mode=\(mode)")
        return record.id
    }

    /// PNG keeps screenshots lossless. A detailed photo can exceed the size
    /// limit as PNG, so fall back to high-quality JPEG rather than failing.
    static func encoded(_ image: UIImage, maximumBytes: Int = SharedImageInbox.maximumImageBytes) -> Data? {
        if let png = image.pngData(), png.count <= maximumBytes { return png }
        guard let jpeg = image.jpegData(compressionQuality: 0.92), jpeg.count <= maximumBytes else { return nil }
        return jpeg
    }

    /// A delayed ordinary app launch shouldn't unexpectedly float an old
    /// share. After five minutes it becomes an explicit retry, not auto-play.
    func claim(now: Date = Date(), maximumAge: TimeInterval = 300, expectedID: UUID? = nil) throws -> Payload? {
        try coordinate { url in
            guard var record = try self.read(url), record.state == .pending else { return nil }
            guard expectedID == nil || record.id == expectedID else { return nil }
            guard now.timeIntervalSince(record.createdAt) >= -5,
                  now.timeIntervalSince(record.createdAt) <= maximumAge else {
                record.state = .retry
                try self.write(record, to: url)
                return nil
            }
            // Even a corrupt record must not loop on every activation.
            record.state = .claimed
            try self.write(record, to: url)
            return try self.payload(record)
        }
    }

    func retry() throws -> Payload? {
        try coordinate { url in
            guard var record = try self.read(url) else { return nil }
            record.state = .claimed
            try self.write(record, to: url)
            return try self.payload(record)
        }
    }

    /// A notification tap is an explicit request for this exact saved image,
    /// unlike ordinary activation. It can resume an older or failed request,
    /// but never a newer image or one that is already being processed.
    func claimNotification(_ id: UUID) throws -> Payload? {
        try coordinate { url in
            guard var record = try self.read(url), record.id == id,
                  record.state != .claimed else { return nil }
            record.state = .claimed
            try self.write(record, to: url)
            return try self.payload(record)
        }
    }

    func preview() throws -> Payload? {
        try coordinate { url in
            guard let record = try self.read(url) else { return nil }
            return try self.payload(record)
        }
    }

    func deferAutomaticStart() throws {
        try coordinate { url in
            guard var record = try self.read(url), record.state == .pending else { return }
            record.state = .retry
            try self.write(record, to: url)
        }
    }

    func finish(_ id: UUID, success: Bool) throws {
        try coordinate { url in
            guard var record = try self.read(url), record.id == id else { return }
            if success { try FileManager.default.removeItem(at: url) }
            else { record.state = .retry; try self.write(record, to: url) }
        }
    }

    func discard() throws {
        try coordinate { url in
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    private func payload(_ record: Record) throws -> Payload {
        guard let image = UIImage(data: record.png) else { throw SharedImageInbox.InboxError.unreadable }
        return Payload(id: record.id, image: image, mode: record.mode, createdAt: record.createdAt,
                       isText: record.isText ?? false)
    }
    private func read(_ url: URL) throws -> Record? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= SharedImageInbox.maximumImageBytes + 4_096 else { throw SharedImageInbox.InboxError.tooLarge }
        return try PropertyListDecoder().decode(Record.self, from: Data(contentsOf: url))
    }
    private func write(_ record: Record, to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(record).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func coordinate<T>(_ operation: (URL) throws -> T) throws -> T {
        guard let root = container() else { throw SharedImageInbox.InboxError.unavailable }
        var directory = root.appendingPathComponent("Quick Float", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        var error: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(writingItemAt: directory, options: [], error: &error) { coordinated in
            result = Result { try operation(coordinated.appendingPathComponent("request.plist")) }
        }
        if let error { throw error }
        guard let result else { throw SharedImageInbox.InboxError.unavailable }
        return try result.get()
    }
}

extension Notification.Name {
    static let codQuickFloatRequested = Notification.Name("com.josh.cod.quick-float-requested")
}
