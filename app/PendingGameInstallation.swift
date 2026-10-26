import Foundation

struct PendingGameInstallation: Identifiable, Equatable {
    let id: String
    let name: String
    let slug: String
    let bottle: String
    let folder: String
    let installer: String
    let stage: String

    var statusLabel: String {
        switch stage {
        case "prepared": return "Environment prepared — choose an installer"
        case "installing": return "Setup was started — continue if it finished"
        case "setup-failed": return "Setup reported an error — retry or finish if installed"
        default: return "Select the installed game EXE"
        }
    }
}

enum PendingGameInstallationStore {
    static func load(
        bottlesDirectory: URL = BottleStore.bottlesDirectoryURL,
        portsDirectory: URL = WinePortStore.portsDirectoryURL,
        fileManager: FileManager = .default
    ) -> [PendingGameInstallation] {
        let directories = (try? fileManager.contentsOfDirectory(at: bottlesDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var results: [PendingGameInstallation] = []
        for directory in directories {
            let bottle = directory.lastPathComponent
            guard BottleStore.isValidName(bottle), fileManager.fileExists(atPath: directory.appendingPathComponent("bottle.conf").path) else { continue }
            let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for file in files where file.lastPathComponent.hasPrefix("install-") && file.pathExtension == "conf" {
                let values = BottleStore.parseConf(file)
                let slug = values["INSTALL_SLUG"] ?? ""
                let name = values["INSTALL_NAME"] ?? ""
                let stage = values["INSTALL_STAGE"] ?? ""
                guard BottleStore.isValidName(slug), WinePortDraft.isValidPortName(name),
                      values["INSTALL_BOTTLE"] == bottle,
                      file.lastPathComponent == "install-\(slug).conf",
                      ["prepared", "installing", "setup-failed", "awaiting-game"].contains(stage),
                      !fileManager.fileExists(atPath: portsDirectory.appendingPathComponent(slug).appendingPathComponent("port.conf").path)
                else { continue }
                results.append(PendingGameInstallation(
                    id: "\(bottle)/\(slug)", name: name, slug: slug, bottle: bottle,
                    folder: values["INSTALL_FOLDER"] ?? "", installer: values["INSTALLER_PATH"] ?? "", stage: stage
                ))
            }
        }
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
