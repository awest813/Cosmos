import Foundation

/// Detects GOG offline installs and unregistered launcher configs.
enum GogLibraryMonitor {
    struct DetectedGame: Equatable {
        let slug: String
        let title: String
        let exe: String
    }

    static func listGames(importScript: URL, environment: [String: String] = [:]) -> [DetectedGame]? {
        guard let scriptURL = resolveImportScript(near: importScript) else { return nil }

        let task = Process()
        task.executableURL = scriptURL
        task.arguments = ["list-gog", "--json"]
        task.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        task.environment = mergedEnvironment(environment)

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = -1
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
        guard let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return nil
        }
        return array.compactMap { item in
            guard let slug = item["slug"] as? String,
                  let title = item["title"] as? String,
                  let exe = item["exe"] as? String else { return nil }
            return DetectedGame(slug: slug, title: title, exe: exe)
        }
    }

    struct SyncResult: Equatable {
        let status: String
        let newCount: Int
        let skippedCount: Int
        let exitCode: Int32
        let output: String

        var succeeded: Bool {
            exitCode == 0 && status != "failed"
        }
    }

    /// Register missing GOG games via `import_game.command sync-gog`.
    static func syncUnregistered(
        importScript: URL,
        environment: [String: String] = [:],
        build: Bool = false,
        timeout: TimeInterval = 600
    ) -> SyncResult? {
        guard let scriptURL = resolveImportScript(near: importScript) else { return nil }

        var args = ["sync-gog"]
        if build { args.append("--build") }

        let task = Process()
        task.executableURL = scriptURL
        task.arguments = args
        task.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        var env = environment
        env["COSMOS_ALLOW_USER_APPS"] = "1"
        task.environment = mergedEnvironment(env)

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = -1
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
        let newCount = parseSyncIntegerField("sync_new", from: output) ?? 0
        let skippedCount = parseSyncIntegerField("sync_skipped", from: output) ?? 0
        return SyncResult(
            status: status,
            newCount: newCount,
            skippedCount: skippedCount,
            exitCode: exitCode,
            output: output
        )
    }

    static func parseSyncStatus(from output: String) -> String? {
        parseLineField("sync_status", from: output)
    }

    static func parseSyncIntegerField(_ field: String, from output: String) -> Int? {
        guard let value = parseLineField(field, from: output) else { return nil }
        return Int(value)
    }

    private static func parseLineField(_ field: String, from output: String) -> String? {
        let prefix = "\(field)="
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.hasPrefix(prefix) {
                return String(text.dropFirst(prefix.count))
            }
        }
        return nil
    }

    /// GOG games on disk without a matching `gog-<slug>.conf` launcher config.
    static func unregistered(games: [DetectedGame], configsDirectory: URL) -> [DetectedGame] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: configsDirectory.path) else {
            return games
        }
        let registered = Set(
            names
                .filter { $0.hasPrefix("gog-") && $0.hasSuffix(".conf") }
                .map { String($0.dropFirst(4).dropLast(5)) }
        )
        return games.filter { !registered.contains($0.slug) }
    }

    private static func mergedEnvironment(_ overrides: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "COSMOS_BOTTLE")
        for (key, value) in overrides {
            env[key] = value
        }
        return env
    }

    private static func resolveImportScript(near script: URL) -> URL? {
        let root = script.deletingLastPathComponent()
        let candidates = [
            root.appendingPathComponent("import_game.command"),
            root.deletingLastPathComponent().appendingPathComponent("import_game.command"),
        ]
        let fileManager = FileManager.default
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
