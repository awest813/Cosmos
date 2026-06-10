import XCTest
@testable import Cosmos

final class ShellArgumentParserTests: XCTestCase {
    func testEmptyString() {
        XCTAssertEqual(ShellArgumentParser.parse(""), [])
    }

    func testSingleToken() {
        XCTAssertEqual(ShellArgumentParser.parse("game.exe"), ["game.exe"])
    }

    func testWhitespaceSeparated() {
        XCTAssertEqual(ShellArgumentParser.parse("-fullscreen -novid"), ["-fullscreen", "-novid"])
    }

    func testDoubleQuotedGroup() {
        XCTAssertEqual(ShellArgumentParser.parse("\"C:\\Program Files\\Game\\game.exe\""), ["C:\\Program Files\\Game\\game.exe"])
    }

    func testSingleQuotedGroup() {
        XCTAssertEqual(ShellArgumentParser.parse("'-windowed'"), ["-windowed"])
    }

    func testMixedQuotes() {
        XCTAssertEqual(
            ShellArgumentParser.parse("-launch \"My Game\" --lang en"),
            ["-launch", "My Game", "--lang", "en"]
        )
    }

    func testTrailingWhitespaceIgnored() {
        XCTAssertEqual(ShellArgumentParser.parse("  -novid   "), ["-novid"])
    }

    func testShellQuoteEscapesSingleQuotes() {
        XCTAssertEqual(ShellArgumentParser.shellQuote("it's"), "'it'\\''s'")
    }

    func testAppleScriptEscape() {
        XCTAssertEqual(ShellArgumentParser.appleScriptEscape("say \"hi\""), "say \\\"hi\\\"")
    }
}
