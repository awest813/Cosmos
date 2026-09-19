import XCTest
@testable import Cosmos

final class CosmosSetupProgressTests: XCTestCase {
    func testIntelDoesNotCountSkippedRosettaStep() {
        for rosettaReady in [false, true] {
            XCTAssertEqual(CosmosSetupProgress.fraction(
                needsRosetta: false, rosettaReady: rosettaReady,
                cosmosInstalled: false, prefixReady: false,
                steamInstalled: false, hasGames: false
            ), 0)
            XCTAssertEqual(CosmosSetupProgress.fraction(
                needsRosetta: false, rosettaReady: rosettaReady,
                cosmosInstalled: true, prefixReady: true,
                steamInstalled: true, hasGames: false
            ), 0.75)
            XCTAssertEqual(CosmosSetupProgress.fraction(
                needsRosetta: false, rosettaReady: rosettaReady,
                cosmosInstalled: true, prefixReady: true,
                steamInstalled: true, hasGames: true
            ), 1)
        }
    }

    func testAppleSiliconIncludesRosetta() {
        XCTAssertEqual(CosmosSetupProgress.fraction(
            needsRosetta: true, rosettaReady: true,
            cosmosInstalled: false, prefixReady: false,
            steamInstalled: false, hasGames: false
        ), 0.2)
        XCTAssertEqual(CosmosSetupProgress.fraction(
            needsRosetta: true, rosettaReady: false,
            cosmosInstalled: true, prefixReady: true,
            steamInstalled: true, hasGames: true
        ), 0.8)
        XCTAssertEqual(CosmosSetupProgress.fraction(
            needsRosetta: true, rosettaReady: true,
            cosmosInstalled: true, prefixReady: true,
            steamInstalled: true, hasGames: true
        ), 1)
    }
}
