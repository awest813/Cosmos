import Foundation

/// Host Wine/Rosetta readiness for the dashboard sidebar and launch gating.
struct WineRuntimeStatus: Equatable {
    let chipArchitecture: String
    let rosettaCode: String
    let wineVersion: String
    let wineInstalled: Bool
    let wineRootPath: String
    let wineBinaryPath: String
    let wineReportedVersion: String?

    var needsRosetta: Bool { chipArchitecture == "arm64" }

    var rosettaReady: Bool {
        rosettaCode == "available" || rosettaCode == "not_required"
    }

    var isLaunchReady: Bool {
        rosettaReady && wineInstalled
    }

    var rosettaLabel: String {
        switch rosettaCode {
        case "available": return "Rosetta 2 ready"
        case "missing": return "Rosetta 2 required"
        case "not_required": return "Intel host (no Rosetta)"
        default: return "Rosetta status unknown"
        }
    }

    var wineLabel: String {
        wineInstalled
            ? "Wine \(wineVersion) installed"
            : "Wine \(wineVersion) not downloaded"
    }

    var translationNote: String {
        if needsRosetta {
            return "Cosmos runs x86_64 Wine builds through Rosetta 2 on Apple Silicon."
        }
        return "Native x86_64 host — Wine runs without Rosetta."
    }
}

enum WineRuntimeStore {
    static func load(wineVersion: String = SteamSettings.defaults.wineVersion) -> WineRuntimeStatus {
        if let parsed = loadFromScript(wineVersion: wineVersion) {
            return parsed
        }
        return loadLocally(wineVersion: wineVersion)
    }

    private static func loadFromScript(wineVersion: String) -> WineRuntimeStatus? {
        guard let root = CosmosPaths.cosmosRoot() else { return nil }
        let runScript = root.appendingPathComponent("run.command")
        guard FileManager.default.isExecutableFile(atPath: runScript.path) else { return nil }

        let process = Process()
        process.executableURL = runScript
        process.arguments = ["--runtime-status"]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["WINE_VERSION": wineVersion]
        ) { _, new in new }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parseStatusLines(text, fallbackWineVersion: wineVersion)
    }

    private static func loadLocally(wineVersion: String) -> WineRuntimeStatus {
        let chip = hostArchitecture()
        let rosetta: String
        if chip != "arm64" {
            rosetta = "not_required"
        } else {
            rosetta = rosettaInstalled() ? "available" : "missing"
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent("wine-\(wineVersion)", isDirectory: true)
        let bin = root
            .appendingPathComponent("Wine Devel.app/Contents/Resources/wine/bin/wine")
        let installed = FileManager.default.isExecutableFile(atPath: bin.path)

        return WineRuntimeStatus(
            chipArchitecture: chip,
            rosettaCode: rosetta,
            wineVersion: wineVersion,
            wineInstalled: installed,
            wineRootPath: root.path,
            wineBinaryPath: bin.path,
            wineReportedVersion: nil
        )
    }

    static func parseStatusLines(_ text: String, fallbackWineVersion: String) -> WineRuntimeStatus? {
        var fields: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            fields[parts[0]] = parts[1]
        }
        guard let chip = fields["chip"] else { return nil }
        return WineRuntimeStatus(
            chipArchitecture: chip,
            rosettaCode: fields["rosetta"] ?? "unknown",
            wineVersion: fields["wine_version"] ?? fallbackWineVersion,
            wineInstalled: fields["wine_installed"] == "1",
            wineRootPath: fields["wine_root"] ?? "",
            wineBinaryPath: fields["wine_bin"] ?? "",
            wineReportedVersion: fields["wine_report"]
        )
    }

    private static func hostArchitecture() -> String {
#if arch(arm64)
        return "arm64"
#elseif arch(x86_64)
        return "x86_64"
#else
        return "unknown"
#endif
    }

    private static func rosettaInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
