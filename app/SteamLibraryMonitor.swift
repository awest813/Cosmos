import Foundation

/// Compares the Steam library snapshot to detect newly installed games.
enum SteamLibraryMonitor {
    struct DetectedGame: Equatable {
        let appID: String
        let name: String
    }

    struct SyncResult: Equatable {
        let status: String
        let newCount: Int
        let output: String
    }

    static func snapshotURL() -> URL {
        let base: URL
        if let override = ProcessInfo.processInfo.environment["COSMOS_SUPPORT_DIR"], !override.isEmpty {
            base = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            return base.appendingPathComponent("Cosmos/steam-library.snapshot")
        }
        return base.appendingPathComponent("steam-library.snapshot")
    }

    /// List installed Steam games as JSON via detect_steam_games.command --list --json.
    static func listInstalledGames(detectScript: URL, environment: [String: String] = [:]) -> [DetectedGame]? {
        guard let scriptURL = resolveDetectScript(near: detectScript) else { return nil }

        let task = Process()
        task.executableURL = scriptURL
        task.arguments = ["--list", "--json"]
        task.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment { env[key] = value }
        task.environment = env

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        let semaphore = DispatchSemaphore(value: 0)
        var exitCode = -1
        task.terminationHandler = { process in
            exitCode = process.terminationStatus
            semaphore.signal()
        }

        do {
            try task.run()
        } catch {
            return nil
        }

        guard semaphore.wait(timeout: .now() + 60) != .timedOut else {
            task.terminate()
            return nil
        }

        guard exitCode == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return parseGameList(jsonData: data)
    }

    static func parseGameList(jsonData: Data) -> [DetectedGame]? {
        guard
            let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
        else { return nil }
        return array.compactMap { item in
            guard let appID = item["appid"] as? String, let name = item["name"] as? String else { return nil }
            return DetectedGame(appID: appID, name: name)
        }
    }

    static func loadSnapshotAppIDs() -> Set<String> {
        let url = snapshotURL()
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(
            text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func newGames(comparedTo snapshot: Set<String>, current: [DetectedGame]) -> [DetectedGame] {
        current.filter { !snapshot.contains($0.appID) }
    }

    /// Run detect_steam_games.command --sync (writes configs + builds launchers for new titles only).
    static func syncNewGames(detectScript: URL, environment: [String: String] = [:], timeout: TimeInterval = 600) -> SyncResult? {
        guard let scriptURL = resolveDetectScript(near: detectScript) else { return nil }

        let task = Process()
        task.executableURL = scriptURL
        task.arguments = ["--sync"]
        task.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        env["COSMOS_ALLOW_USER_APPS"] = "1"
        for (key, value) in environment { env[key] = value }
        task.environment = env

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        let semaphore = DispatchSemaphore(value: 0)
        var exitCode = -1
        task.terminationHandler = { process in
            exitCode = process.terminationStatus
            semaphore.signal()
        }

        do {
            try task.run()
        } catch {
            return nil
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let status = parseSyncStatus(from: output) ?? (exitCode == 0 ? "current" : "failed")
        let newCount = parseSyncNewCount(from: output) ?? 0
        return SyncResult(status: status, newCount: newCount, output: output)
    }

    static func parseSyncStatus(from output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.hasPrefix("sync_status=") {
                return String(text.dropFirst("sync_status=".count))
            }
        }
        return nil
    }

    static func parseSyncNewCount(from output: String) -> Int? {
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.hasPrefix("sync_new=") {
                return Int(text.dropFirst("sync_new=".count))
            }
        }
        return nil
    }

    private static func resolveDetectScript(near script: URL) -> URL? {
        let root = script.deletingLastPathComponent()
        let candidates = [
            root.appendingPathComponent("detect_steam_games.command"),
            root.deletingLastPathComponent().appendingPathComponent("detect_steam_games.command"),
        ]
        let fileManager = FileManager.default
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
