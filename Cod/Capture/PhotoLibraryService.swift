import Photos
import UIKit

enum PhotoLibraryService {
    enum SaveDestination: Equatable {
        case library
        case album(String)
    }

    enum ServiceError: LocalizedError {
        case denied
        case noScreenshots
        case imageUnavailable
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .denied: return "Allow Photos access for Cod in iPhone Settings, or use Choose Photo without granting library access."
            case .noScreenshots: return "No accessible screenshots found. Take a screenshot and let it save to Photos. With Limited Access, include that screenshot in your allowed photos."
            case .imageUnavailable: return "This screenshot couldn't be loaded. Open it in Photos, let it finish downloading, then try again."
            case let .saveFailed(reason): return reason
            }
        }
    }

    // MARK: - Authorization

    @discardableResult
    static func requestAccess(for level: PHAccessLevel = .readWrite) async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: level)
        guard current == .notDetermined else { return current }
        return await PHPhotoLibrary.requestAuthorization(for: level)
    }

    static func isAuthorized(for level: PHAccessLevel = .readWrite) -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: level)
        return status == .authorized || status == .limited
    }

    // MARK: - Saving

    @discardableResult
    static func save(_ image: UIImage, toAlbumNamed albumName: String?) async throws -> SaveDestination {
        let status = await requestAccess(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ServiceError.denied }

        let requestedAlbum = albumName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let album: PHAssetCollection?
        // Limited and add-only access cannot fetch user albums. Saving to the
        // main library still works, so preserve the user's image and let the
        // caller explain the fallback instead of failing the entire action.
        if let requestedAlbum, !requestedAlbum.isEmpty,
           PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized {
            album = try await findOrCreateAlbum(named: requestedAlbum)
        } else {
            album = nil
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                if let album,
                   let placeholder = request.placeholderForCreatedAsset,
                   let albumRequest = PHAssetCollectionChangeRequest(for: album) {
                    albumRequest.addAssets([placeholder] as NSArray)
                }
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.saveFailed(error?.localizedDescription ?? "Photos refused the write."))
                }
            }
        }

        if let album {
            return .album(album.localizedTitle ?? requestedAlbum ?? "Cod")
        }
        return .library
    }

    private static func findOrCreateAlbum(named name: String) async throws -> PHAssetCollection {
        if let existing = album(named: name) { return existing }

        var identifier: String?
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                identifier = request.placeholderForCreatedAssetCollection.localIdentifier
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.saveFailed(error?.localizedDescription ?? "Couldn't create the album."))
                }
            }
        }

        if let identifier,
           let created = PHAssetCollection.fetchAssetCollections(
               withLocalIdentifiers: [identifier], options: nil
           ).firstObject {
            return created
        }
        guard let fallback = album(named: name) else {
            throw ServiceError.saveFailed("Couldn't open the \(name) album.")
        }
        return fallback
    }

    private static func album(named name: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "localizedTitle = %@", name)
        return PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: options
        ).firstObject
    }

    // MARK: - Reading screenshots

    struct ScreenshotHit {
        var image: UIImage
        var localIdentifier: String
    }

    /// The most recent item in the system Screenshots album.
    static func latestScreenshot() async throws -> ScreenshotHit {
        let status = await requestAccess(for: .readWrite)
        guard status == .authorized || status == .limited else { throw ServiceError.denied }

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil
        )

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1

        var asset: PHAsset?
        if let screenshots = collections.firstObject {
            asset = PHAsset.fetchAssets(in: screenshots, options: options).firstObject
        }
        if asset == nil {
            // Limited-access libraries don't expose smart albums. Search only
            // the accessible assets that are actually screenshots; returning
            // the newest arbitrary photo can surface something unintended.
            options.predicate = NSPredicate(
                format: "(mediaSubtype & %d) != 0",
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
            asset = PHAsset.fetchAssets(with: .image, options: options).firstObject
        }
        guard let asset else { throw ServiceError.noScreenshots }

        let image = try await requestImage(for: asset)
        return ScreenshotHit(
            image: image,
            localIdentifier: asset.localIdentifier
        )
    }

    static func requestImage(for asset: PHAsset) async throws -> UIImage {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // Photos can call back twice (degraded, then full). Ignore the
                // degraded pass and only resume once.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !resumed, !isDegraded else { return }
                if let image {
                    resumed = true
                    continuation.resume(returning: image.normalizedUp())
                } else {
                    // A final nil result can have no error dictionary. Always
                    // finish it instead of leaving the UI waiting forever.
                    resumed = true
                    continuation.resume(throwing: ServiceError.imageUnavailable)
                }
            }
        }
    }
}
