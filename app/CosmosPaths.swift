import Foundation

/// Resolves Cosmos repository / app bundle roots for profiles, recipes, and scripts.
enum CosmosPaths {
    private static let fileManager = FileManager.default

    /// App bundle Resources, or the repository root when running from a dev build.
    static func cosmosRoot(startingAt file: StaticString = #filePath) -> URL? {
        if let resourceURL = Bundle.main.resourceURL,
           fileManager.fileExists(atPath: resourceURL.appendingPathComponent("run.command").path) {
            return resourceURL
        }
        var candidate = URL(fileURLWithPath: String(describing: file)).deletingLastPathComponent()
        while candidate.path != "/" {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("run.command").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        if fileManager.fileExists(atPath: cwd.appendingPathComponent("run.command").path) {
            return cwd
        }
        return nil
    }

    static var profilesDirectory: URL? {
        cosmosRoot()?.appendingPathComponent("profiles", isDirectory: true)
    }

    static var dependencyRecipesDirectory: URL? {
        cosmosRoot()?.appendingPathComponent("recipes/dependencies", isDirectory: true)
    }

    static var fixRecipesDirectory: URL? {
        cosmosRoot()?.appendingPathComponent("recipes/fixes", isDirectory: true)
    }

    static var communityDatabaseDirectory: URL? {
        CosmosBadgeStore.communityGamesDirectory()
    }

    /// User-authored profiles under Application Support (or `COSMOS_SUPPORT_DIR`).
    static var userProfilesDirectory: URL {
        supportDirectory.appendingPathComponent("Profiles", isDirectory: true)
    }

    /// Generated/imported launcher configs under Application Support.
    static var userConfigsDirectory: URL {
        supportDirectory.appendingPathComponent("cosmos_configs", isDirectory: true)
    }

    /// Writable user-data root (`~/Library/Application Support/Cosmos`, or `COSMOS_SUPPORT_DIR`).
    static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["COSMOS_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Cosmos", isDirectory: true)
    }

    /// Path to pass to `profile.command apply` (relative to cosmos root).
    static func profileCommandPath(for fileURL: URL) -> String? {
        guard let root = cosmosRoot() else { return nil }
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return filePath }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}
