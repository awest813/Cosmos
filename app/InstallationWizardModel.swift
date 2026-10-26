import Foundation

struct InstallationWizardRequest: Identifiable {
    let id = UUID()
    var resuming = false
    var installation: PendingGameInstallation? = nil
}

enum InstallationWizardStep: Int, CaseIterable {
    case source, destination, requirements, review
    var title: String {
        switch self {
        case .source: return "Game"
        case .destination: return "Destination"
        case .requirements: return "Requirements"
        case .review: return "Review"
        }
    }
}

struct InstallationDestinationPreview: Equatable {
    let hostFolder: URL
    let windowsFolder: String
    let assumedMappings: Bool
}

struct InstallationWizardDraft {
    let request: InstallationWizardRequest
    var title = ""
    var installer = ""
    var folder = ""
    var existingEnvironment = ""
    var newEnvironmentName = ""
    var gameExecutable = ""
    var makeMacApp = false
    var launchAfterInstall = true

    init(request: InstallationWizardRequest) {
        self.request = request
        title = request.installation?.name ?? ""
        installer = request.installation?.installer ?? ""
        existingEnvironment = request.installation?.bottle ?? ""
        // Resume must leave the folder override blank until the user explicitly
        // relocates it. The backend's disconnected-drive guard stays authoritative.
        if !request.resuming { folder = request.installation?.folder ?? "" }
    }
    var effectiveTitle: String { request.installation?.name ?? title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var slug: String { Self.slugify(effectiveTitle) }
    var environmentName: String {
        if let saved = request.installation { return saved.bottle }
        let existing = existingEnvironment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existing.isEmpty { return existing }
        let custom = newEnvironmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? "game-" + slug : custom
    }
    var prefix: URL { BottleStore.bottlesDirectoryURL.appendingPathComponent(environmentName).appendingPathComponent("prefix") }
    var importRequest: StoreImportRequest { .classicGame(resuming: request.resuming, installation: request.installation) }
    var values: [StoreImportRequest.FieldKind: String] {
        var result: [StoreImportRequest.FieldKind: String] = [
            .displayName: effectiveTitle, .path: installer.trimmingCharacters(in: .whitespacesAndNewlines),
            .installationBottle: environmentName, .makeMacApp: makeMacApp ? "1" : "0",
            .launchAfterInstall: launchAfterInstall ? "1" : "0", .gameExecutable: gameExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        let chosen = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chosen.isEmpty { result[.installDirectory] = chosen }
        else if !request.resuming { result[.installDirectory] = "drive_c/Games/" + slug }
        return result
    }
    func sourceIssue(checkFiles: Bool = true) -> String? {
        if !WinePortDraft.isValidPortName(effectiveTitle) { return "Enter a game title without /, : or line breaks." }
        if !BottleStore.isValidName(slug) { return "Choose a title that produces a valid game identifier without consecutive dots." }
        if request.resuming {
            let executable = gameExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
            if !executable.isEmpty && !executable.lowercased().hasSuffix(".exe") { return "Choose the installed game EXE." }
            return nil
        }
        let path = installer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), ["exe", "msi"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else {
            return "Choose a Windows installer EXE or MSI on your Mac."
        }
        guard checkFiles else { return nil }
        if URL(fileURLWithPath: path).pathExtension.lowercased() == "exe" {
            return WindowsProgramArchitecture.detect(at: URL(fileURLWithPath: path)) == nil ? "Choose an x86/x64 Windows installer EXE, not a DLL or another file type." : nil
        }
        guard let file = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return "The installer is unavailable. Reconnect its drive or choose another file." }
        defer { try? file.close() }
        let header = (try? file.read(upToCount: 8)) ?? Data()
        return Array(header) == [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1] ? nil : "This file does not have a Windows Installer MSI container header."
    }
    func destinationIssue(bottles: [Bottle]) -> String? {
        guard BottleStore.isValidName(environmentName) else { return "Use an environment name with letters, numbers, dots, underscores or hyphens, without consecutive dots." }
        if request.installation == nil && !request.resuming && existingEnvironment.isEmpty && bottles.contains(where: { $0.name == environmentName }) {
            return "This environment already exists. Select it explicitly or choose a new environment name."
        }
        if let bottle = bottles.first(where: { $0.name == environmentName }), bottle.prefixArch != "wow64" {
            return "This installation flow needs a WoW64 environment. Choose another environment."
        }
        return StoreImportValidation.validate(request: importRequest, values: values)
    }
    func previewDestination() throws -> InstallationDestinationPreview {
        let manager = FileManager.default
        if request.resuming && !manager.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) {
            throw NSError(domain: "Cosmos.Installation", code: 1, userInfo: [NSLocalizedDescriptionKey: "The saved Windows environment is not initialized. Run or retry setup first."])
        }
        var path = values[.installDirectory] ?? ""
        if path.isEmpty && request.resuming {
            let state = prefix.deletingLastPathComponent().appendingPathComponent("install-\(slug).conf")
            path = request.installation?.folder ?? BottleStore.parseConf(state)["INSTALL_FOLDER"] ?? ""
            if !path.isEmpty && !manager.fileExists(atPath: path) {
                throw NSError(domain: "Cosmos.Installation", code: 2, userInfo: [NSLocalizedDescriptionKey: "The saved installation folder is unavailable. Reconnect its drive or explicitly choose its new location."])
            }
        }
        if path.isEmpty { path = "drive_c/Games/" + slug }
        if let saved = request.installation, !saved.folder.isEmpty, path == saved.folder,
           !manager.fileExists(atPath: saved.folder) {
            throw NSError(domain: "Cosmos.Installation", code: 2, userInfo: [NSLocalizedDescriptionKey: "The saved installation folder is unavailable. Reconnect its drive or explicitly choose its new location."])
        }
        let host = try WineFilesystemBridge.resolve(path, prefix: prefix)
        var directory: ObjCBool = false
        if manager.fileExists(atPath: host.path, isDirectory: &directory), !directory.boolValue {
            throw NSError(domain: "Cosmos.Installation", code: 3, userInfo: [NSLocalizedDescriptionKey: "The installation destination is a file. Choose a folder instead."])
        }
        return InstallationDestinationPreview(hostFolder: host, windowsFolder: try WineFilesystemBridge.windowsPath(host.path, prefix: prefix),
            assumedMappings: !manager.fileExists(atPath: prefix.appendingPathComponent("system.reg").path))
    }
    // Match port_slugify's ASCII mapping rather than silently transliterating.
    static func slugify(_ title: String) -> String {
        let bytes = title.utf8.map { byte -> UInt8 in
            let value = (65...90).contains(byte) ? byte + 32 : byte
            return (97...122).contains(value) || (48...57).contains(value) || [46, 95, 45].contains(value) ? value : 45
        }
        var result = String(decoding: bytes, as: UTF8.self)
        while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        while let first = result.utf8.first, !(97...122).contains(first) && !(48...57).contains(first) { result.removeFirst() }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "port" : result
    }
}
