import Foundation

enum WorkspaceDestination: String, CaseIterable, Identifiable {
    case library = "Library", installations = "Installations", environments = "Environments"
    case components = "Components", activity = "Activity"
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .library: return "gamecontroller"
        case .installations: return "square.and.arrow.down"
        case .environments: return "externaldrive"
        case .components: return "shippingbox"
        case .activity: return "clock.arrow.circlepath"
        }
    }
}

/// A presentation adapter. Existing records and launch semantics stay intact.
enum WorkspaceGame: Identifiable, Hashable {
    case port(WinePort)
    case profile(SavedProfile)
    var id: String {
        switch self {
        case .port(let port): return "port:" + port.id
        case .profile(let profile): return "profile:" + profile.id
        }
    }
    var name: String {
        switch self { case .port(let port): return port.name; case .profile(let profile): return profile.name }
    }
    var source: String {
        switch self { case .port: return "Standalone"; case .profile(let profile): return profile.libraryStore.label }
    }
    var executable: String {
        switch self { case .port(let port): return port.exe; case .profile(let profile): return profile.path }
    }
    var launchConfigured: Bool {
        switch self { case .port(let port): return !port.exe.isEmpty; case .profile(let profile): return profile.canLaunchFromDashboard }
    }
    static func catalog(ports: [WinePort], profiles: [SavedProfile], query: String = "") -> [WorkspaceGame] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return (ports.map(Self.port) + profiles.map(Self.profile))
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.executable.localizedCaseInsensitiveContains(query) || $0.source.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum WorkspaceCommand: String, CaseIterable {
    case install, addExecutable, play, edit, buildApp, reveal, checkFiles, diagnose, refresh
    var title: String {
        switch self {
        case .install: return "Install Windows Game…"
        case .addExecutable: return "Add Installed EXE…"
        case .play: return "Play"
        case .edit: return "Game Settings…"
        case .buildApp: return "Create / Update Mac App"
        case .reveal: return "Show Files in Finder"
        case .checkFiles: return "Check Game Files"
        case .diagnose: return "Diagnose Launch"
        case .refresh: return "Refresh"
        }
    }
}

/// Shared by menus, toolbar and game actions; Steam readiness is deliberately
/// absent. Backend-specific requirements are evaluated against the actual item.
struct WorkspaceCommandContext {
    let game: WorkspaceGame?
    let busy: Bool
    let portHostIssue: String?
    let runtimeIssue: String?

    func disabledReason(_ command: WorkspaceCommand) -> String? {
        if command == .refresh { return busy ? "Wait for the current operation to finish." : nil }
        if command == .install || command == .addExecutable {
            return busy ? "Wait for the current operation to finish." : portHostIssue
        }
        guard let game else { return "Select a game in Library." }
        if command == .reveal { return nil }
        if busy { return "Wait for the current operation to finish." }
        if command == .play {
            guard game.launchConfigured else { return "Choose the game's executable or source identifier first." }
            if case .port = game { return portHostIssue }
            return runtimeIssue
        }
        if command == .buildApp || command == .edit || command == .checkFiles || command == .diagnose {
            if case .profile = game { return "Use this saved launcher's tools in the previous interface during the transition." }
            if command == .buildApp { return portHostIssue }
        }
        return nil
    }
}
