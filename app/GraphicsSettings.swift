import Foundation

/// Advanced graphics and performance settings stored in `steam.conf` / `bottle.conf`.
struct GraphicsSettings: Equatable {
    var syncMode: String
    var gptkPath: String
    var spockD3D9Path: String
    var dxmtChannel: String
    var metalFXEnabled: Bool
    var moltenvkPreset: String
    var wineDebugPreset: String
    var rosettaAvx: String
    var wineWritecopy: String

    static let defaults = GraphicsSettings(
        syncMode: "off",
        gptkPath: "",
        spockD3D9Path: "",
        dxmtChannel: "stable",
        metalFXEnabled: false,
        moltenvkPreset: "default",
        wineDebugPreset: "cosmos",
        rosettaAvx: "auto",
        wineWritecopy: "auto"
    )

    static let syncModeOptions = ["off", "esync", "msync"]
    static let dxmtChannelOptions = ["stable", "latest"]
    static let moltenvkPresetOptions = ["default", "performance", "compatibility"]
    static let wineDebugPresetOptions = ["cosmos", "moonshine"]
    static let sojuModeOptions = ["auto", "on", "off"]

    static func syncModeTitle(_ mode: String) -> String {
        switch mode {
        case "esync": return "Esync"
        case "msync": return "Msync"
        default: return "Off"
        }
    }

    static func syncModeLabel(for mode: String) -> String {
        switch mode {
        case "esync": return "Lower CPU overhead for multiplayer."
        case "msync": return "Newer Wine sync. Experimental on macOS."
        default: return "Wine's usual setting."
        }
    }

    static func normalizedSojuMode(_ value: String) -> String? {
        switch value {
        case "auto": return "auto"
        case "on", "1": return "on"
        case "off", "0": return "off"
        default: return nil
        }
    }

    var rosettaAvxCaption: String { Self.rosettaAvxCaption(for: rosettaAvx) }
    var wineWritecopyCaption: String { Self.wineWritecopyCaption(for: wineWritecopy) }

    static func rosettaAvxCaption(for mode: String) -> String {
        switch mode {
        case "on":
            return "On for every launch, including Intel."
        case "off":
            return "Rosetta's CPU report stays unchanged."
        default:
            return "On for Apple Silicon. Diablo II: Resurrected waits at launch without it. Intel Macs are unchanged."
        }
    }

    static func wineWritecopyCaption(for mode: String) -> String {
        switch mode {
        case "on":
            return "On for every launch, including Steam."
        case "off":
            return "The login page uses Wine's usual memory setting."
        default:
            return "On for Battle.net, Epic, and GOG, so the login page can draw. Steam is unchanged."
        }
    }

    var syncModeLabel: String { Self.syncModeLabel(for: syncMode) }

