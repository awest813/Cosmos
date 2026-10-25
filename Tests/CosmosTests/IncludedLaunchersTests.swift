import XCTest
@testable import Cosmos

final class IncludedLaunchersTests: XCTestCase {
    func testIncludedLauncherCatalog() {
        XCTAssertEqual(IncludedLaunchers.all.map(\.id), ["highball", "vermut"])
        XCTAssertEqual(IncludedLaunchers.highball.name, "Highball")
        XCTAssertEqual(IncludedLaunchers.highball.sourceFolder, "third_party/highball")
        XCTAssertEqual(IncludedLaunchers.highball.buildScript, "scripts/build_highball.command")
        XCTAssertEqual(IncludedLaunchers.highball.guideRelativePath, "docs/HIGHBALL.md")
        XCTAssertTrue(IncludedLaunchers.highball.summary.contains("Apple Silicon"))
        XCTAssertTrue(IncludedLaunchers.highball.summary.contains("not in the folder"))
        XCTAssertTrue(IncludedLaunchers.highball.licenseLine.contains("GPL-3.0"))

        XCTAssertEqual(IncludedLaunchers.vermut.name, "Vermut")
        XCTAssertEqual(IncludedLaunchers.vermut.sourceFolder, "third_party/vermut")
        XCTAssertEqual(IncludedLaunchers.vermut.buildScript, "scripts/build_vermut.command")
        XCTAssertEqual(IncludedLaunchers.vermut.guideRelativePath, "docs/VERMUT.md")
        XCTAssertTrue(IncludedLaunchers.vermut.summary.contains("Steam, Epic, and GOG"))
        XCTAssertTrue(IncludedLaunchers.vermut.summary.contains("disk image"))
        XCTAssertTrue(IncludedLaunchers.vermut.licenseLine.contains("MIT"))
        XCTAssertTrue(IncludedLaunchers.caption.contains("separate from Cosmos"))
        XCTAssertEqual(IncludedLaunchers.title, "Highball and Vermut")
    }

    func testIncludedLauncherBuildTitles() {
        XCTAssertEqual(
            CosmosOperationLabel.title(script: "scripts/build_highball.command", arguments: []),
            "Building Highball…"
        )
        XCTAssertEqual(
            CosmosOperationLabel.title(script: "scripts/build_vermut.command", arguments: []),
            "Building Vermut…"
        )
    }
}
