import Foundation

/// Favorites and recent launches for the sidebar (persisted under Application Support).
enum ProfilePreferencesStore {
    private static let fileName = "profile-preferences.json"
    private static let maxRecent = 12

    struct Preferences: Codable, Equatable {
        var favoriteIDs: [String]
        var recentIDs: [String]
    }

    private static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["COSMOS_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Cosmos", isDirectory: true)
    }

    private static var fileURL: URL {
        supportDirectory.appendingPathComponent(fileName)
    }

    static func load() -> Preferences {
        guard let data = try? Data(contentsOf: fileURL),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences(favoriteIDs: [], recentIDs: [])
        }
        return prefs
    }

    static func save(_ preferences: Preferences) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(preferences)
        try data.write(to: fileURL, options: .atomic)
    }

    static func toggleFavorite(profileID: String) -> Preferences {
        var prefs = load()
        if let index = prefs.favoriteIDs.firstIndex(of: profileID) {
            prefs.favoriteIDs.remove(at: index)
        } else {
            prefs.favoriteIDs.append(profileID)
            prefs.favoriteIDs.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        try? save(prefs)
        return prefs
    }

    static func recordRecentLaunch(profileID: String) -> Preferences {
        var prefs = load()
        prefs.recentIDs.removeAll { $0 == profileID }
        prefs.recentIDs.insert(profileID, at: 0)
        if prefs.recentIDs.count > maxRecent {
            prefs.recentIDs = Array(prefs.recentIDs.prefix(maxRecent))
        }
        try? save(prefs)
        return prefs
    }

    static func isFavorite(profileID: String, in preferences: Preferences) -> Bool {
        preferences.favoriteIDs.contains(profileID)
    }
}
