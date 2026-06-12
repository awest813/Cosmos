import Foundation

enum GameProfileWriterError: LocalizedError {
    case invalidSteamAppID
    case invalidGOGSlug
    case emptyName
    case missingRepositoryRoot
    case suggestFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSteamAppID:
            return "Enter a numeric Steam App ID."
        case .invalidGOGSlug:
            return "Enter a GOG folder slug (letters, numbers, hyphens)."
        case .emptyName:
            return "Enter a display name for the game."
        case .missingRepositoryRoot:
            return "Could not locate the Cosmos repository root."
        case .suggestFailed(let detail):
            return detail
        case .writeFailed(let detail):
            return detail
        }
    }
}

/// Creates and saves user-authored YAML game profiles under Application Support.
enum GameProfileWriter {
    private static let fileManager = FileManager.default

    static func suggestSteamYAML(appID: String, repositoryRoot: URL) throws -> String {
        let trimmed = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.allSatisfy(\.isNumber), !trimmed.isEmpty else {
            throw GameProfileWriterError.invalidSteamAppID
        }
        let script = repositoryRoot.appendingPathComponent("cosmosdb.command")
        guard fileManager.isExecutableFile(atPath: script.path) else {
            throw GameProfileWriterError.missingRepositoryRoot
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "suggest-profile", trimmed]
        process.currentDirectoryURL = repositoryRoot
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0, !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GameProfileWriterError.suggestFailed(
                err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Could not generate a profile draft for App ID \(trimmed)."
                    : err.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return out
    }

    static func buildGOGYAML(name: String, slug: String, exePath: String) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedName.isEmpty else { throw GameProfileWriterError.emptyName }
        guard trimmedSlug.range(of: #"^[a-z0-9][a-z0-9-]*$"#, options: .regularExpression) != nil else {
            throw GameProfileWriterError.invalidGOGSlug
        }
        let profileID = trimmedSlug.replacingOccurrences(of: "-", with: "_")
        let path = exePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let exeLine = path.isEmpty
            ? "drive_c/GOG Games/\(trimmedName)/game.exe"
            : path
        return """
        id: \(profileID)
        name: "\(escapeYAML(trimmedName))"
        store: gog
        gog_slug: \(trimmedSlug)
        status: playable
        recommended_backend: dxmt
        wine_version: cosmos-stable
        exe_path: \(exeLine)
        settings:
          retina: false
          windows_version: win10
        notes: User-authored GOG profile. Adjust exe_path after registering the install folder.
        """
    }

    @discardableResult
    static func saveUserProfile(
        yaml: String,
        store: String,
        suggestedFilename: String
    ) throws -> URL {
        let storeName = store.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let storeDir = CosmosPaths.userGameProfilesDirectory
            .appendingPathComponent(storeName, isDirectory: true)
        try fileManager.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let safeName = suggestedFilename
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: "/", with: "-")
        let fileURL = storeDir.appendingPathComponent(safeName.hasSuffix(".yaml") ? safeName : "\(safeName).yaml")
        do {
            try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw GameProfileWriterError.writeFailed(error.localizedDescription)
        }
        return fileURL
    }

    static func suggestedSteamFilename(appID: String, yaml: String) -> String {
        if let name = GameProfileStore.scalarPreview(in: yaml, key: "name") {
            let slug = name
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            if !slug.isEmpty {
                return "steam-\(appID)-\(slug).yaml"
            }
        }
        return "steam-\(appID)-profile.yaml"
    }

    static func suggestedGOGFilename(slug: String) -> String {
        "gog-\(slug.lowercased()).yaml"
    }

    private static func escapeYAML(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
