import Foundation

/// Tracks Terminal-launched helpers via exit-status files under Application Support.
/// Uses the same file-based IPC pattern as common MIT shell wrappers (no GPL coupling).
enum TerminalJobTracker {
    private static let fileManager = FileManager.default
    private static let trackedJobIDKey = "com.cosmos.pendingTerminalJobID"
    private static let trackedJobLabelKey = "com.cosmos.pendingTerminalJobLabel"
    private static var pollTokens: [String: UUID] = [:]

    struct TrackedJob: Equatable {
        let id: String
        let label: String
    }

    struct CompletedJob: Equatable {
        let id: String
        let label: String
        let exitCode: Int
    }

    static var jobsDirectory: URL {
        if let support = ProcessInfo.processInfo.environment["COSMOS_SUPPORT_DIR"], !support.isEmpty {
            return URL(fileURLWithPath: support, isDirectory: true)
                .appendingPathComponent("terminal-jobs", isDirectory: true)
        }
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

    private static func deliveredFileURL(for jobID: String) -> URL {
        jobsDirectory.appendingPathComponent("\(jobID).delivered")
    }

    static func saveTrackedJob(id: String, label: String) {
        UserDefaults.standard.set(id, forKey: trackedJobIDKey)
        UserDefaults.standard.set(label, forKey: trackedJobLabelKey)
    }

    static func loadTrackedJob() -> TrackedJob? {
        guard let id = UserDefaults.standard.string(forKey: trackedJobIDKey) else { return nil }
        let label = UserDefaults.standard.string(forKey: trackedJobLabelKey) ?? id
        return TrackedJob(id: id, label: label)
    }

    static func clearTrackedJob() {
        UserDefaults.standard.removeObject(forKey: trackedJobIDKey)
        UserDefaults.standard.removeObject(forKey: trackedJobLabelKey)
    }

    static func cleanup(jobID: String) {
        cancelPoll(jobID: jobID)
        for suffix in ["exit", "state", "meta", "delivered"] {
            try? fileManager.removeItem(at: jobsDirectory.appendingPathComponent("\(jobID).\(suffix)"))
        }
    }

    /// Returns true only for the first caller that claims delivery for this job.
    static func claimDelivery(jobID: String) -> Bool {
        let url = deliveredFileURL(for: jobID)
        if fileManager.fileExists(atPath: url.path) {
            return false
        }
        return fileManager.createFile(atPath: url.path, contents: Data("1".utf8), attributes: nil)
    }

    static func readLabel(jobID: String) -> String? {
        let meta = jobsDirectory.appendingPathComponent("\(jobID).meta")
        guard let text = try? String(contentsOf: meta, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            if line.hasPrefix("label=") {
                return String(line.dropFirst("label=".count))
            }
        }
        return nil
    }

    /// Build a shell command that runs `innerCommand` through `terminal_wrap.sh`.
    static func wrappedShellCommand(
        jobID: String,
        wrapScriptPath: String,
        innerCommand: String,
        label: String
    ) -> String {
        let support = jobsDirectory.deletingLastPathComponent().path
        return [
            "export COSMOS_SUPPORT_DIR=\(ShellArgumentParser.shellQuote(support))",
            "export COSMOS_TERMINAL_LABEL=\(ShellArgumentParser.shellQuote(label))",
            "\(ShellArgumentParser.shellQuote(wrapScriptPath)) \(ShellArgumentParser.shellQuote(jobID)) -- \(innerCommand)",
        ].joined(separator: "; ")
    }

    static func readExitCode(jobID: String) -> Int? {
        let url = exitFileURL(for: jobID)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed)
    }

    /// Jobs that finished while the app was inactive (or after a relaunch).
    static func completedJobsAwaitingDelivery() -> [CompletedJob] {
        guard let entries = try? fileManager.contentsOfDirectory(at: jobsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .filter { $0.pathExtension == "exit" }
            .compactMap { url -> CompletedJob? in
                let id = url.deletingPathExtension().lastPathComponent
                if fileManager.fileExists(atPath: deliveredFileURL(for: id).path) {
                    return nil
                }
                guard let exitCode = readExitCode(jobID: id) else { return nil }
                let label = readLabel(jobID: id) ?? loadTrackedJob()?.label ?? id
                return CompletedJob(id: id, label: label, exitCode: exitCode)
            }
            .sorted { $0.id < $1.id }
    }

    static func cancelPoll(jobID: String) {
        pollTokens.removeValue(forKey: jobID)
    }

    /// Poll until the job writes its exit file or the timeout elapses.
    static func poll(
        jobID: String,
        interval: TimeInterval = 1.0,
        timeout: TimeInterval = 3600,
        onComplete: @escaping (Int?) -> Void
    ) {
        let token = UUID()
        pollTokens[jobID] = token
        let deadline = Date().addingTimeInterval(timeout)
        func tick() {
            guard pollTokens[jobID] == token else { return }
            if let code = readExitCode(jobID: jobID) {
                pollTokens.removeValue(forKey: jobID)
                onComplete(code)
                return
            }
            if Date() >= deadline {
                pollTokens.removeValue(forKey: jobID)
                onComplete(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: tick)
        }
        tick()
    }
}
