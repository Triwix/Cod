import XCTest
@testable import Cod

final class PiPStateTests: XCTestCase {
    func testActiveWindowTakesReplacementPathEvenAfterStatusMovesToPreparing() {
        let path = PiPPinController.preparationPath(
            wasActive: true,
            hasPlayer: true,
            hasController: true
        )

        XCTAssertEqual(path, .replaceActive)
    }

    func testPrewarmedControllerReusesPreparedPlayback() {
        let path = PiPPinController.preparationPath(
            wasActive: false,
            hasPlayer: true,
            hasController: true
        )

        XCTAssertEqual(path, .reusePrepared)
    }

    func testMissingPreparedComponentsUsesColdPath() {
        XCTAssertEqual(
            PiPPinController.preparationPath(
                wasActive: false,
                hasPlayer: true,
                hasController: false
            ),
            .cold
        )
    }
}
