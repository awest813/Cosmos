import Foundation

/// Runs `scripts/check_updates.sh --json` and parses the release status.
enum UpdateChecker {
    struct Status: Equatable {
        let appVersion: String
        let runtimeVersion: String
        let latestRelease: String?
        let state: State

        enum State: String, Equatable {
            case current
            case updateAvailable = "update_available"
            case unavailable
            case unknown
        }

        var updateAvailable: Bool { state == .updateAvailable }
    }

    /// Foreground or silent check against GitHub Releases.
    static func check(runScript: URL, timeout: TimeInterval = 20) -> Status? {
        guard let checkScript = resolveCheckScript(near: runScript) else { return nil }

        let task = Process()
        task.executableURL = checkScript
        task.arguments = ["--json"]
        task.currentDirectoryURL = checkScript.deletingLastPathComponent()

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            return nil
        }

        let group = DispatchGroup()
        group.enter()
        var exitCode = -1
        task.terminationHandler = { process in
            exitCode = process.terminationStatus
            group.leave()
        }

        let waitResult = group.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            task.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard exitCode == 0 || exitCode == 2 else { return nil }
        return parse(jsonData: data, exitCode: exitCode)
    }

    private static func resolveCheckScript(near runScript: URL) -> URL? {
        let root = runScript.deletingLastPathComponent()
        let candidates = [
            root.appendingPathComponent("scripts/check_updates.sh"),
            root.deletingLastPathComponent().appendingPathComponent("scripts/check_updates.sh"),
        ]
        let fileManager = FileManager.default
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static func parse(jsonData: Data, exitCode: Int) -> Status? {
        guard
            let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let appVersion = object["app_version"] as? String,
            let runtimeVersion = object["runtime_version"] as? String
        else {
            return nil
        }

        let latest = object["latest_release"] as? String
        let rawState = object["status"] as? String
        let state: Status.State
        if exitCode == 2 {
            state = .updateAvailable
        } else if let rawState, let parsed = Status.State(rawValue: rawState) {
            state = parsed
        } else {
            state = .unknown
        }

        return Status(
            appVersion: appVersion,
            runtimeVersion: runtimeVersion,
            latestRelease: latest,
            state: state
        )
    }
}
