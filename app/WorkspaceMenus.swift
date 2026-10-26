import SwiftUI

struct WorkspaceActions {
    var perform: (WorkspaceCommand) -> Void
    var disabledReason: (WorkspaceCommand) -> String?
    var navigate: (WorkspaceDestination) -> Void
    var newEnvironment: () -> Void
    var openHelp: () -> Void
    var checkUpdates: () -> Void
}
private struct WorkspaceActionsKey: FocusedValueKey { typealias Value = WorkspaceActions }
extension FocusedValues {
    var workspaceActions: WorkspaceActions? {
        get { self[WorkspaceActionsKey.self] }
        set { self[WorkspaceActionsKey.self] = newValue }
    }
}

struct WorkspaceMenus: Commands {
    @FocusedValue(\.workspaceActions) private var actions
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            item(.install).keyboardShortcut("n", modifiers: .command)
            item(.addExecutable).keyboardShortcut("o", modifiers: .command)
            Button("New Environment…") { actions?.newEnvironment() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil || actions?.disabledReason(.refresh) != nil)
        }
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(after: .sidebar) {
            Button("Library") { actions?.navigate(.library) }.keyboardShortcut("1", modifiers: .command)
            Button("Installations") { actions?.navigate(.installations) }.keyboardShortcut("2", modifiers: .command)
            Button("Environments") { actions?.navigate(.environments) }.keyboardShortcut("3", modifiers: .command)
            Button("Components") { actions?.navigate(.components) }.keyboardShortcut("4", modifiers: .command)
            Button("Activity") { actions?.navigate(.activity) }.keyboardShortcut("5", modifiers: .command)
            Divider()
            item(.focusSearch).keyboardShortcut("f", modifiers: .command)
            item(.refresh).keyboardShortcut("r", modifiers: .command)
        }
        CommandMenu("Game") {
            item(.play).keyboardShortcut(.return, modifiers: .command)
            item(.edit)
            item(.buildApp)
            Divider()
            item(.reveal)
            item(.checkFiles)
            item(.diagnose)
        }
        CommandGroup(replacing: .help) {
            Button("Windows Game Installation Guide") { actions?.openHelp() }.disabled(actions == nil)
            Button("Show Activity") { actions?.navigate(.activity) }.disabled(actions == nil)
        }
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { actions?.checkUpdates() }.disabled(actions == nil)
        }
    }
    private func item(_ command: WorkspaceCommand) -> some View {
        Button(command.title) { actions?.perform(command) }
            .disabled(actions == nil || actions?.disabledReason(command) != nil)
            .help(actions?.disabledReason(command) ?? command.title)
    }
}

struct WorkspaceSettingsView: View {
    @AppStorage("cosmos.useRedesignedWorkspace") private var redesigned = true
    var body: some View {
        Form {
            Section("Interface preview") {
                Toggle("Use the redesigned workspace", isOn: $redesigned)
                Text("The previous interface remains available while advanced tools move into the new screens. Your games, environments and settings stay in place.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Game settings") {
                Text("Select a game in Library to edit its settings. Manage shared Windows settings in Environments and Wine/graphics downloads in Components.")
            }
        }.padding(24).frame(width: 520)
    }
}
