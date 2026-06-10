import Foundation

// A Cosmos bottle as seen by the dashboard: a named directory under
// ~/Library/Application Support/Cosmos/Bottles/ with a bottle.conf and a prefix.
// This mirrors what bottle.command manages; the UI shells out to that script for
// mutations and re-reads the filesystem here for display.
struct Bottle: Identifiable, Hashable {
    let id: String          // the bottle name (its directory name)
    let settings: [String: String]
    let prefixURL: URL
    let isInitialized: Bool
    let steamInstalled: Bool

    var name: String { id }
    var backend: String { settings["COSMOS_BACKEND"] ?? "recommended" }
    var wineVersion: String { settings["WINE_VERSION"] ?? "default" }
    var windowsVersion: String { settings["WINDOWS_VERSION"] ?? "" }

    var windowsDisplay: String {
        windowsVersion.isEmpty ? "Wine default" : windowsVersion
    }
    var retinaEnabled: Bool { settings["WINE_RETINA_MODE"] == "1" }
    var syncMode: String {
        if let mode = settings["COSMOS_SYNC_MODE"], GraphicsSettings.syncModeOptions.contains(mode) {
            return mode
        }
        if settings["WINEESYNC"] == "1" { return "esync" }
        if settings["WINEMSYNC"] == "1" { return "msync" }
        return "off"
    }

    var statusText: String {
        guard isInitialized else { return "Not created" }
        return steamInstalled ? "Ready (Steam installed)" : "Initialized"
    }
}

enum BottleStore {
    static var bottlesDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cosmos/Bottles", isDirectory: true)
    }

    static func load() -> [Bottle] {
        let fileManager = FileManager.default
        let root = bottlesDirectoryURL
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var bottles: [Bottle] = []
        for dir in entries {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            let confURL = dir.appendingPathComponent("bottle.conf")
            let prefixURL = dir.appendingPathComponent("prefix", isDirectory: true)
            let hasConf = fileManager.fileExists(atPath: confURL.path)
            let hasPrefix = fileManager.fileExists(atPath: prefixURL.path)
            guard hasConf || hasPrefix else { continue }

            let settings = parseConf(confURL)
            let initialized = fileManager.fileExists(
                atPath: prefixURL.appendingPathComponent("system.reg").path)
            let steam = fileManager.fileExists(
                atPath: prefixURL.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe").path)
                || fileManager.fileExists(
                    atPath: prefixURL.appendingPathComponent("drive_c/Program Files/Steam/steam.exe").path)

            bottles.append(Bottle(
                id: dir.lastPathComponent,
                settings: settings,
                prefixURL: prefixURL,
                isInitialized: initialized,
                steamInstalled: steam
            ))
        }

        return bottles.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    // Parse the flat KEY="value" bottle.conf into a dictionary.
    static func parseConf(_ url: URL) -> [String: String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

        var result: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separator = line.firstIndex(of: "=") else { continue }

            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    static let backendOptions = ["recommended", "dxmt", "d3dmetal", "dxvk", "wined3d"]
    static let windowsOptions = ["winxp", "win7", "win8", "win10", "win11"]

    // Mirror bottle.command's name validation so the UI can disable invalid input.
    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("..") else { return false }
        return trimmed.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
    }
}
