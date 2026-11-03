import AVFoundation
import UIKit

/// A real moving, local movie for document-opening / Photos picker QA.
enum FixtureVideo {
    @MainActor static func make(duration: TimeInterval = 30) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CodMovingTest-\(UUID()).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        for frame in 0..<60 {
            while !input.isReadyForMoreMediaData {
                guard ContinuousClock.now < deadline else { writer.cancelWriting(); throw CocoaError(.fileWriteUnknown) }
                try await Task.sleep(for: .milliseconds(10))
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32ARGB, [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
            guard let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                context.setFillColor([UIColor.red, .blue, .green][frame / 20].cgColor)
                context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(x: frame * 5 % 280, y: 50, width: 40, height: 80))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(seconds: Double(frame) * duration / 60, preferredTimescale: 600)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }
}
