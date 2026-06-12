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
