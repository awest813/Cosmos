import XCTest
@testable import Cosmos

final class CosmosDesignTests: XCTestCase {
    func testScrollAnchorIDsAreUnique() {
        let ids = [
            CosmosScrollAnchor.steamSettings,
            CosmosScrollAnchor.performanceGraphics,
            CosmosScrollAnchor.gameLibrary,
            CosmosScrollAnchor.gameProfiles,
            CosmosScrollAnchor.repair,
            CosmosScrollAnchor.compatibility,
            CosmosScrollAnchor.storeImport,
        ]
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
