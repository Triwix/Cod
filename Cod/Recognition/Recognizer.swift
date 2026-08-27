import UIKit
import Vision

/// Text and barcode recognition, all on-device via Vision.
enum Recognizer {
    struct TextResult {
        /// Recognized lines joined with newlines, in reading order.
        var text: String
        /// Per-observation boxes in *normalized Vision coordinates*
        /// (origin bottom-left), handy for drawing and for smart regions.
        var boxes: [CGRect]
        var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    struct BarcodeHit: Identifiable, Hashable {
        let id = UUID()
        var payload: String
        var symbology: String
        var box: CGRect

        var isLikelyURL: Bool {
            guard let url = URL(string: payload) else { return false }
            return url.scheme?.hasPrefix("http") == true
        }
    }

    enum RecognizerError: LocalizedError {
        case noCGImage
        case unavailable

        var errorDescription: String? {
            switch self {
            case .noCGImage:
                return "That image couldn't be read."
            case .unavailable:
                return "The Simulator can't run this Vision model. It works on a real device."
            }
        }
    }

    // MARK: - Text

    static func recognizeText(
        in image: UIImage,
        accuracy: OCRAccuracy = AppSettings.shared.ocrAccuracy,
        languages: [String] = AppSettings.shared.ocrLanguages,
        usesLanguageCorrection: Bool = AppSettings.shared.ocrLanguageCorrection
    ) async throws -> TextResult {
        guard let cgImage = image.cgImageForRecognition else { throw RecognizerError.noCGImage }
        let orientation = image.cgOrientation

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = accuracy == .fast ? .fast : .accurate
                request.usesLanguageCorrection = usesLanguageCorrection
                if !languages.isEmpty { request.recognitionLanguages = languages }

                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: TextResult(
                        text: lines.joined(separator: "\n"),
                        boxes: observations.map(\.boundingBox)
                    ))
                } catch {
                    continuation.resume(throwing: Self.mapped(error))
                }
            }
        }
    }

    /// Languages Vision can recognize on this device, for the settings picker.
    static var supportedLanguages: [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
    }

    // MARK: - Barcodes

    static func detectBarcodes(in image: UIImage) async throws -> [BarcodeHit] {
        guard let cgImage = image.cgImageForRecognition else { throw RecognizerError.noCGImage }
        let orientation = image.cgOrientation

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectBarcodesRequest()
                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                    try handler.perform([request])
                    let hits: [BarcodeHit] = (request.results ?? []).compactMap { observation in
                        guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
                        return BarcodeHit(
                            payload: payload,
                            symbology: observation.symbology.friendlyName,
                            box: observation.boundingBox
                        )
                    }
                    continuation.resume(returning: hits)
                } catch {
                    continuation.resume(throwing: Self.mapped(error))
                }
            }
        }
    }

    // MARK: - Smart regions

    /// Regions worth offering as one-tap selections: paragraphs of text (with
    /// adjacent lines merged into a block) plus card-like rectangles. Returned
    /// in *image-space* pixels, origin top-left.
    static func smartRegions(in image: UIImage) async -> [CGRect] {
        guard let cgImage = image.cgImageForRecognition else { return [] }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let imageArea = size.width * size.height

        // Real recognition (at the fast level) gives much cleaner line boxes
        // than VNDetectTextRectangles, which happily boxes noise.
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false

        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.minimumAspectRatio = 0.1
        rectRequest.maximumObservations = 12
        rectRequest.minimumSize = 0.08
        rectRequest.minimumConfidence = 0.7

        // Run them through separate handlers: if one model is unavailable
        // (the Simulator can't load them all) the other still contributes.
        let orientation = image.cgOrientation
        try? VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            .perform([textRequest])
        try? VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            .perform([rectRequest])

        let lines = (textRequest.results ?? [])
            .filter { $0.confidence > 0.3 }
            .map { $0.boundingBox.denormalized(in: size) }
            .filter { $0.width > 30 && $0.height > 10 }

        let cards = (rectRequest.results ?? [])
            .map { $0.boundingBox.denormalized(in: size) }

        let candidates = (lines.mergedIntoBlocks() + cards)
            .map { $0.insetBy(dx: -6, dy: -4).intersection(CGRect(origin: .zero, size: size)) }
            .filter { rect in
                guard !rect.isNull else { return false }
                let fraction = rect.area / imageArea
                // Too small to aim at, or so big that "select all" is the
                // better answer.
                return fraction > 0.002 && fraction < 0.85 && rect.width > 40 && rect.height > 16
            }
            .mergingOverlaps()

        return Array(candidates.prefix(14))
    }

    // MARK: - Plumbing

    /// Vision reports "could not create inference context" when a model can't
    /// be loaded — which is what the Simulator does for barcode detection.
    /// Turn that into something the UI can explain.
    private static func mapped(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == "com.apple.Vision", nsError.code == 9 else { return error }
        return RecognizerError.unavailable
    }
}

