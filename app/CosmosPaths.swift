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

    /// Path to pass to `profile.command apply` (relative to cosmos root).
    static func profileCommandPath(for fileURL: URL) -> String? {
        guard let root = cosmosRoot() else { return nil }
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return filePath }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}
