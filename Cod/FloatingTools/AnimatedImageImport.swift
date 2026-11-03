@preconcurrency import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum AnimatedImageError: LocalizedError {
  case invalid, tooLong, encoding
  var errorDescription: String? {
    switch self {
    case .invalid: return "Choose a readable animated GIF smaller than 50 MB."
    case .tooLong: return "Choose a GIF with no more than 600 frames and two minutes of animation."
    case .encoding: return "Cod couldn't prepare this animation for video playback."
    }
  }
}

enum AnimatedImageImport {
  /// AVFoundation's legacy writer objects are confined to one encoding queue.
  private final class WriterState: @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    init(
      _ writer: AVAssetWriter, _ input: AVAssetWriterInput,
      _ adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) {
      self.writer = writer
      self.input = input
      self.adaptor = adaptor
    }
  }
  static func isAnimatedGIF(_ data: Data) -> Bool {
    guard data.count <= VisualFileImport.maximumImageBytes,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetType(source) as String? == UTType.gif.identifier
    else { return false }
    return CGImageSourceGetCount(source) > 1
  }
  static func frameDelay(_ properties: [CFString: Any]) -> Double {
    let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
    let value =
      (gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime]) as? Double
      ?? 0.1
    return value.isFinite && value > 0 ? max(0.02, value) : 0.1
  }
  static func video(_ data: Data, name: String = "GIF Animation") async throws -> VideoReference {
    try Task.checkCancellation()
    guard isAnimatedGIF(data) else { throw AnimatedImageError.invalid }
    let directory = try TemporaryMedia.directory(.animations)
    let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    do {
      try await encode(data, to: url)
      try Task.checkCancellation()
      return try await VideoReference.openOwned(url, name: name)
    } catch {
      try? FileManager.default.removeItem(at: url)
      throw error
    }
  }

  private static func encode(_ data: Data, to url: URL) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let queue = DispatchQueue(label: "com.josh.cod.animation", qos: .userInitiated)
      queue.async {
        do {
          guard
            let source = CGImageSourceCreateWithData(
              data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
          else { throw AnimatedImageError.invalid }
          let count = CGImageSourceGetCount(source)
          guard count <= 600 else { throw AnimatedImageError.tooLong }
          let delays = (0..<count).map {
            frameDelay(
              CGImageSourceCopyPropertiesAtIndex(source, $0, nil) as? [CFString: Any] ?? [:])
          }
          let duration = delays.reduce(0, +)
          guard duration <= 120 else { throw AnimatedImageError.tooLong }
          let options =
            [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 1_280,
              kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary
          guard let first = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw AnimatedImageError.invalid
          }
          // Very small H.264 rasters can encode but fail to decode on Apple
          // devices. Use at least one macroblock and preserve the source fit.
          let width = max(16, first.width / 2 * 2)
          let height = max(16, first.height / 2 * 2)
          let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
          let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
              AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width,
              AVVideoHeightKey: height,
            ])
          let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: nil)
          guard writer.canAdd(input) else { throw AnimatedImageError.encoding }
          writer.add(input)
          guard writer.startWriting() else { throw writer.error ?? AnimatedImageError.encoding }
          writer.startSession(atSourceTime: .zero)
          let state = WriterState(writer, input, adaptor)
          var index = 0
          var finished = false
          var elapsed = 0.0
          input.requestMediaDataWhenReady(on: queue) {
            guard !finished else { return }
            while state.input.isReadyForMoreMediaData {
              do {
                if index > count {
                  finished = true
                  state.writer.endSession(
                    atSourceTime: CMTime(seconds: duration, preferredTimescale: 600))
                  state.input.markAsFinished()
                  state.writer.finishWriting {
                    if state.writer.status == .completed {
                      continuation.resume()
                    } else {
                      continuation.resume(
                        throwing: state.writer.error ?? AnimatedImageError.encoding)
                    }
                  }
                  return
                }
                try autoreleasepool {
                  guard
                    let cg = CGImageSourceCreateThumbnailAtIndex(
                      source, min(index, count - 1), options)
                  else { throw AnimatedImageError.invalid }
                  let format = UIGraphicsImageRendererFormat()
                  format.scale = 1
                  format.opaque = true
                  let image = UIGraphicsImageRenderer(
                    size: CGSize(width: width, height: height), format: format
                  ).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    let scale = min(
                      CGFloat(width) / CGFloat(cg.width), CGFloat(height) / CGFloat(cg.height))
                    let drawSize = CGSize(
                      width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
                    UIImage(cgImage: cg).draw(
                      in: CGRect(
                        x: (CGFloat(width) - drawSize.width) / 2,
                        y: (CGFloat(height) - drawSize.height) / 2, width: drawSize.width,
                        height: drawSize.height))
                  }
                  guard let pixels = image.pixelBuffer(),
                    state.adaptor.append(
                      pixels,
                      withPresentationTime: CMTime(
                        seconds: index == count ? duration - 1 / 600.0 : elapsed,
                        preferredTimescale: 600))
                  else { throw state.writer.error ?? AnimatedImageError.encoding }
                }
                if index < count { elapsed += delays[index] }
                index += 1
              } catch {
                finished = true
                state.writer.cancelWriting()
                continuation.resume(throwing: error)
                return
              }
            }
          }
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
}
