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
