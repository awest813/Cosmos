import Foundation
import Combine

/// Executes shell commands to manage Wine, Steam, DXMT, and launcher generation.
///
/// All heavy lifting is delegated to the existing `run.command` and
/// `install_merlot.command` scripts.  This class provides an observable
/// wrapper so SwiftUI views can react to progress and status changes.
@MainActor
final class CiderEngine: ObservableObject {

    // MARK: - Defaults (must stay in sync with run.command)

    static let defaultWineVersion  = "11.8"
    static let defaultDXMTVersion  = "0.74"
    static let defaultWinePrefix   = NSHomeDirectory() + "/.wine-steam-11"
    static let defaultDXMTRoot     = NSHomeDirectory() + "/DXMT"
    static let defaultSteamLog     = (ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp") + "/merlot-steam.log"

    // MARK: - Published state

    @Published var setupState = SetupState()
    @Published var profiles: [GameProfile] = []
    @Published var isRunning = false
    @Published var lastOutput = ""
    @Published var lastError: String?

    // MARK: - Paths

    /// Root of the Cider repository (two levels up from the built executable
    /// when running from `CiderApp/.build/…`; can also be set via the
    /// `CIDER_REPO` environment variable or detected from the app bundle).
    let repoRoot: String

    // MARK: - Init

    init() {
        if let env = ProcessInfo.processInfo.environment["CIDER_REPO"] {
            self.repoRoot = env
        } else if let bundleResource = Bundle.main.resourceURL?.appendingPathComponent("run.command").path,
                  FileManager.default.fileExists(atPath: bundleResource) {
            self.repoRoot = Bundle.main.resourceURL!.path
        } else {
            // Fallback: assume CiderApp is a subdirectory of the repo.
            let execURL = URL(fileURLWithPath: CommandLine.arguments[0])
            var candidate = execURL.deletingLastPathComponent()
            for _ in 0..<6 {
                if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("run.command").path) {
                    break
                }
                candidate = candidate.deletingLastPathComponent()
            }
            self.repoRoot = candidate.path
        }

        refresh()
    }

    // MARK: - Public API

    /// Re-detect installed components and reload profiles.
    func refresh() {
        setupState = SetupState.detect()
        profiles = GameProfile.loadAll()
    }

    /// Run the full `run.command` setup (install prerequisites + launch Steam).
    func installAndLaunchSteam() async {
        await runScript("run.command")
        refresh()
    }

