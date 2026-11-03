import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers
import UIKit

enum VideoImportError: LocalizedError {
    case tooLarge, unsupported
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "Choose a video smaller than 500 MB."
        case .unsupported: return "Choose a playable local video without copy protection, such as an MP4 or MOV."
        }
    }
}

/// Owns only a copy created by Cod. Neither playback cleanup nor a history
/// deletion may remove the user's original Photos or Files item.
final class VideoReference: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let duration: TimeInterval
    let poster: UIImage
    private init(url: URL, name: String, duration: TimeInterval, poster: UIImage) {
        self.url = url; self.name = name; self.duration = duration; self.poster = poster
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    static func copy(from source: URL) async throws -> VideoReference {
        try Task.checkCancellation()
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let url = try copyFile(from: source)
        do {
            try Task.checkCancellation()
            let reference = try await openOwned(url, name: source.deletingPathExtension().lastPathComponent)
            try Task.checkCancellation()
            return reference
        }
        catch { try? FileManager.default.removeItem(at: url); throw error }
    }

    static func copyFile(from source: URL) throws -> URL {
        guard source.isFileURL else { throw VideoImportError.unsupported }
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        let size = values.fileSize ?? 0
        guard values.isRegularFile == true, size > 0 else { throw VideoImportError.unsupported }
        guard size <= 500 * 1_024 * 1_024 else { throw VideoImportError.tooLarge }
        let directory = try TemporaryMedia.directory(.imports)
        let ext = source.pathExtension.lowercased()
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(["mp4", "mov", "m4v"].contains(ext) ? ext : "mov")
        do { try FileManager.default.copyItem(at: source, to: destination) }
        catch { try? FileManager.default.removeItem(at: destination); throw error }
        return destination
    }

    static func openOwned(_ url: URL, name: String = "Video") async throws -> VideoReference {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), try await !asset.load(.hasProtectedContent),
              !(try await asset.loadTracks(withMediaType: .video)).isEmpty else { throw VideoImportError.unsupported }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw VideoImportError.unsupported }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_200, height: 1_200)
        let (image, _) = try await generator.image(at: .zero)
        return VideoReference(url: url, name: name, duration: duration, poster: UIImage(cgImage: image))
    }
}

struct PickedVideo: Transferable {
    let reference: VideoReference
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let reference = try await VideoReference.copy(from: received.file)
            return PickedVideo(reference: reference)
        }
    }
}
