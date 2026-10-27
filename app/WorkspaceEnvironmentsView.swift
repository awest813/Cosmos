import AppKit
import SwiftUI

struct WorkspaceEnvironmentsView: View {
    let environments: [WorkspaceEnvironment]
    @Binding var selection: WorkspaceEnvironmentID
    let busy: Bool
    let reason: (WorkspaceEnvironmentAction) -> String?
    let perform: (WorkspaceEnvironmentAction) -> Void
    let onCreate: () -> Void
    let onOpenGame: (WinePort) -> Void
    @State private var page = "Overview"
    private var selected: WorkspaceEnvironment? { environments.first { $0.key == selection } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Environments").font(.largeTitle.bold())
                    Text("Separate Windows setups for your games. Browsing here does not change a game's launch target.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("New Environment…", action: onCreate).disabled(busy)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(environments) { environment in
                        Button { selection = environment.key } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(environment.name, systemImage: environment.bottle == nil ? "desktopcomputer" : "externaldrive")
                                    .font(.headline)
                                Text(environment.initialized ? "Initialized" : "Not initialized").font(.caption)
                                Text("\(environment.assignedGames.count) assigned games").font(.caption).foregroundStyle(.secondary)
                            }.padding(14).frame(minWidth: 190, alignment: .leading)
                                .background(environment.key == selection ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).accessibilityAddTraits(environment.key == selection ? .isSelected : [])
                    }
                }
            }
            if let selected {
                Text(selected.name).font(.title2.bold())
                Picker("Environment details", selection: $page) {
                    ForEach(["Overview", "Games", "Files", "Settings"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented)
                detail(selected)
            } else {
                Label("This environment is no longer available. Select another environment; no actions will target a replacement automatically.", systemImage: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private func detail(_ environment: WorkspaceEnvironment) -> some View {
        switch page {
        case "Games":
            Text("Games with a saved assignment to this environment").font(.headline)
            if environment.assignedGames.isEmpty { Text("No assigned standalone games. Other launchers may use a shared environment without recording ownership.").foregroundStyle(.secondary) }
            ForEach(environment.assignedGames) { game in
                Button { onOpenGame(game) } label: {
                    HStack { Text(game.name); Spacer(); Text(game.programArch == "win32" ? "32-bit" : "64-bit").foregroundStyle(.secondary); Image(systemName: "arrow.right") }
                }.buttonStyle(.bordered)
            }
            action(.install)
        case "Files":
            EnvironmentFilesInspector(prefix: environment.prefix)
        case "Settings":
            LabeledContent("Windows", value: SettingLabels.windowsDisplayName(environment.windowsVersion))
            LabeledContent("Graphics default", value: SettingLabels.backendDisplayName(environment.backend))
            Text("These shared defaults can affect every game using this environment. Per-game overrides remain in Game Settings.").foregroundStyle(.secondary)
            action(.settings)
            if environment.bottle == nil { Text("Main defaults are available in More → Steam Setup & Settings.").font(.caption).foregroundStyle(.secondary) }
            if let bottle = environment.bottle {
                DisclosureGroup("Additional saved settings") {
                    ForEach(bottle.settings.keys.sorted(), id: \.self) { key in
                        LabeledContent(key) { Text(bottle.settings[key] ?? "").textSelection(.enabled) }
                    }
                }
            }
        default:
            LabeledContent("Wine version", value: environment.wineVersion)
            LabeledContent("Program layout requested", value: environment.requestedArchitecture.isEmpty ? "Use environment defaults" : SettingLabels.prefixArchDisplayName(environment.requestedArchitecture))
            LabeledContent("Windows files") { Text(environment.prefix.path).textSelection(.enabled) }
            Text("Initialization and requested layout do not verify x86/WoW64 support or game compatibility. Files shows the actual registry architecture marker.").font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack { action(.install); action(.settings); action(.reveal) }
                VStack(alignment: .leading) { action(.install); action(.settings); action(.reveal) }
            }
            HStack { action(.logs); action(.diagnose); action(.clone) }
            action(.dependencies)
            Divider()
            Text("Recovery").font(.headline)
            Text("Clone before changing or removing Windows files. Linked external folders are not included in the copy.").font(.caption).foregroundStyle(.secondary)
            HStack { action(.stop); action(.reset); action(.delete) }
        }
    }
    private func action(_ command: WorkspaceEnvironmentAction) -> some View {
        Button(command.title, role: command.isDestructive ? .destructive : nil) { perform(command) }
            .buttonStyle(.bordered).disabled(reason(command) != nil).help(reason(command) ?? command.title)
    }
}

struct EnvironmentFilesInspector: View {
    let prefix: URL
    @State private var layout: WineEnvironmentLayout?
    @State private var architecture = "Unknown"
    @State private var token = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Registry architecture", value: architecture)
            Text("A win64 registry marker describes the prefix layout; x86/WoW64 runtime support still needs actual testing.")
                .font(.caption).foregroundStyle(.secondary)
            if let layout { WineEnvironmentFilesView(layout: layout) }
            else { ProgressView("Reading environment folders…") }
        }.onAppear { load() }.onChange(of: prefix) { _ in load() }.onDisappear { token = UUID() }
    }
    private func load() {
        let request = UUID(); token = request; layout = nil; architecture = "Unknown"
        DispatchQueue.global(qos: .utility).async {
            let result = WineEnvironmentLayout(prefix: prefix)
            var marker = "Missing or unknown"
            if let handle = try? FileHandle(forReadingFrom: prefix.appendingPathComponent("system.reg")) {
                defer { try? handle.close() }
                let header = (try? handle.read(upToCount: 4096)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                if header.split(whereSeparator: \.isNewline).contains("#arch=win32") { marker = "win32 — 32-bit prefix" }
                else if header.split(whereSeparator: \.isNewline).contains("#arch=win64") { marker = "win64 — 64-bit prefix" }
            }
            let capturedMarker = marker
            DispatchQueue.main.async { guard token == request else { return }; layout = result; architecture = capturedMarker }
        }
    }
}

struct EnvironmentSettingsView: View {
    let request: EnvironmentSettingsRequest
    let busy: Bool
    let onCancel: () -> Void
    let onSave: (EnvironmentSettingsDraft, @escaping (String?) -> Void) -> Void
    @State private var draft: EnvironmentSettingsDraft
    @State private var saving = false
    @State private var failure: String?
    init(request: EnvironmentSettingsRequest, busy: Bool, onCancel: @escaping () -> Void,
         onSave: @escaping (EnvironmentSettingsDraft, @escaping (String?) -> Void) -> Void) {
        self.request = request; self.busy = busy; self.onCancel = onCancel; self.onSave = onSave
        _draft = State(initialValue: EnvironmentSettingsDraft(bottle: request.bottle, revision: request.revision))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings for \(draft.bottle.name)").font(.title2.bold())
            Text("This environment has \(request.environment.assignedGames.count) assigned games. Shared defaults apply where games do not have their own overrides. Clone first to keep an independent setup.").foregroundStyle(.secondary)
            ScrollView {
              VStack(alignment: .leading, spacing: 12) {
            if !request.environment.assignedGames.isEmpty {
                DisclosureGroup("Assigned games to review") {
                    ForEach(request.environment.assignedGames) { Text($0.name) }
                }
            }
            Form {
                Picker("Graphics default", selection: $draft.backend) { ForEach(BottleStore.backendOptions, id: \.self) { Text(SettingLabels.backendDisplayName($0)).tag($0) } }
                Picker("Windows version", selection: $draft.windows) {
                    if draft.bottle.windowsVersion.isEmpty { Text("Keep current Wine default").tag("") }
                    ForEach(BottleStore.windowsOptions, id: \.self) { Text(SettingLabels.windowsDisplayName($0)).tag($0) }
                }
                Picker("Program layout", selection: $draft.architecture) { ForEach(SettingLabels.prefixArchOptions, id: \.self) { Text(SettingLabels.prefixArchDisplayName($0)).tag($0) } }
                    .disabled(draft.bottle.isInitialized)
                if draft.bottle.isInitialized { Text("Create a new environment for a different architecture; this does not convert existing Windows files.").font(.caption) }
                Toggle("Retina mode", isOn: $draft.retina)
                Picker("Thread synchronization", selection: $draft.sync) { ForEach(GraphicsSettings.syncModeOptions, id: \.self) { Text(GraphicsSettings.syncModeTitle($0)).tag($0) } }
            }.disabled(busy || saving)
            if !draft.changes.isEmpty {
                Text("Changes to save").font(.headline)
                ForEach(draft.summaries, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
            }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
              }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            HStack {
                if saving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction).disabled(saving)
                Button("Save Changes") {
                    saving = true; failure = nil
                    onSave(draft) { error in saving = false; if let error { failure = error } else { onCancel() } }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(busy || saving || draft.changes.isEmpty)
            }
        }.padding(24).frame(width: 570, height: 580)
    }
}