// MARK: - Helpers

extension VNBarcodeSymbology {
    var friendlyName: String {
        rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
    }
}

extension CGRect {
    /// Vision normalized (origin bottom-left) → image pixels (origin top-left).
    func denormalized(in size: CGSize) -> CGRect {
        CGRect(
            x: minX * size.width,
            y: (1 - maxY) * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}

extension Array where Element == CGRect {
    /// Groups text lines that sit directly above/below each other into one
    /// paragraph block, so tapping selects the whole address rather than a
    /// single line of it.
    func mergedIntoBlocks() -> [CGRect] {
        guard !isEmpty else { return [] }
        // Each block remembers the height of the *lines* that formed it. Using
        // the growing union's height instead would let the gap tolerance grow
        // with every merge, and the whole screen would collapse into one box.
        var blocks: [(rect: CGRect, lineHeight: CGFloat)] =
            sorted { $0.minY < $1.minY }.map { ($0, $0.height) }
        var didMerge = true

        while didMerge {
            didMerge = false
            outer: for i in 0..<blocks.count {
                for j in (i + 1)..<blocks.count {
                    let a = blocks[i], b = blocks[j]

                    // Columns must line up…
                    let overlapX = Swift.min(a.rect.maxX, b.rect.maxX) - Swift.max(a.rect.minX, b.rect.minX)
                    guard overlapX > Swift.min(a.rect.width, b.rect.width) * 0.5 else { continue }

                    // …and the lines must be close enough to read as one block.
                    let gapY = Swift.max(a.rect.minY, b.rect.minY) - Swift.min(a.rect.maxY, b.rect.maxY)
                    guard gapY < Swift.min(a.lineHeight, b.lineHeight) * 0.85 else { continue }

                    blocks[i] = (a.rect.union(b.rect), Swift.min(a.lineHeight, b.lineHeight))
                    blocks.remove(at: j)
                    didMerge = true
                    break outer
                }
            }
        }
        return blocks.map(\.rect)
    }

    /// Collapses boxes that substantially overlap so tap-to-snap doesn't offer
    /// six near-identical candidates for the same paragraph.
    func mergingOverlaps(threshold: CGFloat = 0.6) -> [CGRect] {
        var result: [CGRect] = []
        for rect in sorted(by: { $0.area > $1.area }) {
            let duplicate = result.contains { existing in
                let intersection = existing.intersection(rect)
                guard !intersection.isNull else { return false }
                return intersection.area / Swift.min(existing.area, rect.area) > threshold
            }
            if !duplicate { result.append(rect) }
        }
        return result
    }
}

extension CGRect {
    var area: CGFloat { width * height }
}

extension UIImage {
    /// Vision wants a `CGImage`; regenerate one for images backed by CIImage.
    var cgImageForRecognition: CGImage? {
        if let cgImage { return cgImage }
        guard let ciImage else { return nil }
        return CIContext().createCGImage(ciImage, from: ciImage.extent)
    }

    var cgOrientation: CGImagePropertyOrientation {
        CGImagePropertyOrientation(imageOrientation)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
