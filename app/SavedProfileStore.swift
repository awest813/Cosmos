import Foundation

/// Launcher configs for the sidebar — merges Application Support profiles and
/// generated/imported configs under cosmos_configs/.
enum SavedProfileStore {
    private static let fileManager = FileManager.default

    private static let skippedConfigBasenames: Set<String> = [
        "steam.conf",
        "binding-of-isaac.conf",
        "template.conf.example",
    ]

    static func profilesDirectory() -> URL {
        CosmosPaths.profilesDirectory
    }

    static func configsDirectory() -> URL {
        let support = CosmosPaths.configsDirectory
        if fileManager.fileExists(atPath: support.path) {
            return support
        }
        if let bundled = CosmosPaths.cosmosRoot()?.appendingPathComponent("cosmos_configs", isDirectory: true),
           fileManager.fileExists(atPath: bundled.path) {
            return bundled
        }
        return support
    }

    static func cosmosAppsDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["COSMOS_APPS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let system = URL(fileURLWithPath: "/Applications/Cosmos Apps", isDirectory: true)
        if fileManager.fileExists(atPath: system.path) {
            return system
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Cosmos Apps", isDirectory: true)
    }

    static func cosmosAppsIsInstalled() -> Bool {
        let dir = cosmosAppsDirectory()
        guard fileManager.fileExists(atPath: dir.path) else { return false }
        guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return false }
        return names.contains { $0.hasSuffix(".app") }
    }

    static func countCosmosApps() -> Int {
        let dir = cosmosAppsDirectory()
        guard fileManager.fileExists(atPath: dir.path),
              let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else {
            return 0
        }
        return names.filter { $0.hasSuffix(".app") }.count
    }

    static func load() -> [SavedProfile] {
        var merged: [String: SavedProfile] = [:]

        func ingest(_ url: URL) {
            guard url.pathExtension == "conf" else { return }
            let base = url.lastPathComponent
            if skippedConfigBasenames.contains(base) || base.contains("-template") {
                return
            }
            guard let profile = parseConfig(at: url) else { return }
            merged[profile.id] = profile
        }

        let profileURLs = (try? fileManager.contentsOfDirectory(
            at: profilesDirectory(),
            includingPropertiesForKeys: nil
        )) ?? []
        for url in profileURLs { ingest(url) }

        let configURLs = (try? fileManager.contentsOfDirectory(
            at: configsDirectory(),
            includingPropertiesForKeys: nil
        )) ?? []
        for url in configURLs where merged[url.lastPathComponent] == nil {
            ingest(url)
        }

        return merged.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Parse a Cosmos launcher .conf (install_cosmos / detect_steam_games / import_game).
    static func parseConfig(at fileURL: URL) -> SavedProfile? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        var appName = ""
        var path = ""
        var gameExePath = ""
        var args = ""
        var steamAppID: String?

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix("["),
                  let separatorIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: separatorIndex)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))

            switch key {
            case "APP_NAME", "name":
                if !value.isEmpty { appName = value }
            case "path":
                path = value
            case "GAME_EXE_PATH":
                gameExePath = value
            case "args", "STEAM_GAME_ARGS", "GAME_ARGS":
                if !value.isEmpty { args = value }
            case "STEAM_GAME_ID":
                steamAppID = value
            default:
                break
            }
        }

        if appName.isEmpty {
            appName = fileURL.deletingPathExtension().lastPathComponent
        }

        let launchPath = !path.isEmpty ? path : gameExePath

        return SavedProfile(
            id: fileURL.lastPathComponent,
            name: appName,
            path: launchPath,
            args: args,
            steamAppID: steamAppID,
            fileURL: fileURL
        )
    }
}

struct SavedProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let args: String
    let steamAppID: String?
    let fileURL: URL

    var canLaunchFromDashboard: Bool {
        !path.isEmpty || (steamAppID != nil && !(steamAppID?.isEmpty ?? true))
    }

    var launchMethodLabel: String {
        if !path.isEmpty { return "Direct executable" }
        if steamAppID != nil { return "Steam applaunch" }
        return "Not configured"
    }
}
