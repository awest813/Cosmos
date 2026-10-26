import XCTest
@testable import Cosmos

final class TerminalHandoffRunnerTests: XCTestCase {
    func testRejectedHandoffIncludesErrorInsteadOfReportingStarted() {
        let done = expectation(description: "rejected")
        TerminalHandoffRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'permission denied' >&2; exit 1"], directory: FileManager.default.temporaryDirectory) { failure in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertTrue(failure?.contains("permission denied") == true)
                XCTAssertTrue(failure?.contains("exit 1") == true)
                done.fulfill()
            }
        wait(for: [done], timeout: 10)
    }
    func testAcceptedHandoffOnlyMeansAppleScriptAcceptedCommand() {
        let done = expectation(description: "accepted")
        TerminalHandoffRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'fixture acceptance'; exit 0"], directory: FileManager.default.temporaryDirectory) { failure in
                XCTAssertNil(failure); done.fulfill()
            }
        wait(for: [done], timeout: 10)
    }
    func testLargeFailureOutputIsDrainedAndReportBounded() {
        let done = expectation(description: "bounded failure")
        TerminalHandoffRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "i=0; while [ $i -lt 6000 ]; do printf 'fixture diagnostic output line\\n' >&2; i=$((i+1)); done; exit 2"],
            directory: FileManager.default.temporaryDirectory) { failure in
                XCTAssertNotNil(failure); XCTAssertLessThan(failure?.count ?? 0, 17000); done.fulfill()
            }
        wait(for: [done], timeout: 15)
    }
}