    /// Launch Steam with an optional game profile.
    func launchSteam(profile: GameProfile? = nil) async {
        var env: [String: String] = [:]
        if let p = profile {
            if !p.steamGameID.isEmpty { env["STEAM_GAME_ID"] = p.steamGameID }
            env["WINE_RETINA_MODE"] = p.retina ? "1" : "0"
            if !p.mouseWarp.isEmpty { env["WINE_MOUSE_WARP_OVERRIDE"] = p.mouseWarp }
            for override in p.envOverrides {
                let parts = override.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    env[String(parts[0])] = String(parts[1])
                }
            }
        }
        await runScript("run.command", extraEnv: env)
        refresh()
    }

    /// Regenerate `.app` launchers via `install_merlot.command`.
    func rebuildLaunchers() async {
        await runScript("install_merlot.command")
    }

    /// Remove and re-download DXMT.
    func reinstallDXMT() async {
        let dxmtRoot = Self.defaultDXMTRoot
        await runShell("rm -rf '\(dxmtRoot)/i386-windows' '\(dxmtRoot)/x86_64-windows' '\(dxmtRoot)/x86_64-unix'")
        await runScript("run.command")
        refresh()
    }

    /// Delete the Wine prefix so it can be recreated on next launch.
    func resetWinePrefix() async {
        await runShell("rm -rf '\(Self.defaultWinePrefix)'")
        refresh()
    }

    /// Kill all Wine and Steam processes.
    func killWineProcesses() async {
        await runShell("pkill -f 'wine' 2>/dev/null; pkill -f 'Steam' 2>/dev/null; true")
        refresh()
    }

    /// Return the contents of the Steam log file.
    func readSteamLog() -> String {
        let logPath = Self.defaultSteamLog
        return (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "(no log found at \(logPath))"
    }

    /// Save a profile and regenerate its Merlot `.conf` file so
    /// `install_merlot.command` will pick it up.
    func saveProfile(_ profile: GameProfile) throws {
        try profile.save()
        try writeMerlotConf(for: profile)
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
            profiles.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
    }

    /// Delete a profile and its generated `.conf`.
    func deleteProfile(_ profile: GameProfile) throws {
        try profile.delete()
        let confPath = "\(repoRoot)/merlot_configs/\(profile.slug).conf"
        try? FileManager.default.removeItem(atPath: confPath)
        profiles.removeAll { $0.id == profile.id }
    }

    // MARK: - Internals

    /// Write a Merlot `.conf` file that `install_merlot.command` understands.
    private func writeMerlotConf(for profile: GameProfile) throws {
        let configsDir = "\(repoRoot)/merlot_configs"
        try FileManager.default.createDirectory(
            atPath: configsDir, withIntermediateDirectories: true
        )
        let path = "\(configsDir)/\(profile.slug).conf"

        var lines: [String] = []
        lines.append("APP_NAME=\"\(profile.displayName) (Merlot)\"")
        lines.append("BUNDLE_ID=\"com.merlot.\(profile.slug)\"")
        lines.append("")

        var envNames: [String] = []
        var envValues: [(String, String)] = []

        if !profile.steamGameID.isEmpty {
            envNames.append("STEAM_GAME_ID")
            envValues.append(("STEAM_GAME_ID", profile.steamGameID))
        }
        if profile.retina {
            envNames.append("WINE_RETINA_MODE")
            envValues.append(("WINE_RETINA_MODE", "1"))
        }
        if !profile.mouseWarp.isEmpty {
            envNames.append("WINE_MOUSE_WARP_OVERRIDE")
            envValues.append(("WINE_MOUSE_WARP_OVERRIDE", profile.mouseWarp))
        }
        for override in profile.envOverrides {
            let parts = override.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                envNames.append(key)
                envValues.append((key, String(parts[1])))
            }
        }

        lines.append("RUN_ENV_NAMES=(")
        for name in envNames {
            lines.append("  \(name)")
        }
        lines.append(")")
        lines.append("")

        for (key, value) in envValues {
            lines.append("\(key)=\"\(value)\"")
        }

        try lines.joined(separator: "\n").appending("\n")
            .write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Run one of the repo's `.command` scripts.
    private func runScript(_ name: String, extraEnv: [String: String] = [:]) async {
        let scriptPath = "\(repoRoot)/\(name)"
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            lastError = "\(name) not found at \(scriptPath)"
            return
        }
        await execute(path: "/bin/bash", arguments: [scriptPath], extraEnv: extraEnv)
    }

    /// Run an arbitrary shell command string.
    private func runShell(_ command: String) async {
        await execute(path: "/bin/bash", arguments: ["-c", command])
    }

    /// Low-level process execution with output capture.
    private func execute(
        path: String,
        arguments: [String],
        extraEnv: [String: String] = [:]
    ) async {
        isRunning = true
        lastError = nil
        lastOutput = ""

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        for (k, v) in extraEnv { env[k] = v }
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()

            // Read output in background
            let data = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                DispatchQueue.global().async {
                    let d = pipe.fileHandleForReading.readDataToEndOfFile()
                    cont.resume(returning: d)
                }
            }

            proc.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            lastOutput = output

            if proc.terminationStatus != 0 {
                lastError = "Process exited with status \(proc.terminationStatus)"
            }
        } catch {
            lastError = error.localizedDescription
        }

        isRunning = false
    }
}
