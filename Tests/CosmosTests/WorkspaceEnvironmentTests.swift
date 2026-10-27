import XCTest
@testable import Cosmos

final class WorkspaceEnvironmentTests: XCTestCase {
    private var bottle: Bottle {
        Bottle(id: "main", settings: ["WINE_VERSION": "10.0", "COSMOS_BACKEND": "wined3d", "COSMOS_PREFIX_ARCH": "wow64", "WINDOWS_VERSION": "win10"],
            prefixURL: URL(fileURLWithPath: "/Fixture/main/prefix"), isInitialized: true, steamInstalled: false)
    }
    private var environments: [WorkspaceEnvironment] {
        let ports = [
            WinePort(id: "main-game", settings: ["PORT_BOTTLE": ""], directory: URL(fileURLWithPath: "/Ports/main-game")),
            WinePort(id: "named-game", settings: ["PORT_BOTTLE": "main", "PORT_NAME": "Named game"], directory: URL(fileURLWithPath: "/Ports/named-game"))
        ]
        return WorkspaceEnvironment.catalog(bottles: [bottle], ports: ports, main: .defaults, mainInitialized: true)
    }
    func testMainAndNamedMainHaveSeparateIdentityAndGameAssignments() {
        let items = environments
        XCTAssertEqual(items.map(\.id), ["main", "named:main"])
        XCTAssertEqual(items[0].assignedGames.map(\.id), ["main-game"])
        XCTAssertEqual(items[1].assignedGames.map(\.id), ["named-game"])
    }
    func testCommandTargetsCarryTheirOwnPrefixAndWineVersion() {
        let items = environments
        XCTAssertEqual(items[0].commandEnvironment["COSMOS_BOTTLE"], "")
        XCTAssertEqual(items[1].commandEnvironment["COSMOS_BOTTLE"], "main")
        XCTAssertEqual(items[1].commandEnvironment["WINEPREFIX"], bottle.prefixURL.path)
        XCTAssertEqual(items[1].commandEnvironment["WINE_VERSION"], "10.0")
        XCTAssertEqual(items[1].commandEnvironment["COSMOS_SKIP_STEAM"], "1")
    }
    func testMainCannotBeClonedResetOrDeletedThroughNamedBottleActions() {
        let context = WorkspaceEnvironmentContext(selected: environments[0], busy: false, modalPresented: false, installHostIssue: nil)
        for action in [WorkspaceEnvironmentAction.clone, .reset, .delete, .install] { XCTAssertNotNil(context.disabledReason(action)) }
        XCTAssertNil(context.disabledReason(.diagnose)); XCTAssertNil(context.disabledReason(.stop))
    }
    func testMissingSelectionAndModalBlockEveryAction() {
        for context in [WorkspaceEnvironmentContext(selected: nil, busy: false, modalPresented: false, installHostIssue: nil),
                        WorkspaceEnvironmentContext(selected: environments[1], busy: false, modalPresented: true, installHostIssue: nil)] {
            for action in WorkspaceEnvironmentAction.allCases { XCTAssertNotNil(context.disabledReason(action)) }
        }
    }
    func testBusyAndUnsupportedInstallerDoNotBlockReadOnlyFolderReveal() {
        let busy = WorkspaceEnvironmentContext(selected: environments[1], busy: true, modalPresented: false, installHostIssue: nil)
        XCTAssertNil(busy.disabledReason(.reveal)); XCTAssertNotNil(busy.disabledReason(.delete))
        let unsupported = WorkspaceEnvironmentContext(selected: environments[1], busy: false, modalPresented: false, installHostIssue: "Unsupported host")
        XCTAssertEqual(unsupported.disabledReason(.install), "Unsupported host")
        XCTAssertNil(unsupported.disabledReason(.clone))
    }
    func testSettingsOnlySendChangedValuesAndExpectedRevision() {
        var draft = EnvironmentSettingsDraft(bottle: bottle, revision: String(repeating: "a", count: 64))
        XCTAssertTrue(draft.changes.isEmpty)
        draft.backend = "dxmt"; draft.retina = true
        XCTAssertEqual(draft.arguments, ["update", "main", "--expect-sha256", String(repeating: "a", count: 64), "COSMOS_BACKEND", "dxmt", "WINE_RETINA_MODE", "1"])
        XCTAssertFalse(draft.summaries.joined().contains("COSMOS_BACKEND"))
    }
    func testMainSettingsRequestCannotCreateANamedEnvironmentEditor() {
        XCTAssertNil(EnvironmentSettingsRequest(environment: environments[0], revision: "fixture"))
        XCTAssertNotNil(EnvironmentSettingsRequest(environment: environments[1], revision: "fixture"))
    }
    func testInstallHerePreselectsEnvironmentWithoutLockingNewGameIdentity() {
        var draft = InstallationWizardDraft(request: InstallationWizardRequest(preferredEnvironment: "main"))
        draft.title = "New Game"; draft.installer = "/Downloads/setup.exe"
        XCTAssertEqual(draft.environmentName, "main")
        draft.existingEnvironment = "another"
        XCTAssertEqual(draft.environmentName, "another")
        XCTAssertEqual(draft.values[.installationBottle], "another")
    }
}
