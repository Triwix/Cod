import AVFoundation
import UIKit

/// Turns a still snippet into a tiny looping H.264 clip.
///
/// PiP is built around real video playback. Rather than fight
/// `AVSampleBufferDisplayLayer` into pretending to be a live stream, we hand
/// AVKit exactly what it expects: an `AVPlayer` playing a movie. Identical
/// frames compress to almost nothing, so the file is a few kilobytes.
enum FloatingClip {
    enum ClipError: LocalizedError {
        case noPixelBuffer
        case writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .noPixelBuffer: return "Couldn't turn that snippet into a video frame."
            case let .writerFailed(reason): return "Couldn't build the floating clip: \(reason)"
            }
        }
    }

    // Short on purpose: every frame is identical, so looping by seeking back to
    // zero is visually undetectable. A longer clip only costs encode time.
    private static let fps: Int32 = 6
    private static let seconds: Int32 = 2

    static func make(from image: UIImage) async throws -> URL {
        guard let pixelBuffer = image.pixelBuffer() else { throw ClipError.noPixelBuffer }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cod-float-\(UUID().uuidString).mp4")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard writer.canAdd(input) else { throw ClipError.writerFailed("writer rejected the video input") }
        writer.add(input)

        guard writer.startWriting() else {
            throw ClipError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(fps * seconds)
        let queue = DispatchQueue(label: "com.josh.cod.clipwriter")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var frame = 0
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard frame < totalFrames else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps))
                    frame += 1
                }
            }
        }

        await writer.finishWriting()

        guard writer.status == .completed else {
            throw ClipError.writerFailed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }
        return url
    }

    /// Clips are disposable; sweep any left behind by a crash or a swap.
    static func cleanUp(except keep: URL? = nil) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("cod-float-") && file != keep {
            try? fm.removeItem(at: file)
        }
    }
}
