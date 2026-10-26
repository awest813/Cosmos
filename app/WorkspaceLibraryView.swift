import SwiftUI

struct WorkspaceLibraryView: View {
    let games: [WorkspaceGame]
    @Binding var selection: String?
    let reason: (WorkspaceCommand) -> String?
    let perform: (WorkspaceCommand) -> Void
    var searchRequest: Int = 0
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var source = "All"

    private var visible: [WorkspaceGame] {
        games.filter { (source == "All" || $0.source == source) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.executable.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Library").font(.largeTitle.bold())
                Spacer()
                Text("\(games.count) games").foregroundStyle(.secondary)
            }
            HStack {
                TextField("Search games or executable paths", text: $query)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Search Library").focused($searchFocused)
                Picker("Source", selection: $source) {
                    Text("All Sources").tag("All")
                    ForEach(Array(Set(games.map(\.source))).sorted(), id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 190)
            }
            if games.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "gamecontroller").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Your games belong here").font(.title2.bold())
                    Text("Install a Windows game or add an EXE you already have. Steam setup is optional.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack { commandButton(.install); commandButton(.addExecutable) }
                    if let issue = reason(.install) { Text(issue).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, minHeight: 250)
            } else if visible.isEmpty {
                Text("No games match this search. Change the search or source filter.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                // A single collection for both source types. Selection is a
                // namespaced record ID, never a title or an array index.
                ScrollView {
                  LazyVStack(spacing: 8) {
                   ForEach(visible) { game in
                    Button { selection = game.id } label: {
                        HStack(spacing: 12) {
                            Image(systemName: game.source == "Standalone" ? "macwindow" : "gamecontroller")
                                .font(.title2).frame(width: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(game.name).font(.headline)
                                Text(game.source).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection == game.id { Image(systemName: "checkmark.circle.fill") }
                        }.padding(12).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(selection == game.id ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityAddTraits(selection == game.id ? .isSelected : [])
                    .contextMenu {
                        Button("Select Game") { selection = game.id }
                        // Commands only act on the selected context; another
                        // row cannot accidentally launch the previous game.
                        if selection == game.id {
                            commandButton(.play); commandButton(.edit); commandButton(.buildApp)
                            Divider(); commandButton(.reveal); commandButton(.checkFiles); commandButton(.diagnose)
                        }
                    }
                   }
                  }
                }
                .frame(height: 400)
            }
        }
        .onAppear { if searchRequest > 0 { searchFocused = true } }
        .onChange(of: searchRequest) { _ in searchFocused = true }
        .onChange(of: games.map(\.source)) { sources in
            if source != "All" && !sources.contains(source) { source = "All" }
        }
    }
    private func commandButton(_ command: WorkspaceCommand) -> some View {
        Button(command.title) { perform(command) }
            .disabled(reason(command) != nil).help(reason(command) ?? command.title)
    }
}
