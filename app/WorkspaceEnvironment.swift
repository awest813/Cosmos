import Foundation
import CryptoKit

enum WorkspaceEnvironmentID: Hashable {
    case main
    case named(String)
    var stableID: String { switch self { case .main: return "main"; case .named(let name): return "named:" + name } }
}

struct WorkspaceEnvironment: Identifiable, Hashable {
    let key: WorkspaceEnvironmentID
    let name: String
    let prefix: URL
    let wineVersion: String
    let windowsVersion: String
    let backend: String
    let requestedArchitecture: String
    let initialized: Bool
    let assignedGames: [WinePort]
    let bottle: Bottle?
    var id: String { key.stableID }
    var commandEnvironment: [String: String] {
        var result = ["COSMOS_BOTTLE": bottle?.name ?? "", "WINEPREFIX": prefix.path, "WINE_VERSION": wineVersion, "COSMOS_SKIP_STEAM": "1"]
        if let requested = bottle?.settings["COSMOS_PREFIX_ARCH"], !requested.isEmpty { result["COSMOS_PREFIX_ARCH"] = requested }
        return result
    }
    static func catalog(bottles: [Bottle], ports: [WinePort], main: SteamSettings, mainInitialized: Bool) -> [WorkspaceEnvironment] {
        let primary = WorkspaceEnvironment(key: .main, name: "Main environment", prefix: main.prefixURL,
            wineVersion: main.wineVersion, windowsVersion: main.windowsVersion, backend: main.backend,
            requestedArchitecture: "", initialized: mainInitialized,
            assignedGames: ports.filter { $0.bottle.isEmpty }, bottle: nil)
        return [primary] + bottles.map { bottle in
            WorkspaceEnvironment(key: .named(bottle.name), name: bottle.name, prefix: bottle.prefixURL,
                wineVersion: bottle.settings["WINE_VERSION"].flatMap { $0.isEmpty ? nil : $0 } ?? "11.8",
                windowsVersion: bottle.windowsVersion, backend: bottle.backend, requestedArchitecture: bottle.prefixArch,
                initialized: bottle.isInitialized, assignedGames: ports.filter { $0.bottle == bottle.name }, bottle: bottle)
        }
    }
}

enum WorkspaceEnvironmentAction: String, CaseIterable {
    case install, settings, reveal, logs, diagnose, clone, stop, reset, delete
    var title: String {
        switch self {
        case .install: return "Install a Game Here…"
        case .settings: return "Environment Settings…"
        case .reveal: return "Open Windows Folder"
        case .logs: return "Open Launch Log"
        case .diagnose: return "Diagnose Environment"
        case .clone: return "Clone Environment…"
        case .stop: return "Stop Environment…"
        case .reset: return "Reset Windows Files…"
        case .delete: return "Delete Environment…"
        }
    }
    var isDestructive: Bool { self == .reset || self == .delete || self == .stop }
}

struct WorkspaceEnvironmentContext {
    let selected: WorkspaceEnvironment?
    let busy: Bool
    let modalPresented: Bool
    let installHostIssue: String?
    func disabledReason(_ action: WorkspaceEnvironmentAction) -> String? {
        if modalPresented { return "Finish or close the current sheet first." }
        guard let selected else { return "Select an available environment." }
        if busy && action != .reveal { return "Wait for the current operation to finish." }
        if action == .settings && selected.bottle == nil { return "Main defaults are managed in More → Steam Setup & Settings." }
        if [.clone, .reset, .delete, .install].contains(action), selected.bottle == nil {
            return "Choose a named environment for this action. Main environment settings remain available separately."
        }
        if action == .install {
            if selected.requestedArchitecture != "wow64" { return "The guided installer requires a WoW64 environment." }
            return installHostIssue
        }
        if action == .reveal && !selected.initialized { return "Windows files are available after initialization. You can inspect prepared folders under Files." }
        return nil
    }
}

struct EnvironmentSettingsDraft {
    let bottle: Bottle
    let revision: String
    var backend: String
    var windows: String
    var architecture: String
    var retina: Bool
    var sync: String
    init(bottle: Bottle, revision: String) {
        self.bottle = bottle; self.revision = revision
        backend = bottle.backend; windows = bottle.windowsVersion; architecture = bottle.prefixArch
        retina = bottle.retinaEnabled; sync = bottle.syncMode
    }
    var changes: [(String, String)] {
        var result: [(String, String)] = []
        if backend != bottle.backend { result.append(("COSMOS_BACKEND", backend)) }
        if windows != bottle.windowsVersion { result.append(("WINDOWS_VERSION", windows)) }
        if architecture != bottle.prefixArch { result.append(("COSMOS_PREFIX_ARCH", architecture)) }
        if retina != bottle.retinaEnabled { result.append(("WINE_RETINA_MODE", retina ? "1" : "0")) }
        if sync != bottle.syncMode { result.append(("COSMOS_SYNC_MODE", sync)) }
        return result
    }
    var arguments: [String] { ["update", bottle.name, "--expect-sha256", revision] + changes.flatMap { [$0.0, $0.1] } }
    var summaries: [String] {
        changes.map { key, value in
            switch key {
            case "COSMOS_BACKEND": return "Graphics default: " + SettingLabels.backendDisplayName(value)
            case "WINDOWS_VERSION": return "Windows: " + SettingLabels.windowsDisplayName(value)
            case "COSMOS_PREFIX_ARCH": return "Program layout: " + SettingLabels.prefixArchDisplayName(value)
            case "WINE_RETINA_MODE": return "Retina: " + (value == "1" ? "On" : "Off")
            default: return "Thread synchronization: " + GraphicsSettings.syncModeTitle(value)
            }
        }
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

struct EnvironmentSettingsRequest: Identifiable {
    let id = UUID()
    let environment: WorkspaceEnvironment
    let bottle: Bottle
    let revision: String
    init?(environment: WorkspaceEnvironment, revision: String) {
        guard let bottle = environment.bottle else { return nil }
        self.environment = environment; self.bottle = bottle; self.revision = revision
    }
}

struct EnvironmentConfirmation: Identifiable {
    let id = UUID()
    let environment: WorkspaceEnvironment
    let action: WorkspaceEnvironmentAction
    var message: String {
        let games = environment.assignedGames.count
        switch action {
        case .stop: return "Save your game first. Cosmos stops only identified Wine processes in \(environment.name). Unsaved progress may be lost."
        case .reset: return "Save and clone first if you need a backup. This stops \(environment.name) and removes its Windows files and inside-prefix games/saves. Settings and logs stay. External linked folders and \(games) assigned game definitions stay; reinstall games before using them. Partial removal cannot be undone."
        default: return "Save and clone first if you need a backup. This stops and deletes \(environment.name), including its Windows files, settings and logs. External linked folders and \(games) assigned game definitions stay; edit or remove those definitions afterward. Deletion cannot be undone."
        }
    }
}
