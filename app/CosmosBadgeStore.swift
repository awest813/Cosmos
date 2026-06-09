import Foundation

/// Resolved compatibility badge for dashboard display (CosmosDB 0.7).
struct ResolvedBadge: Equatable {
    let status: String
    let source: String
    let label: String

    var isKnown: Bool { status != "unknown" }
}

enum CosmosBadgeStore {
    private static let fileManager = FileManager.default

    private static var supportCosmosDB: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cosmos/CosmosDB", isDirectory: true)
    }

    static func communityGamesDirectory() -> URL? {
        let synced = supportCosmosDB.appendingPathComponent("community/games", isDirectory: true)
        if fileManager.fileExists(atPath: synced.path) {
            return synced
        }
        return CosmosPaths.cosmosRoot()?.appendingPathComponent("cosmos-db/games", isDirectory: true)
    }

    static func resolve(steamAppID: String, curated: GameProfile?) -> ResolvedBadge {
        if let curated {
            return ResolvedBadge(
                status: curated.statusLabel,
                source: "profile",
                label: curated.name
            )
        }
        if let report = latestLocalReport(steamAppID: steamAppID) {
            return ResolvedBadge(status: report.status, source: "local_report", label: report.label)
        }
        if let entry = communityEntry(steamAppID: steamAppID) {
            return ResolvedBadge(
                status: entry.status,
                source: "community",
                label: entry.title
            )
        }
        return ResolvedBadge(status: "unknown", source: "none", label: "No compatibility data")
    }

    private static func communityEntry(steamAppID: String) -> (status: String, title: String)? {
        guard let dir = communityGamesDirectory() else { return nil }
        let url = dir.appendingPathComponent("\(steamAppID).json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            return nil
        }
        let title = (json["title"] as? String) ?? "Steam App \(steamAppID)"
        return (status, title)
    }

    private static func latestLocalReport(steamAppID: String) -> (status: String, label: String)? {
        let reports = supportCosmosDB.appendingPathComponent("reports", isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: reports,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let matches = files
            .filter { $0.lastPathComponent.hasPrefix("\(steamAppID)-") && $0.pathExtension == "json" }
            .sorted {
                let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d0 > d1
            }
        guard let latest = matches.first,
              let data = try? Data(contentsOf: latest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            return nil
        }
        let note = (json["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = (note?.isEmpty == false) ? note! : latest.lastPathComponent
        return (status, label)
    }
}
