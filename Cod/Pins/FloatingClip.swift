@preconcurrency import AVFoundation
import UIKit

/// Turns a still snippet into a tiny looping H.264 clip.
///
/// PiP is built around real video playback. Rather than fight
/// `AVSampleBufferDisplayLayer` into pretending to be a live stream, we hand
/// AVKit exactly what it expects: an `AVPlayer` playing a movie. Identical
/// frames compress to almost nothing, so the file is a few kilobytes.
enum FloatingClip {
    /// Share-extension temporary storage is purged when the extension calls
    /// `completeRequest`. AVKit may still be decoding the clip at that point,
    /// which leaves a live PiP window with a gray frame. Caches survives the
    /// handoff; stale clips are removed whenever the next session starts.
    private static var clipDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CodFloatingClips", isDirectory: true)
    }

    enum ClipError: LocalizedError {
        case noPixelBuffer
        case writerFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .noPixelBuffer: return "Couldn't turn that snippet into a video frame."
            case let .writerFailed(reason): return "Couldn't build the floating clip: \(reason)"
            case .timedOut: return "Preparing the floating image took too long. Please try again."
            }
        }
    }

    // Short on purpose: every frame is identical, so looping by seeking back to
    // zero is visually undetectable. A longer clip only costs encode time.
    private static let fps: Int32 = 6
    private static let seconds: Int32 = 2

    static func make(from image: UIImage) async throws -> URL {
        try Task.checkCancellation()
        guard let pixelBuffer = image.pixelBuffer() else { throw ClipError.noPixelBuffer }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let directory = clipDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory
            .appendingPathComponent("cod-float-\(UUID().uuidString).mp4")
        var completed = false
        defer {
            if !completed { try? FileManager.default.removeItem(at: url) }
        }

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

        try await FloatingClipEncoder.encode(
            ImageClipWriter(writer: writer, input: input, adaptor: adaptor, pixelBuffer: pixelBuffer, fps: fps),
            frames: Int(fps * seconds)
        )
        completed = true
        return url
    }

    /// Clips are disposable; sweep any left behind by a crash or a swap.
    static func cleanUp(except keep: URL? = nil) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: clipDirectory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("cod-float-") && file != keep {
            try? fm.removeItem(at: file)
        }
    }
}

/// Keep the wait independent of AVFoundation so failures before readiness,
/// stalled finalization and cancellation can be exercised deterministically.
protocol FloatingClipWriting: AnyObject {
    var status: AVAssetWriter.Status { get }
    var error: Error? { get }
    var isReady: Bool { get }
    func append(frame: Int) -> Bool
    func finish()
    func cancel()
}

enum FloatingClipEncoder {
    static func encode(
        _ writer: FloatingClipWriting, frames: Int,
        timeout: Duration = .seconds(15), pollInterval: Duration = .milliseconds(10)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var completed = false
        defer { if !completed { writer.cancel() } }

        func check() throws {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw FloatingClip.ClipError.timedOut }
            guard writer.status == .writing else {
                throw FloatingClip.ClipError.writerFailed(writer.error?.localizedDescription ?? "Video encoding stopped.")
            }
        }

        // A cancellable wait also observes terminal writer states when an
        // AVAssetWriterInput never becomes ready or stops issuing callbacks.
        for frame in 0..<frames {
            try check()
            while !writer.isReady {
                try await Task.sleep(for: pollInterval)
                try check()
            }
            guard writer.append(frame: frame) else {
                throw FloatingClip.ClipError.writerFailed(writer.error?.localizedDescription ?? "The video writer rejected an image frame.")
            }
        }
        try check()
        writer.finish()
        while true {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw FloatingClip.ClipError.timedOut }
            // Read status once: finalization may complete between any two
            // reads, which must never turn a successful clip into a failure.
            switch writer.status {
            case .completed:
                completed = true
                return
            case .writing:
                break
            default:
                throw FloatingClip.ClipError.writerFailed(writer.error?.localizedDescription ?? "Video finalization stopped.")
            }
            try await Task.sleep(for: pollInterval)
        }
    }
}

private final class ImageClipWriter: FloatingClipWriting {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let pixelBuffer: CVPixelBuffer
    let fps: Int32

    init(writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor,
         pixelBuffer: CVPixelBuffer, fps: Int32) {
        self.writer = writer; self.input = input; self.adaptor = adaptor
        self.pixelBuffer = pixelBuffer; self.fps = fps
    }
    var status: AVAssetWriter.Status { writer.status }
    var error: Error? { writer.error }
    var isReady: Bool { input.isReadyForMoreMediaData }
    func append(frame: Int) -> Bool {
        adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps))
    }
    func finish() {
        input.markAsFinished()
        // Observe status with the same deadline; a lost completion callback
        // must not strand a checked continuation or keep a cancelled float alive.
        writer.finishWriting(completionHandler: {})
    }
    func cancel() {
        if writer.status == .writing { writer.cancelWriting() }
    }
}
