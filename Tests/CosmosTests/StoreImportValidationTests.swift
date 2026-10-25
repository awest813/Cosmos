import XCTest
@testable import Cosmos

final class StoreImportValidationTests: XCTestCase {
    func testClassicInstallerRequiresInstallerPathAndGameTitle() {
        let request = StoreImportRequest(
            title: "Install Classic Game", message: "Installer, folder, game",
            fields: [
                .init(id: .path, label: "Installer EXE", placeholder: "setup.exe"),
                .init(id: .displayName, label: "Game title", placeholder: "Title")
            ],
            submitLabel: "Install in Terminal", script: "scripts/install_program.command",
            baseArguments: ["install"], forceTerminal: true
        )
        XCTAssertNotNil(StoreImportValidation.validate(request: request, values: [.path: "/Games", .displayName: "SimCity 3000 Unlimited"]))
        XCTAssertNotNil(StoreImportValidation.validate(request: request, values: [.path: "setup.exe", .displayName: "SimCity 3000 Unlimited"]))
        XCTAssertNotNil(StoreImportValidation.validate(request: request, values: [.path: "/Downloads/setup.exe", .displayName: " "]))
        XCTAssertNil(StoreImportValidation.validate(request: request, values: [.path: "/Downloads/setup SimCity.exe", .displayName: "SimCity 3000 Unlimited"]))
    }

    func testGogRequiresPath() {
        let request = StoreImportRequest(
            title: "GOG",
            message: "test",
            fields: [.init(id: .path, label: "Path", placeholder: "path")],
            submitLabel: "Import",
            script: "import_game.command",
            baseArguments: ["add-gog"],
            forceTerminal: false
        )
        XCTAssertEqual(
            StoreImportValidation.validate(request: request, values: [:]),
            "Enter a GOG setup .exe, install folder, or slug from List GOG Games."
        )
    }

    func testGogAcceptsSlug() {
        let request = StoreImportRequest(
            title: "GOG",
            message: "test",
            fields: [.init(id: .path, label: "Path", placeholder: "path")],
            submitLabel: "Import",
            script: "import_game.command",
            baseArguments: ["add-gog"],
            forceTerminal: false
        )
        XCTAssertNil(
            StoreImportValidation.validate(request: request, values: [.path: "celeste"])
        )
    }
}
