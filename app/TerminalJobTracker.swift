import Foundation

/// Tracks Terminal-launched helpers via exit-status files under Application Support.
/// Uses the same file-based IPC pattern as common MIT shell wrappers (no GPL coupling).
enum TerminalJobTracker {
    private static let fileManager = FileManager.default

    static var jobsDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Cosmos/terminal-jobs", isDirectory: true)
    }

    static func makeJobID() -> String {
        UUID().uuidString.lowercased()
    }

    static func prepareJobsDirectory() throws {
        try fileManager.createDirectory(at: jobsDirectory, withIntermediateDirectories: true)
    }

    static func exitFileURL(for jobID: String) -> URL {
        jobsDirectory.appendingPathComponent("\(jobID).exit")
    }

    static func cleanup(jobID: String) {
        for suffix in ["exit", "state", "meta"] {
            try? fileManager.removeItem(at: jobsDirectory.appendingPathComponent("\(jobID).\(suffix)"))
        }
    }

    /// Build a shell command that runs `innerCommand` through `terminal_wrap.sh`.
    static func wrappedShellCommand(
        jobID: String,
        wrapScriptPath: String,
        innerCommand: String
    ) -> String {
        let support = jobsDirectory.deletingLastPathComponent().path
        return [
            "export COSMOS_SUPPORT_DIR=\(ShellArgumentParser.shellQuote(support))",
            "\(ShellArgumentParser.shellQuote(wrapScriptPath)) \(ShellArgumentParser.shellQuote(jobID)) -- \(innerCommand)",
        ].joined(separator: "; ")
    }

    static func readExitCode(jobID: String) -> Int? {
        let url = exitFileURL(for: jobID)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed)
    }

    /// Poll until the job writes its exit file or the timeout elapses.
    static func poll(
        jobID: String,
        interval: TimeInterval = 1.0,
        timeout: TimeInterval = 3600,
        onComplete: @escaping (Int?) -> Void
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        func tick() {
            if let code = readExitCode(jobID: jobID) {
                onComplete(code)
                return
            }
            if Date() >= deadline {
                onComplete(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: tick)
        }
        tick()
    }
}
