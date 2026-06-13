import Foundation

struct RepairRecipe: Identifiable, Hashable {
    enum Kind: String {
        case dependency
        case fix
    }

    let id: String
    let kind: Kind
    let description: String

    /// Human-friendly label for repair recipe tiles.
    var displayTitle: String {
        if !description.isEmpty, description != id {
            return description
        }
        return id
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    var displaySubtitle: String {
        description.isEmpty || description == id ? id : id
    }
}

enum RecipeStore {
    private static let fileManager = FileManager.default

    static func loadDependencies() -> [RepairRecipe] {
        guard let dir = CosmosPaths.dependencyRecipesDirectory else { return [] }
        return loadRecipes(in: dir, kind: .dependency)
    }

    static func loadFixes() -> [RepairRecipe] {
        guard let dir = CosmosPaths.fixRecipesDirectory else { return [] }
        return loadRecipes(in: dir, kind: .fix)
    }

    private static func loadRecipes(in directory: URL, kind: RepairRecipe.Kind) -> [RepairRecipe] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "recipe" }
            .compactMap { parseRecipe(at: $0, kind: kind) }
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    private static func parseRecipe(at url: URL, kind: RepairRecipe.Kind) -> RepairRecipe? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fields = ConfParser.parse(text)
        guard let id = fields["ID"], !id.isEmpty else { return nil }
        let description = fields["DESCRIPTION"] ?? id
        return RepairRecipe(id: id, kind: kind, description: description)
    }
}

/// KEY="value" files shared by bottles, recipes, and steam.conf.
enum ConfParser {
    static func parse(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { result[key] = value }
        }
        return result
    }
}
