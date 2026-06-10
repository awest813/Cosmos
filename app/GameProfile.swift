import Foundation

/// Curated v0 YAML profile from `profiles/` (roadmap 0.4).
struct GameProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let store: String
    let steamAppID: String
    let status: String
    let recommendedBackend: String
    let notes: String
    let dependencyCount: Int
    let fixCount: Int
    let fileURL: URL
    /// Relative path for `profile.command apply`.
    let commandRelativePath: String

    var statusLabel: String {
        status.isEmpty ? "unknown" : status
    }

    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum GameProfileStore {
    private static let fileManager = FileManager.default

    static func load() -> [GameProfile] {
        guard let root = CosmosPaths.profilesDirectory else { return [] }
        guard let storeDirs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let shippedStores: Set<String> = ["steam", "gog", "itch", "battlenet", "standalone"]
        var profiles: [GameProfile] = []
        for storeDir in storeDirs where shippedStores.contains(storeDir.lastPathComponent) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: storeDir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            guard let files = try? fileManager.contentsOfDirectory(
                at: storeDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for file in files where ["yaml", "yml"].contains(file.pathExtension) {
                if let profile = parse(file) {
                    profiles.append(profile)
                }
            }
        }

        return profiles.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func find(steamAppID: String) -> GameProfile? {
        load().first { $0.steamAppID == steamAppID }
    }

    private static func parse(_ url: URL) -> GameProfile? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let id = scalar(in: text, key: "id") ?? url.deletingPathExtension().lastPathComponent
        let name = scalar(in: text, key: "name") ?? id
        let store = scalar(in: text, key: "store") ?? "steam"
        let appid = scalar(in: text, key: "steam_appid") ?? ""
        let status = scalar(in: text, key: "status") ?? "playable"
        let backend = scalar(in: text, key: "recommended_backend") ?? "recommended"
        let notes = scalar(in: text, key: "notes") ?? ""
        let deps = listItems(in: text, section: "dependencies")
        let fixes = listItems(in: text, section: "fixes")
        let relative = CosmosPaths.profileCommandPath(for: url) ?? url.path
        return GameProfile(
            id: id,
            name: name,
            store: store,
            steamAppID: appid,
            status: status,
            recommendedBackend: backend,
            notes: notes,
            dependencyCount: deps.count,
            fixCount: fixes.count,
            fileURL: url,
            commandRelativePath: relative
        )
    }

    private static func listItems(in text: String, section: String) -> [String] {
        var items: [String] = []
        var inSection = false
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "\(section):" {
                inSection = true
                continue
            }
            if inSection {
                if trimmed.hasPrefix("- ") {
                    var item = String(trimmed.dropFirst(2))
                    if item.hasPrefix("\""), item.hasSuffix("\""), item.count >= 2 {
                        item = String(item.dropFirst().dropLast())
                    }
                    items.append(item)
                } else if !trimmed.isEmpty, !trimmed.hasPrefix("#"), !line.hasPrefix("  ") {
                    break
                }
            }
        }
        return items
    }

    private static func scalar(in text: String, key: String) -> String? {
        let pattern = "(?m)^\(NSRegularExpression.escapedPattern(for: key)):[[:space:]]*(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        var value = String(text[valueRange]).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }
}
