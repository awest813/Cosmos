import Foundation

/// Local file checks only. Never starts Wine, changes a prefix or downloads data.
struct PortFileCheck {
    struct Finding: Identifiable {
        let id: String
        let passed: Bool
        let message: String
    }

    let gameURL: URL?
    let prefixURL: URL?
    let findings: [Finding]

    static func inspect(
        _ port: WinePort,
        mainPrefix: URL = SteamSettings.defaults.prefixURL,
        bottlesDirectory: URL = BottleStore.bottlesDirectoryURL,
        fileManager: FileManager = .default
    ) -> PortFileCheck {
        var findings: [Finding] = []
        let validBottle = port.bottle.isEmpty || BottleStore.isValidName(port.bottle)
        let prefix: URL?
        if port.bottle.isEmpty {
            prefix = mainPrefix
        } else if validBottle {
            let directory = bottlesDirectory.appendingPathComponent(port.bottle, isDirectory: true)
            prefix = directory.appendingPathComponent("prefix", isDirectory: true)
            let exists = fileManager.fileExists(atPath: directory.appendingPathComponent("bottle.conf").path)
            findings.append(Finding(
                id: "environment", passed: exists,
                message: exists ? "Found environment: \(port.bottle)." : "Environment \(port.bottle) is missing. Restore it or choose another environment in Edit."
            ))
        } else {
            prefix = nil
            findings.append(Finding(id: "environment", passed: false, message: "Invalid environment name. Choose an existing environment in Edit."))
        }
        if let prefix {
            let initialized = fileManager.fileExists(atPath: prefix.appendingPathComponent("system.reg").path)
            findings.append(Finding(
                id: "prefix", passed: initialized,
                message: initialized ? "Windows environment is initialized." : "Windows environment is not initialized yet. First launch prepares it."
            ))
        }
        let game: URL?
        if let prefix {
            do {
                game = try WineFilesystemBridge.resolve(port.exe, prefix: prefix)
            } catch {
                game = nil
                findings.append(Finding(id: "filesystem", passed: false, message: "\(error.localizedDescription) Use Edit to review the game path or environment mapping."))
            }
        } else {
            game = nil
        }
        let detected = game.flatMap { WindowsProgramArchitecture.detect(at: $0) }
        findings.append(Finding(
            id: "executable", passed: detected != nil,
            message: detected == nil
                ? "Game EXE is missing or is not an x86/x64 Windows program. Use Edit to locate the installed game."
                : "Found a \(detected == .win32 ? "32-bit" : "64-bit") Windows program."
        ))
        if let detected {
            findings.append(Finding(
                id: "architecture", passed: detected.rawValue == port.programArch,
                message: detected.rawValue == port.programArch
                    ? "Saved program architecture matches the EXE."
                    : "Saved program architecture differs from the EXE. Select the matching architecture in Edit."
            ))
        }
        if let prefix, let handle = try? FileHandle(forReadingFrom: prefix.appendingPathComponent("system.reg")) {
            defer { try? handle.close() }
            let header = (try? handle.read(upToCount: 4096)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if header.split(whereSeparator: \.isNewline).contains("#arch=win32"), detected == .win64 {
                findings.append(Finding(id: "prefix-architecture", passed: false, message: "A 64-bit game cannot use this 32-bit prefix. Choose a separate 64-bit/WoW64 environment in Edit."))
            }
        }
        if case .failure(let error) = PortStack.resolve(port.renderers, distribution: port.distribution) {
            findings.append(Finding(id: "graphics", passed: false, message: error.message))
        }
        return PortFileCheck(gameURL: game, prefixURL: prefix, findings: findings)
    }

    func report(for port: WinePort) -> String {
        let lines = findings.map { "\($0.passed ? "PASS" : "CHECK"): \($0.message)" }.joined(separator: "\n")
        return """
        Cosmos port file checks — gameplay NOT TESTED
        Game: \(port.name)
        Port ID: \(port.id)
        Environment: \(port.bottleLabel)
        Configured path: \(port.exe)
        Executable: \(gameURL?.path ?? port.exe)
        Prefix: \(prefixURL?.path ?? "Not resolved")
        Graphics requested: \(port.graphicsLabel)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        \(lines)
        Runtime loading, WoW64 support, loaded renderer, gameplay and save/load: not verified.
        """
    }
}
