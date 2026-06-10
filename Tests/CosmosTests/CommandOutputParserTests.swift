import XCTest
@testable import Cosmos

final class CommandOutputParserTests: XCTestCase {
    func testLastErrorMessage() {
        let output = """
        ==> Downloading Wine
        curl: (6) Could not resolve host
        Error: Wine download failed. Check your network connection and try again.
        """
        XCTAssertEqual(
            CommandOutputParser.lastErrorMessage(from: output),
            "Wine download failed. Check your network connection and try again."
        )
    }

    func testSuggestedFixCount() {
        let output = """
        Suggested fixes (3):

        [prefix] Missing VC++ runtime
        """
        XCTAssertEqual(CommandOutputParser.suggestedFixCount(from: output), 3)
    }

    func testDiagnoseSummaryWithIssues() {
        let output = "Suggested fixes (2):\n\n[item]"
        XCTAssertEqual(
            CommandOutputParser.diagnoseSummary(from: output),
            "Diagnosis found 2 issues. Review the output below or apply safe fixes."
        )
    }

    func testFailureMessageUsesScriptError() {
        let message = CommandOutputParser.failureMessage(
            exitCode: 1,
            intent: .general,
            output: "Error: steam.exe not found.\n"
        )
        XCTAssertEqual(message, "steam.exe not found.")
    }

    func testTrimPreservesErrorLines() {
        let long = String(repeating: "x", count: 130_000)
        let output = "Error: first failure\n\(long)"
        let result = CommandOutputParser.trimPreservingErrors(output)
        XCTAssertTrue(result.trimmed)
        XCTAssertTrue(result.text.contains("Error: first failure"))
    }
}
