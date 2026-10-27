import XCTest
@testable import Cosmos

final class EnvironmentRecipeTests: XCTestCase {
    private func parse(_ text: String, id: String = "xact", kind: RepairRecipe.Kind = .dependency) throws -> EnvironmentRecipe {
        try XCTUnwrap(EnvironmentRecipe.parse(data: Data(text.utf8), fileID: id, kind: kind))
    }
    func testReviewRetainsProvenanceAndExactRevision() throws {
        let text = "# Source: upstream (CC0)\nTYPE=dependency\nID=xact\nDESCRIPTION=Audio runtime\nWINETRICKS=xact\n"
        let item = try parse(text)
        XCTAssertEqual(item.contents, text)
        XCTAssertEqual(item.revision, EnvironmentSettingsDraft.digest(Data(text.utf8)))
        XCTAssertNil(item.unsupportedReason)
        XCTAssertEqual(item.arguments, ["reviewed-recipe", "dependency", "xact", item.revision])
    }
    func testIdentityAndUnsupportedPayloadsCannotRun() throws {
        for text in ["TYPE=fix\nID=xact\nWINETRICKS=xact", "TYPE=dependency\nID=other\nWINETRICKS=xact", "TYPE=dependency\nID=xact\nWINETRICKS=xact;other"] {
            XCTAssertNotNil(try parse(text).unsupportedReason)
        }
    }
    func testDestructiveAndParameterDependentFixesStayInDedicatedTools() throws {
        for script in ["rebuild_prefix", "set_backend", "kill_wine", "dll_override"] {
            XCTAssertNotNil(try parse("TYPE=fix\nID=test\nSCRIPT=\(script)", id: "test", kind: .fix).unsupportedReason)
        }
        XCTAssertNil(try parse("TYPE=fix\nID=test\nSCRIPT=dll_override\nDLL_OVERRIDE=ddraw=n,b", id: "test", kind: .fix).unsupportedReason)
    }
    func testCommandScopeCarriesSelectedEnvironmentAndRuntime() {
        let bottle = Bottle(id: "legacy", settings: ["WINE_VERSION": "10.0"], prefixURL: URL(fileURLWithPath: "/Fixture/legacy/prefix"), isInitialized: true, steamInstalled: false)
        let target = WorkspaceEnvironment.catalog(bottles: [bottle], ports: [], main: .defaults, mainInitialized: false)[1]
        let request = EnvironmentToolsRequest(environment: target, runtimeRoot: "/Fixture/Wine 10")
        XCTAssertEqual(request.commandEnvironment["WINEPREFIX"], bottle.prefixURL.path)
        XCTAssertEqual(request.commandEnvironment["COSMOS_BOTTLE"], "legacy")
        XCTAssertEqual(request.commandEnvironment["WINE_VERSION"], "10.0")
        XCTAssertEqual(request.commandEnvironment["WINE_ROOT"], "/Fixture/Wine 10")
    }
    func testDependencyReviewDoesNotRequireSteamOrAnInitializedPrefix() {
        let environment = WorkspaceEnvironment.catalog(bottles: [], ports: [], main: .defaults, mainInitialized: false)[0]
        XCTAssertNil(WorkspaceEnvironmentContext(selected: environment, busy: false, modalPresented: false, installHostIssue: "Unsupported host").disabledReason(.dependencies))
    }
}
