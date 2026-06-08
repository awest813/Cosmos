import Foundation

/// Persistent settings for the default Steam Wine prefix (`~/.wine-steam-11`).
/// Stored in `~/Library/Application Support/Cosmos/steam.conf` and loaded by
/// `run.command` when no named bottle (`COSMOS_BOTTLE`) is active.
struct SteamSettings: Equatable {
    var backend: String
    var windowsVersion: String
    var retinaEnabled: Bool
    var detachEnabled: Bool
    var silentInstallEnabled: Bool
    var wineVersion: String

    static let defaults = SteamSettings(
        backend: "recommended",
        windowsVersion: "",
        retinaEnabled: false,
        detachEnabled: true,
        silentInstallEnabled: true,
        wineVersion: "11.8"
    )

    var prefixURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".wine-steam-11", isDirectory: true)
    }

    var steamExecutableURL: URL {
        prefixURL
            .appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
    }

    var isSteamInstalled: Bool {
        let fileManager = FileManager.default
        let steam32 = steamExecutableURL
        let steam64 = prefixURL
            .appendingPathComponent("drive_c/Program Files/Steam/steam.exe")
        return fileManager.fileExists(atPath: steam32.path)
            || fileManager.fileExists(atPath: steam64.path)
    }

    var isPrefixInitialized: Bool {
        FileManager.default.fileExists(
            atPath: prefixURL.appendingPathComponent("system.reg").path)
    }

    var statusText: String {
        guard isPrefixInitialized else { return "Not created" }
        return isSteamInstalled ? "Ready (Steam installed)" : "Initialized"
    }

    var windowsDisplay: String {
        windowsVersion.isEmpty ? "Wine default" : windowsVersion
    }
}

enum SteamSettingsStore {
    static var supportDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cosmos", isDirectory: true)
    }

    static var logsDirectoryURL: URL {
        supportDirectoryURL.appendingPathComponent("logs", isDirectory: true)
    }

    static var defaultLaunchLogURL: URL {
        logsDirectoryURL.appendingPathComponent("steam-launch.log")
    }

    static var confURL: URL {
        supportDirectoryURL.appendingPathComponent("steam.conf")
    }

    static func ensureOnDisk() {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: confURL.path) else { return }
        try? fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        let lines = [
            "# Cosmos default Steam bottle settings. Applied on each launch.",
            "COSMOS_BACKEND=\"recommended\"",
            "COSMOS_DETACH=\"1\"",
            "COSMOS_STEAM_SILENT=\"1\"",
            "STEAM_LAUNCH_ARGS=\"-no-cef-sandbox -cef-single-process\"",
            "WINE_RETINA_MODE=\"0\"",
            "WINDOWS_VERSION=\"\"",
            "WINE_VERSION=\"11.8\"",
            "COSMOS_LAUNCH_LOG=\"\(defaultLaunchLogURL.path)\"",
        ]
        let body = lines.joined(separator: "\n") + "\n"
        try? body.write(to: confURL, atomically: true, encoding: .utf8)
    }

    static let backendOptions = BottleStore.backendOptions
    static let windowsOptions = ["", "winxp", "win7", "win8", "win10", "win11"]

    static func load() -> SteamSettings {
        ensureOnDisk()
        let stored = BottleStore.parseConf(confURL)
        var settings = SteamSettings.defaults
        if let backend = stored["COSMOS_BACKEND"], !backend.isEmpty {
            settings.backend = backend
        }
        if let windows = stored["WINDOWS_VERSION"] {
            settings.windowsVersion = windows
        }
        if let retina = stored["WINE_RETINA_MODE"] {
            settings.retinaEnabled = retina == "1"
        }
        if let detach = stored["COSMOS_DETACH"] {
            settings.detachEnabled = detach == "1"
        }
        if let silent = stored["COSMOS_STEAM_SILENT"] {
            settings.silentInstallEnabled = silent == "1"
        }
        if let wine = stored["WINE_VERSION"], !wine.isEmpty {
            settings.wineVersion = wine
        }
        return settings
    }

    static func set(key: String, value: String) throws {
        try validate(key: key, value: value)
        try writeConf { lines in
            upsert(key: key, value: value, in: &lines)
        }
    }

    static func validate(key: String, value: String) throws {
        guard key.range(of: "^[A-Z][A-Z0-9_]*$", options: .regularExpression) != nil else {
            throw SteamSettingsError.invalidKey(key)
        }
        switch key {
        case "COSMOS_BACKEND":
            guard backendOptions.contains(value) else {
                throw SteamSettingsError.invalidValue("COSMOS_BACKEND must be one of: \(backendOptions.joined(separator: ", "))")
            }
        case "WINDOWS_VERSION":
            guard windowsOptions.contains(value) else {
                throw SteamSettingsError.invalidValue("WINDOWS_VERSION must be empty or one of: winxp, win7, win8, win10, win11")
            }
        case "WINE_RETINA_MODE", "COSMOS_DETACH", "COSMOS_STEAM_SILENT":
            guard value == "0" || value == "1" else {
                throw SteamSettingsError.invalidValue("\(key) must be 0 or 1")
            }
        case "WINEPREFIX", "COSMOS_BOTTLE":
            throw SteamSettingsError.invalidKey("\(key) is managed by Cosmos")
        default:
            break
        }
    }

    private static func writeConf(_ mutate: (inout [String]) -> Void) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)

        var lines: [String] = []
        if fileManager.fileExists(atPath: confURL.path),
           let contents = try? String(contentsOf: confURL, encoding: .utf8) {
            lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        } else {
            lines = ["# Cosmos default Steam bottle settings. Applied on the next launch."]
        }

        mutate(&lines)

        let body = lines.joined(separator: "\n")
        let withNewline = body.hasSuffix("\n") ? body : body + "\n"
        try withNewline.write(to: confURL, atomically: true, encoding: .utf8)
    }

    private static func upsert(key: String, value: String, in lines: inout [String]) {
        let sanitized = value.replacingOccurrences(of: "\"", with: "")
        let replacement = "\(key)=\"\(sanitized)\""
        var found = false
        for index in lines.indices {
            if lines[index].hasPrefix("\(key)=") {
                lines[index] = replacement
                found = true
                break
            }
        }
        if !found {
            lines.append(replacement)
        }
    }
}

enum SteamSettingsError: LocalizedError {
    case invalidKey(String)
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey(let key): return "Invalid setting: \(key)"
        case .invalidValue(let message): return message
        }
    }
}
