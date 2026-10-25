import Foundation

/// Conventional Wine locations and actual drive links. Browsing never creates them.
struct WineEnvironmentLayout {
    struct Location: Identifiable {
        let id: String
        let title: String
        let url: URL
        let isAvailable: Bool
    }
    let locations: [Location]
    let drives: [Location]

    init(prefix: URL, fileManager: FileManager = .default) {
        func available(_ url: URL) -> Bool {
            var directory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
        }
        func target(_ link: URL) -> URL {
            guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: link.path) else { return link }
            if destination.hasPrefix("/") { return URL(fileURLWithPath: destination, isDirectory: true).resolvingSymlinksInPath() }
            return link.deletingLastPathComponent().appendingPathComponent(destination, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        }
        let mappings = prefix.appendingPathComponent("dosdevices", isDirectory: true)
        let cLink = mappings.appendingPathComponent("c:")
        let hasCMapping = (try? fileManager.attributesOfItem(atPath: cLink.path)) != nil || (try? fileManager.destinationOfSymbolicLink(atPath: cLink.path)) != nil
        let cDrive = hasCMapping ? target(cLink) : prefix.appendingPathComponent("drive_c", isDirectory: true)
        let entries: [(String, String, URL)] = [
            ("prefix", "Windows environment", prefix),
            ("drive-c", "C: drive", cDrive),
            ("games", "Games", cDrive.appendingPathComponent("Games", isDirectory: true)),
            ("users", "Windows user files and saves", cDrive.appendingPathComponent("users", isDirectory: true)),
            ("programs", "Program Files", cDrive.appendingPathComponent("Program Files", isDirectory: true)),
            ("programs-x86", "Program Files (x86)", cDrive.appendingPathComponent("Program Files (x86)", isDirectory: true)),
            ("system32", "Windows system files — system32", cDrive.appendingPathComponent("windows/system32", isDirectory: true)),
            ("syswow64", "32-bit system files — syswow64", cDrive.appendingPathComponent("windows/syswow64", isDirectory: true))
        ]
        locations = entries.map { Location(id: $0.0, title: $0.1, url: $0.2, isAvailable: available($0.2)) }
        let links = (try? fileManager.contentsOfDirectory(at: mappings, includingPropertiesForKeys: nil)) ?? []
        drives = links.filter { $0.lastPathComponent.range(of: "^[A-Za-z]:$", options: .regularExpression) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.map { link in
                let url = target(link)
                return Location(id: link.lastPathComponent, title: link.lastPathComponent.uppercased(), url: url, isAvailable: available(url))
            }
    }
}
