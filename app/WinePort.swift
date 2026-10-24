import Foundation

/// Apple Silicon wine port. One Windows program opened like a Mac app.
///
/// The renderer rules match `scripts/lib/port_lib.sh` (Sikarugir / cosmosNEW
/// stack on top of a Cosmos bottle). Bash is what launch and build run;
/// this type is the same table for the dashboard and its tests.
struct PortRenderers: Equatable, Hashable {
    var dxmt: Bool
    var d3dmetal: Bool
    var dxvk: Bool
    var d9vk: Bool
    var cncDDraw: Bool
    var wineD3D: Bool

    static let appleSiliconDefaults = PortRenderers(
        dxmt: true,
        d3dmetal: false,
        dxvk: false,
        d9vk: true,
        cncDDraw: true,
        wineD3D: true
    )

    init(dxmt: Bool, d3dmetal: Bool, dxvk: Bool, d9vk: Bool, cncDDraw: Bool, wineD3D: Bool) {
        self.dxmt = dxmt
        self.d3dmetal = d3dmetal
        self.dxvk = dxvk
        self.d9vk = d9vk
        self.cncDDraw = cncDDraw
        self.wineD3D = wineD3D
    }

    init(settings: [String: String]) {
        dxmt = settings["PORT_RENDER_DXMT"] == "1"
        d3dmetal = settings["PORT_RENDER_D3DMETAL"] == "1"
        dxvk = settings["PORT_RENDER_DXVK"] == "1"
        d9vk = settings["PORT_RENDER_D9VK"] == "1"
        cncDDraw = settings["PORT_RENDER_CNC_DDRAW"] == "1"
        wineD3D = settings["PORT_RENDER_WINED3D"] == "1"
    }

    var enabledIDs: [String] {
        var ids: [String] = []
        if dxmt { ids.append("dxmt") }
        if d3dmetal { ids.append("d3dmetal") }
        if dxvk { ids.append("dxvk") }
        if d9vk { ids.append("d9vk") }
        if cncDDraw { ids.append("cnc-ddraw") }
        if wineD3D { ids.append("wined3d") }
        return ids
    }
}

enum PortStackError: Equatable, Error {
    case sharedD3DMetal
    case noRenderer

    static let sharedD3DMetalMessage = "Shared ports cannot use D3DMetal. Apple's license does not allow a port you give to someone else to include it."
    static let noRendererMessage = "Turn on at least one graphics renderer."

    var message: String {
        switch self {
        case .sharedD3DMetal: return Self.sharedD3DMetalMessage
        case .noRenderer: return Self.noRendererMessage
        }
    }
}

enum PortStack {
    /// Same order as `port_resolve_primary` in scripts/lib/port_lib.sh.
    static func resolve(_ renderers: PortRenderers, distribution: String) -> Result<String, PortStackError> {
        let dist = distribution.isEmpty ? "personal" : distribution
        if renderers.d3dmetal {
            if dist == "share" { return .failure(.sharedD3DMetal) }
            return .success("d3dmetal")
        }
        if renderers.dxmt && renderers.d9vk { return .success("spockd3d9") }
        if renderers.dxmt { return .success("dxmt") }
        if renderers.dxvk { return .success("dxvk") }
        if renderers.d9vk { return .success("spockd3d9") }
        if renderers.wineD3D || renderers.cncDDraw { return .success("wined3d") }
        return .failure(.noRenderer)
    }

    static func launchSummary(_ renderers: PortRenderers, distribution: String) -> String {
        switch resolve(renderers, distribution: distribution) {
        case .failure(let error):
            return error.message
        case .success(let backend):
            var text: String
            switch backend {
            case "d3dmetal":
                text = "Opens with D3DMetal for DirectX 11 and 12. This stays on your Mac."
            case "spockd3d9":
                text = "Opens with DXMT for DirectX 10/11 and D9VK for DirectX 8/9. WineD3D covers older DirectX."
            case "dxmt":
                text = "Opens with DXMT for DirectX 10/11. DirectX 9 uses WineD3D."
            case "dxvk":
                text = "Opens with DXVK for DirectX 9, 10, and 11 through Vulkan."
            case "wined3d":
                text = "Opens with WineD3D. Broadest compatibility, slowest graphics."
            default:
                text = "Opens with \(SettingLabels.backendDisplayName(backend))."
            }
            if renderers.cncDDraw {
                text += " CNC-DDRAW handles classic DirectDraw when you set a ddraw.dll folder."
            }
            return text
        }
    }
}

struct WinePort: Identifiable, Hashable {
    let id: String
    let settings: [String: String]
    let directory: URL

