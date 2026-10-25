import XCTest
@testable import Cosmos

final class StoreImportValidationTests: XCTestCase {
    func testWindowsInstallerOptionsPreservePathsAndDoNotRequireOptionalFields() {
        let request = StoreImportRequest.classicGame()
        XCTAssertFalse(request.fields.first { $0.id == .installDirectory }!.isRequired)
        XCTAssertTrue(request.fields.first { $0.id == .installDirectory }!.choosesDirectory)
        let values: [StoreImportRequest.FieldKind: String] = [
            .path: "/Downloads/Game Setup.MSI", .displayName: "My Windows Game",
            .installDirectory: "/Games/My Windows Game", .makeMacApp: "1", .launchAfterInstall: "0"
        ]
        XCTAssertNil(StoreImportValidation.validate(request: request, values: values))
        XCTAssertEqual(request.installerArguments(values: values), [
            "install", "/Downloads/Game Setup.MSI", "--name", "My Windows Game",
            "--install-dir", "/Games/My Windows Game", "--make-app", "--no-launch"
        ])
        XCTAssertNil(StoreImportValidation.validate(request: request, values: [.path: "/Downloads/game.exe", .displayName: "Game"]))
        XCTAssertNotNil(StoreImportValidation.validate(request: request, values: [.path: "/Downloads/game.exe", .displayName: "Game", .installDirectory: "drive_c/../outside"]))
        XCTAssertNil(StoreImportValidation.validate(request: request, values: [.path: "/Downloads/game.exe", .displayName: "Game", .installDirectory: "C:\\Games\\Game"]))
    }

    func testResumeCanSupplyFolderAndInstalledExeWithoutRerunningInstaller() {
        let request = StoreImportRequest.classicGame(resuming: true)
        let values: [StoreImportRequest.FieldKind: String] = [
            .displayName: "SimCity 3000 Unlimited", .installDirectory: "/Games/SimCity",
            .gameExecutable: "/Games/SimCity/Apps/SC3U.exe"
        ]
        XCTAssertNil(StoreImportValidation.validate(request: request, values: values))
        XCTAssertEqual(request.installerArguments(values: values), [
            "resume", "--name", "SimCity 3000 Unlimited", "--install-dir", "/Games/SimCity",
            "--game-exe", "/Games/SimCity/Apps/SC3U.exe"
        ])
        XCTAssertNotNil(StoreImportValidation.validate(request: request, values: [.displayName: "Game", .gameExecutable: "/Games/setup.msi"]))
    }

    func testResumeNeedsSameGameTitleWithoutInstaller() {
        let request = StoreImportRequest.classicGame(resuming: true)
        XCTAssertEqual(request.baseArguments, ["resume"])
        XCTAssertFalse(request.fields.contains { $0.id == .path })
        XCTAssertNil(StoreImportValidation.validate(request: request, values: [.displayName: "SimCity 3000 Unlimited"]))
        XCTAssertNotNil(StoreImportValidation.validate(request: request, values: [.displayName: " "]))
        XCTAssertNotNil(StoreImportValidation.validate(request: request, values: [.displayName: "Bad/Title"]))
    }

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
