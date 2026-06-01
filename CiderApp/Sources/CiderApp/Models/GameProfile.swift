import Foundation

/// A single game profile with per-game Wine/DXMT settings.
struct GameProfile: Identifiable, Codable, Equatable {
    var id: String { slug }

    /// URL-safe identifier, e.g. "binding-of-isaac".
    var slug: String
    /// Display name shown in the UI and in generated `.app` launchers.
    var displayName: String
    /// Steam App ID (numeric string). Empty means "launch Steam without -applaunch".
    var steamGameID: String
    /// D3D translation backend. "dxmt" (default) or "gptk".
    var backend: String
    /// Whether Wine Retina mode is enabled.
    var retina: Bool
    /// Mouse warp override: "" (default), "force", "enable", or "disable".
    var mouseWarp: String
    /// Extra environment variables passed to `run.command`, one `KEY=VALUE` per entry.
    var envOverrides: [String]
    /// Free-form notes visible in the UI (compatibility tips, known issues, etc.).
    var notes: String

    init(
        slug: String,
        displayName: String,
        steamGameID: String = "",
        backend: String = "dxmt",
        retina: Bool = false,
        mouseWarp: String = "",
        envOverrides: [String] = [],
        notes: String = ""
    ) {
        self.slug = slug
        self.displayName = displayName
        self.steamGameID = steamGameID
        self.backend = backend
        self.retina = retina
        self.mouseWarp = mouseWarp
        self.envOverrides = envOverrides
        self.notes = notes
    }
}

// MARK: - Persistence

extension GameProfile {
    /// Directory where user profiles are stored.
    static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Cider/Profiles", isDirectory: true)
    }

    /// Load all saved profiles from disk.
    static func loadAll() -> [GameProfile] {
        let dir = storageDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(GameProfile.self, from: data)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Save this profile to disk.
    func save() throws {
        let dir = Self.storageDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(slug).json")
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Delete this profile from disk.
    func delete() throws {
        let url = Self.storageDirectory.appendingPathComponent("\(slug).json")
        try FileManager.default.removeItem(at: url)
    }
}
