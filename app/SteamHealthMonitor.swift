import Foundation

/// Parses `run.command --steam-health` for dashboard warnings.
struct SteamHealthStatus: Equatable {
    let prefixInitialized: Bool
    let steamInstalled: Bool
    let mingwAvailable: Bool
    let webhelperWrapper: Bool
    let webhelperWrapperPending: Bool
    let nativeScanEnabled: Bool
    let dualInstallCount: Int
    let dualInstallAppIDs: [String]
    let userdataPresent: Bool
    let cloudLogWarning: Bool

    static let empty = SteamHealthStatus(
        prefixInitialized: false,
        steamInstalled: false,
        mingwAvailable: false,
        webhelperWrapper: false,
        webhelperWrapperPending: false,
        nativeScanEnabled: false,
        dualInstallCount: 0,
        dualInstallAppIDs: [],
        userdataPresent: true,
        cloudLogWarning: false
    )

    var needsMingwForWrapper: Bool {
        steamInstalled && !mingwAvailable && webhelperWrapperPending && !webhelperWrapper
    }

    var hasDualInstallWarning: Bool { dualInstallCount > 0 }

    var hasCloudWarning: Bool { cloudLogWarning || !userdataPresent }
}

enum SteamHealthMonitor {
    static func load(environment: [String: String] = [:]) -> SteamHealthStatus? {
        guard let root = CosmosPaths.cosmosRoot() else { return nil }
        let runScript = root.appendingPathComponent("run.command")
        guard FileManager.default.isExecutableFile(atPath: runScript.path) else { return nil }

        let process = Process()
        process.executableURL = runScript
        process.arguments = ["--steam-health"]
        process.currentDirectoryURL = root
        process.environment = mergedEnvironment(environment)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(lines: text)
    }

    static func parse(lines: String) -> SteamHealthStatus {
        var fields: [String: String] = [:]
        for line in lines.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard let index = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<index])
            let value = String(text[text.index(after: index)...])
            fields[key] = value
        }

        let dualCSV = fields["dual_install_appids"] ?? ""
        let appIDs = dualCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return SteamHealthStatus(
            prefixInitialized: fields["prefix_initialized"] == "1",
            steamInstalled: fields["steam_installed"] == "1",
            mingwAvailable: fields["mingw_available"] == "1",
            webhelperWrapper: fields["webhelper_wrapper"] == "1",
            webhelperWrapperPending: fields["webhelper_wrapper_pending"] == "1",
            nativeScanEnabled: fields["native_scan_enabled"] == "1",
            dualInstallCount: Int(fields["dual_install_count"] ?? "0") ?? 0,
            dualInstallAppIDs: appIDs,
            userdataPresent: fields["userdata_present"] != "0",
            cloudLogWarning: fields["cloud_log_warning"] == "1"
        )
    }

    private static func mergedEnvironment(_ overrides: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "COSMOS_BOTTLE")
        for (key, value) in overrides {
            env[key] = value
        }
        return env
    }
}
