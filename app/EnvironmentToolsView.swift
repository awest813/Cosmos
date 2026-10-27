import SwiftUI

struct EnvironmentToolsView: View {
    let request: EnvironmentToolsRequest
    let busy: Bool
    let hostIssue: String?
    let onClose: () -> Void
    let onRun: (EnvironmentRecipe, @escaping (String?) -> Void) -> Void
    @State private var recipes: [EnvironmentRecipe] = []
    @State private var loaded = false
    @State private var selection: String?
    @State private var running = false
    @State private var result: String?
    @State private var failed = false
    init(request: EnvironmentToolsRequest, busy: Bool, hostIssue: String?, initialRecipes: [EnvironmentRecipe]? = nil,
         onClose: @escaping () -> Void, onRun: @escaping (EnvironmentRecipe, @escaping (String?) -> Void) -> Void) {
        self.request = request; self.busy = busy; self.hostIssue = hostIssue
        self.onClose = onClose; self.onRun = onRun
        _recipes = State(initialValue: initialRecipes ?? [])
        _loaded = State(initialValue: initialRecipes != nil)
        _selection = State(initialValue: initialRecipes?.first?.id)
    }
    private var selected: EnvironmentRecipe? { recipes.first { $0.id == selection } }
    private var blocked: String? {
        if busy || running { return "Wait for the current operation to finish." }
        if let hostIssue { return hostIssue }
        if !request.environment.initialized { return "Initialize this environment by installing a game before applying recipes." }
        return selected?.unsupportedReason
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dependencies & Fixes — \(request.environment.name)").font(.title2.bold())
            Text("Install only what a game needs. These changes affect the shared environment. Save and quit its games, then clone first if you need a backup.").foregroundStyle(.secondary)
            LabeledContent("Wine version", value: request.environment.wineVersion)
            Text(request.environment.prefix.path).font(.caption).textSelection(.enabled)
            if !loaded { ProgressView("Reading bundled recipes…") }
            else if recipes.isEmpty { Text("No recipes could be read. Check the app's recipe bundle before retrying.") }
            else {
                HSplitView {
                    List(selection: $selection) {
                        ForEach([RepairRecipe.Kind.dependency, .fix], id: \.rawValue) { kind in
                            Section(kind == .dependency ? "Dependencies" : "Fixes") {
                                ForEach(recipes.filter { $0.recipe.kind == kind }) { item in
                                    Text(item.recipe.displayTitle).tag(item.id)
                                }
                            }
                        }
                    }.frame(minWidth: 210, idealWidth: 245).disabled(running)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let selected {
                                Text(selected.recipe.displayTitle).font(.headline)
                                Text(selected.effect)
                                Text("Source: bundled Cosmos recipe. Original comments and attribution are preserved below. Upstream reports do not verify this game on this Mac.").font(.caption).foregroundStyle(.secondary)
                                Text(selected.contents).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                if selected.recipe.kind == .dependency { Text("Requires separately installed winetricks (brew install winetricks) and the selected Wine runtime in Components. Cosmos will not substitute another Wine from PATH.").font(.caption) }
                                if let blocked { Label(blocked, systemImage: "info.circle").font(.caption) }
                            } else { Text("Choose a recipe to review its exact contents and effect.").foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }.frame(minWidth: 280)
                }
            }
            if let result { Label(result, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle").font(.caption).textSelection(.enabled) }
            HStack {
                if running { ProgressView("Applying recipe…").controlSize(.small) }
                Spacer()
                Button("Close", action: onClose).keyboardShortcut(.cancelAction).disabled(running)
                Button("Apply Reviewed Recipe") {
                    guard let selected, blocked == nil else { return }
                    running = true; result = nil
                    onRun(selected) { error in
                        running = false; failed = error != nil
                        result = error ?? "Recipe completed. Test the game to verify compatibility. Details are in Activity."
                    }
                }.disabled(selected == nil || blocked != nil).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 760, height: 620)
            .onAppear {
                guard !loaded else { return }
                DispatchQueue.global(qos: .utility).async {
                    let items = EnvironmentRecipe.load()
                    DispatchQueue.main.async { recipes = items; loaded = true }
                }
            }
            .onChange(of: selection) { _ in result = nil }
    }
}
