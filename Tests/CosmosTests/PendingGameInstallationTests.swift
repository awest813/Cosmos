import XCTest
@testable import Cosmos

final class PendingGameInstallationTests: XCTestCase {
    func testPendingDiscoveryUsesCustomDirectoriesAndHidesRegisteredOrInvalidRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bottles = root.appendingPathComponent("Bottles")
        let ports = root.appendingPathComponent("Ports")
        let environment = bottles.appendingPathComponent("custom-environment")
        try FileManager.default.createDirectory(at: environment, withIntermediateDirectories: true)
        try "".write(to: environment.appendingPathComponent("bottle.conf"), atomically: true, encoding: .utf8)
        func write(_ slug: String, stage: String = "awaiting-game", bottle: String = "custom-environment") throws {
            let text = """
            INSTALL_NAME="\(slug)"
            INSTALL_SLUG="\(slug)"
            INSTALL_BOTTLE="\(bottle)"
            INSTALL_FOLDER="/Volumes/Games/\(slug)"
            INSTALLER_PATH="/Downloads/Setup.exe"
            INSTALL_STAGE="\(stage)"
            """
            try text.write(to: environment.appendingPathComponent("install-\(slug).conf"), atomically: true, encoding: .utf8)
        }
        try write("simcity")
        try write("prepared", stage: "prepared")
        try write("finished", stage: "registered")
        try write("wrong-bottle", bottle: "other")
        try write("already-added")
        let registered = ports.appendingPathComponent("already-added")
        try FileManager.default.createDirectory(at: registered, withIntermediateDirectories: true)
        try "".write(to: registered.appendingPathComponent("port.conf"), atomically: true, encoding: .utf8)
        let records = PendingGameInstallationStore.load(bottlesDirectory: bottles, portsDirectory: ports)
        XCTAssertEqual(records.map(\.slug), ["prepared", "simcity"])
        XCTAssertEqual(records.last?.bottle, "custom-environment")
        XCTAssertEqual(records.last?.folder, "/Volumes/Games/simcity")
    }

    func testContinuingPrefillsTheExactEnvironmentAndPreservesSavedFolderGuard() {
        let pending = PendingGameInstallation(id: "custom/simcity", name: "SimCity 3000 Unlimited", slug: "simcity", bottle: "custom", folder: "/Disconnected/SimCity", installer: "/Downloads/Setup.exe", stage: "awaiting-game")
        let request = StoreImportRequest.classicGame(resuming: true, installation: pending)
        XCTAssertEqual(request.initialValues[.displayName], pending.name)
        XCTAssertNil(request.initialValues[.installDirectory])
        XCTAssertNil(StoreImportValidation.validate(request: request, values: request.initialValues))
        XCTAssertEqual(request.installerArguments(values: request.initialValues), [
            "resume", "--name", pending.name, "--bottle", "custom"
        ])
        let retry = StoreImportRequest.classicGame(installation: pending)
        XCTAssertEqual(retry.installerArguments(values: retry.initialValues).prefix(2), ["install", pending.installer])
        XCTAssertEqual(retry.initialValues[.installationBottle], "custom")
    }
}
