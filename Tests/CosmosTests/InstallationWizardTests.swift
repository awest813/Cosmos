import XCTest
@testable import Cosmos

final class InstallationWizardTests: XCTestCase {
    func testDefaultPlanPassesAnExplicitEnvironmentAndFolder() {
        var draft = InstallationWizardDraft(request: .init())
        draft.title = "SimCity 3000 Unlimited"; draft.installer = "/Downloads/Setup.exe"
        XCTAssertEqual(draft.environmentName, "game-simcity-3000-unlimited")
        XCTAssertEqual(draft.importRequest.installerArguments(values: draft.values), [
            "install", "/Downloads/Setup.exe", "--name", "SimCity 3000 Unlimited",
            "--install-dir", "drive_c/Games/simcity-3000-unlimited", "--bottle", "game-simcity-3000-unlimited"
        ])
    }
    func testResumeLocksIdentityAndPreservesSavedFolderGuard() {
        let saved = PendingGameInstallation(id: "custom/game", name: "Game", slug: "game", bottle: "custom",
            folder: "/Volumes/Offline/Game", installer: "/Downloads/Setup.exe", stage: "awaiting-game")
        var draft = InstallationWizardDraft(request: .init(resuming: true, installation: saved))
        draft.title = "Changed"; draft.existingEnvironment = "wrong"; draft.newEnvironmentName = "also-wrong"
        draft.gameExecutable = "Apps/Game.exe"; draft.makeMacApp = true; draft.launchAfterInstall = false
        XCTAssertEqual(draft.effectiveTitle, "Game"); XCTAssertEqual(draft.environmentName, "custom")
        XCTAssertNil(draft.values[.installDirectory])
        XCTAssertEqual(draft.importRequest.installerArguments(values: draft.values), [
            "resume", "--name", "Game", "--game-exe", "Apps/Game.exe", "--bottle", "custom", "--make-app", "--no-launch"
        ])
    }
    func testRetryIncludesInstallerWhileResumeNeverDoes() {
        let saved = PendingGameInstallation(id: "custom/game", name: "Game", slug: "game", bottle: "custom",
            folder: "/Games/Game", installer: "/Downloads/Setup.MSI", stage: "setup-failed")
        let retry = InstallationWizardDraft(request: .init(resuming: false, installation: saved))
        XCTAssertEqual(Array(retry.importRequest.installerArguments(values: retry.values).prefix(2)), ["install", "/Downloads/Setup.MSI"])
        XCTAssertEqual(retry.values[.installDirectory], "/Games/Game")
    }
    func testEnvironmentReuseMustBeExplicitAndWow64() {
        var draft = InstallationWizardDraft(request: .init())
        draft.title = "Game"; draft.installer = "/Downloads/Setup.exe"
        let bottle = Bottle(id: "game-game", settings: ["COSMOS_PREFIX_ARCH": "wow64"], prefixURL: URL(fileURLWithPath: "/fixture"), isInitialized: true, steamInstalled: false)
        XCTAssertNotNil(draft.destinationIssue(bottles: [bottle]))
        draft.existingEnvironment = "game-game"
        XCTAssertNil(draft.destinationIssue(bottles: [bottle]))
        let incompatible = Bottle(id: "game-game", settings: ["COSMOS_PREFIX_ARCH": "win32"], prefixURL: bottle.prefixURL, isInitialized: true, steamInstalled: false)
        XCTAssertNotNil(draft.destinationIssue(bottles: [incompatible]))
    }
    func testAsciiSlugRulesAndInvalidTraversalLikeNames() {
        XCTAssertEqual(InstallationWizardDraft.slugify("  SimCity 3000 Unlimited! "), "simcity-3000-unlimited")
        XCTAssertEqual(InstallationWizardDraft.slugify("__Classic--Game__"), "classic-game__")
        var draft = InstallationWizardDraft(request: .init())
        draft.title = "Bad..Game"; draft.installer = "/Downloads/Setup.exe"
        XCTAssertNotNil(draft.sourceIssue(checkFiles: false))
    }
    func testInstallerHeaderValidationRejectsFakeMsiAndDll() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var draft = InstallationWizardDraft(request: .init()); draft.title = "Game"
        let msi = root.appendingPathComponent("Setup.MSI"); draft.installer = msi.path
        try Data("not an MSI".utf8).write(to: msi); XCTAssertNotNil(draft.sourceIssue())
        try Data([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]).write(to: msi); XCTAssertNil(draft.sourceIssue())
        let exe = root.appendingPathComponent("Setup.exe"); draft.installer = exe.path
        var bytes = [UInt8](repeating: 0, count: 256)
        bytes[0] = 0x4d; bytes[1] = 0x5a; bytes[60] = 128; bytes[128] = 0x50; bytes[129] = 0x45; bytes[132] = 0x4c; bytes[133] = 1
        try Data(bytes).write(to: exe); XCTAssertNil(draft.sourceIssue())
        bytes[151] = 0x20 // IMAGE_FILE_DLL
        try Data(bytes).write(to: exe); XCTAssertNotNil(draft.sourceIssue())
    }
    private func withBottles(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = ProcessInfo.processInfo.environment["COSMOS_BOTTLES_DIR"]
        setenv("COSMOS_BOTTLES_DIR", root.path, 1)
        defer {
            if let previous { setenv("COSMOS_BOTTLES_DIR", previous, 1) } else { unsetenv("COSMOS_BOTTLES_DIR") }
            try? FileManager.default.removeItem(at: root)
        }
        try body(root)
    }
    func testDestinationPreviewForNewEnvironmentCreatesNothing() throws {
        try withBottles { root in
            var draft = InstallationWizardDraft(request: .init()); draft.title = "Game"
            let preview = try draft.previewDestination()
            XCTAssertEqual(preview.windowsFolder, "C:\\Games\\game")
            XCTAssertTrue(preview.assumedMappings)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        }
    }
    func testPreviewUsesActualExternalDriveMapping() throws {
        try withBottles { root in
            var draft = InstallationWizardDraft(request: .init()); draft.title = "Game"; draft.folder = "D:\\Games"
            let prefix = draft.prefix; let drives = prefix.appendingPathComponent("dosdevices")
            try FileManager.default.createDirectory(at: drives, withIntermediateDirectories: true)
            let external = root.appendingPathComponent("External"); try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
            try "registry".write(to: prefix.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: drives.appendingPathComponent("d:"), withDestinationURL: external)
            let preview = try draft.previewDestination()
            XCTAssertEqual(preview.windowsFolder, "D:\\Games"); XCTAssertFalse(preview.assumedMappings)
            XCTAssertFalse(FileManager.default.fileExists(atPath: external.appendingPathComponent("Games").path))
        }
    }
    func testDisconnectedResumeFolderFailsWithoutCreatingReplacement() throws {
        try withBottles { root in
            let missing = root.appendingPathComponent("Offline/Game")
            let saved = PendingGameInstallation(id: "custom/game", name: "Game", slug: "game", bottle: "custom", folder: missing.path, installer: "", stage: "awaiting-game")
            let draft = InstallationWizardDraft(request: .init(resuming: true, installation: saved))
            try FileManager.default.createDirectory(at: draft.prefix, withIntermediateDirectories: true)
            try "registry".write(to: draft.prefix.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try draft.previewDestination())
            XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
            XCTAssertNil(draft.values[.installDirectory])
        }
    }
}
