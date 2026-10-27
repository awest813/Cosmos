import Foundation

/// Review is a snapshot of the exact recipe bytes, not executable instructions.
struct EnvironmentRecipe: Identifiable, Hashable {
    let recipe: RepairRecipe
    let contents: String
    let revision: String
    let fields: [String: String]
    var id: String { recipe.kind.rawValue + ":" + recipe.id }
    var unsupportedReason: String? {
        guard fields["ID"] == recipe.id, fields["TYPE"] == recipe.kind.rawValue,
              recipe.id.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else {
            return "Recipe identity does not match its file."
        }
        if recipe.kind == .dependency {
            guard let verb = fields["WINETRICKS"], verb.range(of: "^[a-zA-Z0-9_]+$", options: .regularExpression) != nil else {
                return "This recipe requires advanced review."
            }
        } else if fields["SCRIPT"] != "dll_override" || (fields["DLL_OVERRIDE"] ?? "").isEmpty {
            return "Use the dedicated environment actions or advanced tools for this fix; it needs additional choices or has a wider effect."
        }
        return nil
    }
    var arguments: [String] { ["reviewed-recipe", recipe.kind.rawValue, recipe.id, revision] }
    var effect: String {
        recipe.kind == .dependency
            ? "Runs external winetricks to install \(fields["WINETRICKS"] ?? recipe.id). It may download files and display Windows installer or license prompts."
            : "Changes shared Windows DLL registry overrides: \(fields["DLL_OVERRIDE"] ?? "See recipe below")."
    }
    static func parse(data: Data, fileID: String, kind: RepairRecipe.Kind) -> EnvironmentRecipe? {
        guard let contents = String(data: data, encoding: .utf8) else { return nil }
        let fields = ConfParser.parse(contents)
        return EnvironmentRecipe(recipe: RepairRecipe(id: fileID, kind: kind, description: fields["DESCRIPTION"] ?? fileID),
            contents: contents, revision: EnvironmentSettingsDraft.digest(data), fields: fields)
    }
    static func load() -> [EnvironmentRecipe] {
        let directories: [(URL?, RepairRecipe.Kind)] = [(CosmosPaths.dependencyRecipesDirectory, .dependency), (CosmosPaths.fixRecipesDirectory, .fix)]
        return directories.flatMap { directory, kind -> [EnvironmentRecipe] in
            guard let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
            return files.filter { $0.pathExtension == "recipe" }.compactMap { file in
                guard let data = try? Data(contentsOf: file) else { return nil }
                return parse(data: data, fileID: file.deletingPathExtension().lastPathComponent, kind: kind)
            }
        }.sorted { $0.id < $1.id }
    }
}

struct EnvironmentToolsRequest: Identifiable {
    let id = UUID()
    let environment: WorkspaceEnvironment
    let runtimeRoot: String
    var commandEnvironment: [String: String] {
        var result = environment.commandEnvironment
        result["WINE_ROOT"] = runtimeRoot
        result["COSMOS_SUPPORT_DIR"] = CosmosPaths.supportDirectory.path
        result["COSMOS_BOTTLES_DIR"] = BottleStore.bottlesDirectoryURL.path
        if let root = CosmosPaths.cosmosRoot() { result["SCRIPT_DIR"] = root.path }
        return result
    }
}
