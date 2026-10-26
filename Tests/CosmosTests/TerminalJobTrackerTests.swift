import XCTest
@testable import Cosmos

final class TerminalJobTrackerTests: XCTestCase {
    func testTerminalHandoffUsesResolvedRootsAndKeepsTrackingInAppSupport() {
        let result = TerminalJobTracker.handoffEnvironment(
            app: ["WINE_VERSION": "11.8", "COSMOS_RUNTIME_DIR": "/App Runtime", "UNRELATED_SECRET": "not forwarded", "COSMOS_BOTTLE": "stale"],
            roots: ["COSMOS_SUPPORT_DIR": "/App Support", "COSMOS_BOTTLES_DIR": "/App Bottles", "COSMOS_PORTS_DIR": "/App Ports"],
            explicit: ["COSMOS_BOTTLE": "selected", "WINEPREFIX": "/Selected Prefix", "COSMOS_SUPPORT_DIR": "/Wrong Tracking"])
        XCTAssertEqual(result["COSMOS_BOTTLES_DIR"], "/App Bottles")
        XCTAssertEqual(result["COSMOS_PORTS_DIR"], "/App Ports")
        XCTAssertEqual(result["COSMOS_SUPPORT_DIR"], "/App Support")
        XCTAssertEqual(result["COSMOS_BOTTLE"], "selected")
        XCTAssertEqual(result["WINEPREFIX"], "/Selected Prefix")
        XCTAssertEqual(result["WINE_VERSION"], "11.8")
        XCTAssertNil(result["UNRELATED_SECRET"])
        XCTAssertTrue(TerminalJobTracker.handoffResetKeys.contains("WINEPREFIX"))
        XCTAssertTrue(TerminalJobTracker.handoffResetKeys.contains("COSMOS_BOTTLES_DIR"))
    }
    private var supportDir: URL!

    override func setUpWithError() throws {
        supportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cosmos-terminal-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        setenv("COSMOS_SUPPORT_DIR", supportDir.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("COSMOS_SUPPORT_DIR")
        try? FileManager.default.removeItem(at: supportDir)
    }

    func testWrappedShellCommandIncludesJobAndWrapper() {
        let command = TerminalJobTracker.wrappedShellCommand(
            jobID: "abc-123",
            wrapScriptPath: "/tmp/terminal_wrap.sh",
            innerCommand: "/tmp/run.command --status",
            label: "run.command --status"
        )
        XCTAssertTrue(command.contains("abc-123"))
        XCTAssertTrue(command.contains("terminal_wrap.sh"))
        XCTAssertTrue(command.contains("COSMOS_SUPPORT_DIR="))
        XCTAssertTrue(command.contains("COSMOS_TERMINAL_LABEL="))
        XCTAssertTrue(command.contains("run.command"))
    }

    func testExportsAndHelperRemainInsideTrackedShellWithLiteralValues() throws {
        let root = try XCTUnwrap(CosmosPaths.cosmosRoot())
        let marker = supportDir.appendingPathComponent("result with spaces")
        let value = "Folder with spaces, 'quotes', $(must-stay-literal)"
        let inner = "export COSMOS_BOTTLES_DIR=\(ShellArgumentParser.shellQuote(value)); printf '%s' \"$COSMOS_BOTTLES_DIR\" > \(ShellArgumentParser.shellQuote(marker.path)); exit 7"
        let command = TerminalJobTracker.wrappedShellCommand(jobID: "shell-contract",
            wrapScriptPath: root.appendingPathComponent("scripts/terminal_wrap.sh").path, innerCommand: inner, label: "fixture only")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        _ = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 7)
        XCTAssertEqual(TerminalJobTracker.readExitCode(jobID: "shell-contract"), 7)
        XCTAssertEqual(try String(contentsOf: marker), value)
    }

    func testCompletedJobsAwaitingDelivery() throws {
        let jobID = "completed-\(UUID().uuidString)"
        try TerminalJobTracker.prepareJobsDirectory()
        defer { TerminalJobTracker.cleanup(jobID: jobID) }

        let meta = TerminalJobTracker.jobsDirectory.appendingPathComponent("\(jobID).meta")
        try "label=install rosetta\n".write(to: meta, atomically: true, encoding: .utf8)
        try "0\n".write(to: TerminalJobTracker.exitFileURL(for: jobID), atomically: true, encoding: .utf8)

        let jobs = TerminalJobTracker.completedJobsAwaitingDelivery()
        XCTAssertTrue(jobs.contains { $0.id == jobID && $0.exitCode == 0 && $0.label == "install rosetta" })
    }

    func testClaimDeliveryIsIdempotent() throws {
        let jobID = "claim-\(UUID().uuidString)"
        try TerminalJobTracker.prepareJobsDirectory()
        defer { TerminalJobTracker.cleanup(jobID: jobID) }

        XCTAssertTrue(TerminalJobTracker.claimDelivery(jobID: jobID))
        XCTAssertFalse(TerminalJobTracker.claimDelivery(jobID: jobID))
    }

    func testDeliveredJobsExcludedFromCompletedScan() throws {
        let jobID = "delivered-\(UUID().uuidString)"
        try TerminalJobTracker.prepareJobsDirectory()
        defer { TerminalJobTracker.cleanup(jobID: jobID) }

        try "1\n".write(to: TerminalJobTracker.exitFileURL(for: jobID), atomically: true, encoding: .utf8)
        XCTAssertTrue(TerminalJobTracker.claimDelivery(jobID: jobID))

        let jobs = TerminalJobTracker.completedJobsAwaitingDelivery()
        XCTAssertFalse(jobs.contains { $0.id == jobID })
    }

    func testReadExitCodeFromFile() throws {
        let jobID = "unit-test-\(UUID().uuidString)"
        try TerminalJobTracker.prepareJobsDirectory()
        defer { TerminalJobTracker.cleanup(jobID: jobID) }

        let exitURL = TerminalJobTracker.exitFileURL(for: jobID)
        try "42\n".write(to: exitURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(TerminalJobTracker.readExitCode(jobID: jobID), 42)
    }
}
