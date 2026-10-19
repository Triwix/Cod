import UIKit
import XCTest
@testable import Cod

final class SnapStoreTests: XCTestCase {
    private var baseDirectory: URL!

    override func setUpWithError() throws {
        baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cod-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: baseDirectory)
        baseDirectory = nil
    }

    func testChangingHistoryLimitPersistsTrimmedIndex() throws {
        let directoryName = "History"
        let store = SnapStore(
            directoryName: directoryName,
            baseDirectory: baseDirectory
        )
        let image = testImage()

        for _ in 0..<12 {
            store.add(image: image, origin: .screenshot, limit: .unlimited)
        }
        store.waitForPendingWrites()

        store.trim(to: .ten)
        store.waitForPendingWrites()

        let indexURL = baseDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("index.json")
        let data = try Data(contentsOf: indexURL)
        let persisted = try JSONDecoder().decode([Snap].self, from: data)

        XCTAssertEqual(store.snaps.count, 10)
        XCTAssertEqual(persisted.count, 10)
    }

    func testOffLimitDoesNotRetainAnAddedImage() {
        let store = SnapStore(
            directoryName: "DisabledHistory",
            baseDirectory: baseDirectory
        )

        store.add(image: testImage(), origin: .pasted, limit: .off)
        store.waitForPendingWrites()

        XCTAssertTrue(store.snaps.isEmpty)
    }

    func testCacheBudgetCountsDecodedPixelsRatherThanCompressedPNGBytes() throws {
        let image = testImage()
        let bitmap = try XCTUnwrap(image.cgImage)
        let png = try XCTUnwrap(image.pngData())
        XCTAssertEqual(SnapStore.decodedMemoryCost(image), bitmap.bytesPerRow * bitmap.height)
        XCTAssertGreaterThan(SnapStore.decodedMemoryCost(image), png.count)
        XCTAssertEqual(SnapStore.decodedMemoryCost(UIImage()), 1)
    }

    private func testImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: 24, height: 24),
            format: format
        ).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
    }
}