    var gptkConfigured: Bool {
        !gptkPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var spockD3D9Configured: Bool {
        !spockD3D9Path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SojuCommandStatus: Equatable {
    var layout: String
    var message: String
    var copiedSo: Bool

    init(layout: String, message: String, copiedSo: Bool = false) {
        self.layout = layout
        self.message = message
        self.copiedSo = copiedSo
    }

    static let empty = SojuCommandStatus(layout: "", message: "")

    var headline: String {
        switch layout {
        case "complete": return "Installed"
        case "partial": return "Incomplete"
        case "missing": return "Not installed"
        case "error": return "Could not update"
        default: return ""
        }
    }

    /// Plain-language status for the graphics page. The raw script line stays in `message`.
    var detail: String {
        switch layout {
        case "complete":
            return "DirectX 12 can use D3DMetal in this Wine install."
        case "partial":
            if copiedSo {
                return "A D3DMetal library was saved as a normal file. Install the layout again so Wine can load it."
            }
            if message.localizedCaseInsensitiveContains("d3d11.dll") {
                return "The Apple download is missing DirectX libraries. Nothing was changed."
            }
            return "D3DMetal is only partly installed. The Metal library, the Windows libraries, and the links between them are all required."
        case "missing":
            if message.localizedCaseInsensitiveContains("download") {
                return "Download Game Porting Toolkit from Apple, then point Cosmos at that folder."
            }
            if message.localizedCaseInsensitiveContains("found") {
                return "Game Porting Toolkit was found. Install the layout when you want DirectX 12."
            }
            return "D3DMetal is not installed in this Wine yet."
        case "error":
            return message.isEmpty ? "The D3DMetal layout could not be updated." : message
        default:
            return message
        }
    }
}

struct OpenGLPatchStatus: Equatable {
    var status: String
    var path: String
    var offset: String
    var byte: String
    var message: String

    static let empty = OpenGLPatchStatus(status: "", path: "", offset: "", byte: "", message: "")

    var headline: String {
        switch status {
        case "patched": return "On"
        case "unpatched": return "Available"
        case "mismatch": return "Left unchanged"
        case "missing": return "Wine not found"
        case "error": return "Could not update"
        default: return ""
        }
    }

    /// Plain-language status for the graphics page. The raw script line stays in `message`.
    var detail: String {
        switch status {
        case "patched":
            return "Games that need an OpenGL 3.2 window can open one."
        case "unpatched":
            return "This Wine build can take the fix. Apply it when a game cannot open a window."
        case "mismatch":
            return "This Wine build is different, so Cosmos left it alone."
        case "missing":
            return "Install Wine, then check again."
        case "error":
            return message.isEmpty ? "The OpenGL check could not be updated." : message
        default:
            return message
        }
    }
}

struct SpockD3D9ValidationResult: Equatable {
    let valid: Bool
    let path: String
    let dllCount: Int
    let x86Dll: String
    let x64Dll: String
    let errorMessage: String

    static let empty = SpockD3D9ValidationResult(
        valid: false, path: "", dllCount: 0, x86Dll: "", x64Dll: "",
        errorMessage: "No SpockD3D9 path set"
    )

    var summaryText: String {
        guard valid else { return errorMessage }
        var parts: [String] = []
        if !x86Dll.isEmpty { parts.append("32-bit") }
        if !x64Dll.isEmpty { parts.append("64-bit") }
        let archLabel = parts.isEmpty ? "\(dllCount) DLL(s)" : parts.joined(separator: " + ")
        let missing = x86Dll.isEmpty ? " Missing 32-bit DLL; 32-bit games cannot use this build." : (x64Dll.isEmpty ? " Missing 64-bit DLL; 64-bit games cannot use this build." : "")
        return "Validated \(archLabel) DLL files.\(missing) Game compatibility is untested."
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
        settings.spockD3D9Path = stored["SPOCK_D3D9_PATH"] ?? ""
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
        if let wineDebug = stored["COSMOS_WINEDEBUG_PRESET"],
           GraphicsSettings.wineDebugPresetOptions.contains(wineDebug) {
            settings.wineDebugPreset = wineDebug
        }
        if let avx = stored["COSMOS_ROSETTA_AVX"], let normalized = GraphicsSettings.normalizedSojuMode(avx) {
            settings.rosettaAvx = normalized
        }
        if let writecopy = stored["COSMOS_WINE_WRITECOPY"], let normalized = GraphicsSettings.normalizedSojuMode(writecopy) {
            settings.wineWritecopy = normalized
        }
        return settings
    }

    static func parseOpenGLStatus(_ output: String) -> OpenGLPatchStatus {
        var status = OpenGLPatchStatus.empty
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq])
            let value = String(trimmed[trimmed.index(after: eq)...])
            switch key {
            case "status": status.status = value
            case "path": status.path = value
            case "offset": status.offset = value
            case "byte": status.byte = value
            case "message": status.message = value
            default: break
            }
        }
        return status
    }

    static func parseSojuStatus(_ output: String) -> SojuCommandStatus {
        var status = SojuCommandStatus.empty
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq])
            let value = String(trimmed[trimmed.index(after: eq)...])
            switch key {
            case "layout": status.layout = value
            case "message": status.message = value
            case "copied_so": status.copiedSo = value == "1"
            default: break
            }
        }
        return status
    }

    static func loadSteam() -> GraphicsSettings {
        SteamSettingsStore.ensureOnDisk()
        return load(from: BottleStore.parseConf(SteamSettingsStore.confURL))
    }

    static func parseSpockD3D9Validation(_ output: String) -> SpockD3D9ValidationResult {
        var valid = false
        var path = ""
        var dllCount = 0
        var x86 = ""
        var x64 = ""
        var error = ""
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq])
            let value = String(trimmed[trimmed.index(after: eq)...])
            switch key {
            case "valid": valid = value == "1"
            case "path": path = value
            case "dll_count": dllCount = Int(value) ?? 0
            case "x86_dll": x86 = value
            case "x64_dll": x64 = value
            case "error": error = value
            default: break
            }
        }
        return SpockD3D9ValidationResult(
            valid: valid,
            path: path,
            dllCount: dllCount,
            x86Dll: x86,
            x64Dll: x64,
            errorMessage: error
        )
    }

    static func validateSpockD3D9Path(
        _ path: String,
        repositoryRoot: URL?,
        fileManager: FileManager = .default
    ) -> SpockD3D9ValidationResult {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let script = resolveRunCommand(repositoryRoot: repositoryRoot, fileManager: fileManager) else {
            return SpockD3D9ValidationResult(
                valid: false, path: trimmed, dllCount: 0, x86Dll: "", x64Dll: "",
                errorMessage: "run.command not found"
            )
        }
        let task = Process()
        task.executableURL = script
        task.arguments = ["--validate-spockd3d9", trimmed]
        task.currentDirectoryURL = script.deletingLastPathComponent()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return parseSpockD3D9Validation(text)
        } catch {
            return SpockD3D9ValidationResult(
                valid: false, path: trimmed, dllCount: 0, x86Dll: "", x64Dll: "",
                errorMessage: error.localizedDescription
            )
        }
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
