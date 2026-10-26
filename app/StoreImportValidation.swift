import Foundation

enum StoreImportValidation {
    static func validate(
        request: StoreImportRequest,
        values: [StoreImportRequest.FieldKind: String]
    ) -> String? {
        func trimmed(_ kind: StoreImportRequest.FieldKind) -> String {
            (values[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let path = trimmed(.path)
        let slug = trimmed(.battlenetSlug)
        let epic = trimmed(.epicAppName)
        if request.script == "profile.command", request.baseArguments.first == "upstream-recipe" {
            return path.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
                ? nil : "Enter a recipe id such as xact. List available ids with profile.command upstream-recipes."
        }
        if request.script == "bottle.command", request.baseArguments.first == "clone" {
            return BottleStore.isValidName(trimmed(.displayName)) ? nil : "Use an environment name with letters, numbers, dots, underscores or hyphens."
        }

        if request.script == "scripts/install_program.command" {
            if !request.baseArguments.contains("resume"),
               !path.hasPrefix("/") || !(path.lowercased().hasSuffix(".exe") || path.lowercased().hasSuffix(".msi")) {
                return "Choose an installer .exe or .msi on your Mac, or enter its full path starting with /."
            }
            if trimmed(.displayName).isEmpty { return "Enter the game title." }
            if !WinePortDraft.isValidPortName(trimmed(.displayName)) {
                return "Enter a game title without / or :."
            }
            let folder = trimmed(.installDirectory)
            let bottle = trimmed(.installationBottle)
            if !bottle.isEmpty && !BottleStore.isValidName(bottle) {
                return "The saved installation environment name is invalid."
            }
            let windowsFolder = folder.range(of: "^[A-Za-z]:[\\\\/]", options: .regularExpression) != nil
            if !folder.isEmpty && (!folder.hasPrefix("/") && !folder.hasPrefix("drive_c/") && !windowsFolder) {
                return "Choose a Mac folder, or use an absolute Windows drive path or drive_c/... path."
            }
            if folder.contains("\n") || (folder.hasPrefix("drive_c/") && folder.split(separator: "/").contains("..")) {
                return "The installation folder must stay inside drive_c and contain no line breaks."
            }
            let game = trimmed(.gameExecutable)
            if !game.isEmpty && !game.lowercased().hasSuffix(".exe") {
                return "Choose the installed game .exe, rather than its installer or folder."
            }
            return nil
        }

        if request.baseArguments.contains("add-gog") {
            if path.isEmpty {
                return "Enter a GOG setup .exe, install folder, or slug from List GOG Games."
            }
            let lower = path.lowercased()
            if lower.hasSuffix(".exe"), !path.hasPrefix("drive_c/"), !path.hasPrefix("/") {
                return "Use Choose… to pick the installer, or enter a full path starting with / or drive_c/."
            }
            return nil
        }

        if request.baseArguments.contains("add-epic") {
            if epic.isEmpty { return "Enter the Legendary app name (from list-epic)." }
            return nil
        }

        if request.baseArguments.contains("add-battlenet") {
            if slug.isEmpty { return "Enter a Battle.net slug or full .exe path." }
            return nil
        }

        if request.fields.contains(where: { $0.id == .path }) {
            if path.isEmpty { return "Enter a file or folder path, or use Choose…." }
            if request.baseArguments.contains("add-exe") || request.baseArguments.contains("find-exe") {
                let lower = path.lowercased()
                if !lower.hasSuffix(".exe"), !path.contains("/"), !path.contains("\\") {
                    return "Enter a folder path or a path ending in .exe."
                }
            }
        }

        return nil
    }
}
