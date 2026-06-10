import Foundation

/// Advanced graphics and performance settings stored in `steam.conf` / `bottle.conf`.
struct GraphicsSettings: Equatable {
    var syncMode: String
    var gptkPath: String
    var dxmtChannel: String
    var metalFXEnabled: Bool
    var moltenvkPreset: String

    static let defaults = GraphicsSettings(
        syncMode: "off",
        gptkPath: "",
        dxmtChannel: "stable",
        metalFXEnabled: false,
        moltenvkPreset: "default"
    )

    static let syncModeOptions = ["off", "esync", "msync"]
    static let dxmtChannelOptions = ["stable", "latest"]
    static let moltenvkPresetOptions = ["default", "performance", "compatibility"]

    var syncModeLabel: String {
        switch syncMode {
        case "esync": return "esync — lower CPU overhead for multiplayer"
        case "msync": return "msync — newer Wine sync (experimental on macOS)"
        default: return "off — Wine default"
        }
    }

    var gptkConfigured: Bool {
        !gptkPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct GptkValidationResult: Equatable {
    let valid: Bool
    let path: String
    let dllDirectory: String
    let dllCount: Int
    let errorMessage: String

    static let empty = GptkValidationResult(
        valid: false, path: "", dllDirectory: "", dllCount: 0,
        errorMessage: "No GPTK path set"
    )
}

enum GraphicsSettingsStore {
    static func load(from stored: [String: String]) -> GraphicsSettings {
        var settings = GraphicsSettings.defaults
        if let mode = stored["COSMOS_SYNC_MODE"], GraphicsSettings.syncModeOptions.contains(mode) {
            settings.syncMode = mode
        } else if stored["WINEESYNC"] == "1" {
            settings.syncMode = "esync"
        } else if stored["WINEMSYNC"] == "1" {
            settings.syncMode = "msync"
        }
        settings.gptkPath = stored["GPTK_PATH"] ?? ""
        if let channel = stored["COSMOS_DXMT_CHANNEL"] {
            let normalized = channel == "experimental" ? "latest" : channel
            if GraphicsSettings.dxmtChannelOptions.contains(normalized) {
                settings.dxmtChannel = normalized
            }
        }
        settings.metalFXEnabled = stored["COSMOS_METALFX"] == "1"
        if let preset = stored["COSMOS_MVK_PRESET"],
           GraphicsSettings.moltenvkPresetOptions.contains(preset) {
            settings.moltenvkPreset = preset
        }
        return settings
    }

    static func loadSteam() -> GraphicsSettings {
        SteamSettingsStore.ensureOnDisk()
        return load(from: BottleStore.parseConf(SteamSettingsStore.confURL))
    }

    static func parseGptkValidation(_ output: String) -> GptkValidationResult {
        var valid = false
        var path = ""
        var dllDir = ""
        var dllCount = 0
        var error = ""
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq])
            let value = String(trimmed[trimmed.index(after: eq)...])
            switch key {
            case "valid": valid = value == "1"
            case "path": path = value
            case "dll_dir": dllDir = value
            case "dll_count": dllCount = Int(value) ?? 0
            case "error": error = value
            default: break
            }
        }
        return GptkValidationResult(
            valid: valid,
            path: path,
            dllDirectory: dllDir,
            dllCount: dllCount,
            errorMessage: error
        )
    }

    /// Run `run.command --validate-gptk` synchronously (dashboard path picker).
    static func validateGptkPath(
        _ path: String,
        repositoryRoot: URL?,
        fileManager: FileManager = .default
    ) -> GptkValidationResult {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let script = resolveRunCommand(repositoryRoot: repositoryRoot, fileManager: fileManager) else {
            return GptkValidationResult(
                valid: false, path: trimmed, dllDirectory: "", dllCount: 0,
                errorMessage: "run.command not found"
            )
        }
        let task = Process()
        task.executableURL = script
        task.arguments = ["--validate-gptk", trimmed]
        task.currentDirectoryURL = script.deletingLastPathComponent()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return parseGptkValidation(text)
        } catch {
            return GptkValidationResult(
                valid: false, path: trimmed, dllDirectory: "", dllCount: 0,
                errorMessage: error.localizedDescription
            )
        }
    }

    private static func resolveRunCommand(repositoryRoot: URL?, fileManager: FileManager) -> URL? {
        let candidates: [URL?] = [
            repositoryRoot?.appendingPathComponent("run.command"),
            Bundle.main.resourceURL?.appendingPathComponent("run.command"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("run.command"),
        ]
        for url in candidates.compactMap({ $0 }) {
            if fileManager.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}