    var name: String { settings["PORT_NAME"].flatMap { $0.isEmpty ? nil : $0 } ?? id }
    var exe: String { settings["PORT_EXE"] ?? "" }
    var bottle: String { settings["PORT_BOTTLE"] ?? "" }
    var distribution: String {
        let value = settings["PORT_DISTRIBUTION"] ?? ""
        return value.isEmpty ? "personal" : value
    }
    var windowsVersion: String {
        let value = settings["PORT_WINDOWS"] ?? ""
        return value.isEmpty ? "win10" : value
    }
    var retinaEnabled: Bool { settings["PORT_RETINA"] == "1" }
    var primaryBackend: String { settings["PORT_PRIMARY"] ?? "" }
    var builtApp: String { settings["PORT_BUILT_APP"] ?? "" }
    var renderers: PortRenderers { PortRenderers(settings: settings) }

    var distributionLabel: String {
        distribution == "share" ? "Shareable" : "This Mac"
    }

    var bottleLabel: String {
        bottle.isEmpty ? "Main environment" : bottle
    }

    var graphicsLabel: String {
        switch primaryBackend {
        case "d3dmetal": return "D3DMetal"
        case "spockd3d9": return "DXMT + D9VK"
        case "dxmt": return "DXMT"
        case "dxvk": return "DXVK"
        case "wined3d": return "WineD3D"
        default: return primaryBackend.isEmpty ? "" : SettingLabels.backendDisplayName(primaryBackend)
        }
    }

    var cardDetail: String {
        var parts = [distributionLabel, SettingLabels.windowsDisplayName(windowsVersion)]
        if !graphicsLabel.isEmpty {
            parts.append(graphicsLabel)
        }
        return parts.joined(separator: " · ")
    }
}

enum WinePortStore {
    static var portsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cosmos/Ports", isDirectory: true)
    }

    static func load() -> [WinePort] {
        load(from: portsDirectoryURL)
    }

    static func load(from root: URL, fileManager: FileManager = .default) -> [WinePort] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var ports: [WinePort] = []
        for dir in entries {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            let confURL = dir.appendingPathComponent("port.conf")
            guard fileManager.fileExists(atPath: confURL.path) else { continue }
            let settings = BottleStore.parseConf(confURL)
            let slug = settings["PORT_SLUG"].flatMap { $0.isEmpty ? nil : $0 } ?? dir.lastPathComponent
            ports.append(WinePort(id: slug, settings: settings, directory: dir))
        }
        return ports.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct WinePortDraft: Equatable {
    var name: String
    var exe: String
    var bottle: String
    var distribution: String
    var windows: String
    var retina: Bool
    var renderers: PortRenderers
    var cncDDrawPath: String
    var gptkPath: String

    static let empty = WinePortDraft(
        name: "",
        exe: "",
        bottle: "",
        distribution: "personal",
        windows: "win10",
        retina: false,
        renderers: .appleSiliconDefaults,
        cncDDrawPath: "",
        gptkPath: ""
    )

    static func isValidPortName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." || trimmed == ".." { return false }
        if trimmed.contains("/") || trimmed.contains(":") || trimmed.contains("\n") { return false }
        return true
    }

    var validationError: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExe = exe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !Self.isValidPortName(trimmedName) {
            return "Enter a name without / or :."
        }
        if trimmedExe.isEmpty {
            return "Choose the Windows program (.exe)."
        }
        let trimmedBottle = bottle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBottle.isEmpty && !BottleStore.isValidName(trimmedBottle) {
            return "That bottle name is not valid."
        }
        if distribution == "share" && !gptkPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "A Game Porting Toolkit path stays on a personal port."
        }
        if case .failure(let error) = PortStack.resolve(renderers, distribution: distribution) {
            return error.message
        }
        return nil
    }

    var commandArguments: [String] {
        var args = [
            "create",
            "--name", name.trimmingCharacters(in: .whitespacesAndNewlines),
            "--exe", exe.trimmingCharacters(in: .whitespacesAndNewlines),
            "--distribution", distribution,
            "--windows", windows,
            "--retina", retina ? "1" : "0",
            "--dxmt", renderers.dxmt ? "1" : "0",
            "--d3dmetal", renderers.d3dmetal ? "1" : "0",
            "--dxvk", renderers.dxvk ? "1" : "0",
            "--d9vk", renderers.d9vk ? "1" : "0",
            "--cnc-ddraw", renderers.cncDDraw ? "1" : "0",
            "--wined3d", renderers.wineD3D ? "1" : "0",
        ]
        let trimmedBottle = bottle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBottle.isEmpty {
            args += ["--bottle", trimmedBottle]
        }
        let cnc = cncDDrawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cnc.isEmpty {
            args += ["--cnc-ddraw-path", cnc]
        }
        let gptk = gptkPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !gptk.isEmpty && distribution == "personal" {
            args += ["--gptk-path", gptk]
        }
        return args
    }
}
