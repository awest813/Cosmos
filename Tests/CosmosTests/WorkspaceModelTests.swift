import XCTest
@testable import Cosmos

final class WorkspaceModelTests: XCTestCase {
    private var port: WinePort {
        WinePort(id: "same-id", settings: ["PORT_NAME": "Same title", "PORT_EXE": "C:\\Game\\Game.exe", "PORT_BOTTLE": "classic", "PORT_PROGRAM_ARCH": "win32"], directory: URL(fileURLWithPath: "/fixture/Ports/same-id"))
    }
    private var profile: SavedProfile {
        SavedProfile(id: "same-id", name: "Same title", path: "/fixture/OtherGame.exe", args: "", steamAppID: nil, gogSlug: nil, fileURL: URL(fileURLWithPath: "/fixture/same-id.conf"))
    }
    func testSameTitlesAndSourceIDsNeverMergeDifferentLaunchRecords() {
        let items = WorkspaceGame.catalog(ports: [port], profiles: [profile])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.id)), ["port:same-id", "profile:same-id"])
        guard case .port(let selected)? = items.first(where: { $0.id == "port:same-id" }) else { return XCTFail("Port identity was lost") }
        XCTAssertEqual(selected.bottle, "classic")
        XCTAssertEqual(selected.programArch, "win32")
        XCTAssertEqual(selected.exe, "C:\\Game\\Game.exe")
    }
    func testStandaloneActionsDoNotRequireSteamOrAnInstalledRuntime() {
        let context = WorkspaceCommandContext(game: .port(port), busy: false, portHostIssue: nil, runtimeIssue: "Wine is not installed")
        for command in [WorkspaceCommand.install, .addExecutable, .play, .edit, .buildApp, .checkFiles, .diagnose] {
            XCTAssertNil(context.disabledReason(command), command.rawValue)
        }
    }
    func testMissingSelectionNeverFallsBackToAnotherLauncher() {
        let context = WorkspaceCommandContext(game: nil, busy: false, portHostIssue: nil, runtimeIssue: nil)
        for command in [WorkspaceCommand.play, .edit, .buildApp, .reveal, .checkFiles, .diagnose] {
            XCTAssertNotNil(context.disabledReason(command))
        }
        XCTAssertNil(context.disabledReason(.install))
    }
    func testBusyExecutorBlocksMutationsButAllowsFileReveal() {
        let context = WorkspaceCommandContext(game: .port(port), busy: true, portHostIssue: nil, runtimeIssue: nil)
        XCTAssertNil(context.disabledReason(.reveal))
        for command in [WorkspaceCommand.install, .addExecutable, .play, .edit, .buildApp, .diagnose] {
            XCTAssertNotNil(context.disabledReason(command))
        }
    }
    func testUnsupportedHostStillAllowsDefinitionInspectionAndEditing() {
        let context = WorkspaceCommandContext(game: .port(port), busy: false, portHostIssue: "Unsupported host", runtimeIssue: nil)
        XCTAssertEqual(context.disabledReason(.play), "Unsupported host")
        XCTAssertEqual(context.disabledReason(.install), "Unsupported host")
        XCTAssertNil(context.disabledReason(.checkFiles))
        XCTAssertNil(context.disabledReason(.edit))
    }
    func testProfileCapabilitiesDoNotPretendPortOnlyToolsApply() {
        let context = WorkspaceCommandContext(game: .profile(profile), busy: false, portHostIssue: "Port host only", runtimeIssue: nil)
        XCTAssertNil(context.disabledReason(.play))
        XCTAssertNotNil(context.disabledReason(.buildApp))
        XCTAssertNotNil(context.disabledReason(.edit))
    }
    func testCatalogSearchMatchesExecutableAndKeepsIdentity() {
        XCTAssertEqual(WorkspaceGame.catalog(ports: [port], profiles: [profile], query: "othergame").map(\.id), ["profile:same-id"])
        XCTAssertEqual(WorkspaceGame.catalog(ports: [port], profiles: [profile], query: "standalone").map(\.id), ["port:same-id"])
        XCTAssertEqual(WorkspaceGame.catalog(ports: [port], profiles: [profile], query: "  ").count, 2)
    }
}
