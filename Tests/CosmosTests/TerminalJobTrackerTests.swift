import XCTest
@testable import Cosmos

final class TerminalJobTrackerTests: XCTestCase {
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
