@preconcurrency import AVFoundation
import CoreImage

enum VideoRegionCrop {
  /// cancelExport is thread-safe; other configuration stays on the export task.
  private final class Cancellation: @unchecked Sendable {
    let export: AVAssetExportSession
    init(_ export: AVAssetExportSession) { self.export = export }
  }
  /// Normalized, top-left coordinates taken from the oriented poster frame.
  static func crop(_ video: VideoReference, region: CGRect) async throws -> VideoReference {
    try Task.checkCancellation()
    let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
    guard region.minX.isFinite, region.minY.isFinite, region.width.isFinite, region.height.isFinite,
      region.width > 0, region.height > 0, unit.contains(region)
    else { throw VideoImportError.unsupported }
    let asset = AVURLAsset(url: video.url)
    let natural = CGSize(
      width: video.poster.size.width * region.width,
      height: video.poster.size.height * region.height)
    let size = CGSize(
      width: max(16, floor(natural.width / 2) * 2), height: max(16, floor(natural.height / 2) * 2))
    let composition = AVMutableVideoComposition(asset: asset) { request in
      let extent = request.sourceImage.extent
      let crop = CGRect(
        x: extent.minX + extent.width * region.minX,
        y: extent.minY + extent.height * (1 - region.maxY),
        width: extent.width * region.width, height: extent.height * region.height)
      let frame = request.sourceImage.cropped(to: crop)
        .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        .transformed(
          by: CGAffineTransform(scaleX: size.width / crop.width, y: size.height / crop.height))
      request.finish(with: frame, context: nil)
    }
    composition.renderSize = size
    let track = try await asset.loadTracks(withMediaType: .video).first
    let nominalRate = try await track?.load(.nominalFrameRate) ?? 30
    composition.frameDuration = CMTime(
      seconds: 1 / min(60, max(24, Double(nominalRate))), preferredTimescale: 60_000)
    guard
      let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
    else { throw VideoImportError.unsupported }
    export.videoComposition = composition
    export.timeRange = CMTimeRange(
      start: .zero, duration: CMTime(seconds: video.duration, preferredTimescale: 60_000))
    let cancellation = Cancellation(export)
    let url = try TemporaryMedia.directory(.crops).appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")
    do {
      try await withTaskCancellationHandler {
        if #available(iOS 18.0, *) {
          try await export.export(to: url, as: .mp4)
        } else {
          export.outputURL = url
          export.outputFileType = .mp4
          await export.export()
          guard export.status == .completed else {
            throw export.error ?? VideoImportError.unsupported
          }
        }
      } onCancel: {
        cancellation.export.cancelExport()
      }
      try Task.checkCancellation()
      return try await VideoReference.openOwned(url, name: "\(video.name) · Cropped")
    } catch {
      try? FileManager.default.removeItem(at: url)
      throw error
    }
  }
}
