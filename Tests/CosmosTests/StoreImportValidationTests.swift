import XCTest
@testable import Cosmos

final class StoreImportValidationTests: XCTestCase {
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
