import AppKit
import SwiftUI

struct PortsDashboard: View {
    let ports: [WinePort]
    let bottleNames: [String]
    let isRunning: Bool
    var onCreate: (WinePortDraft) -> Void
    var onLaunch: (WinePort) -> Void
    var onBuild: (WinePort) -> Void
    var onDelete: (WinePort) -> Void

    @State private var selectedID: String?
    @State private var showCreateSheet = false
    @State private var pendingDelete: WinePort?

    private var selectedPort: WinePort? {
        ports.first { $0.id == selectedID }
    }

    var body: some View {
        CosmosSection(
            title: "Ports",
            systemImage: "macwindow.on.rectangle",
            caption: "Turn a Windows program into a Mac app on Apple Silicon. DXMT and D9VK are on by default. D3DMetal is optional and stays on this Mac — it cannot be part of a port you share."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if !ports.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            showCreateSheet = true
                        } label: {
                            Label("New Port", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning)
                        .help("Wrap a Windows program as a Mac app")
                    }
                }

                if ports.isEmpty {
                    CosmosEmptyState(
                        systemImage: "macwindow.on.rectangle",
                        title: "No ports yet",
                        message: "A port opens one Windows program like a Mac app. It uses a bottle you already have, or the main environment.",
                        isRunning: isRunning,
                        actions: [(title: "Create Port", prominent: true, action: { showCreateSheet = true })]
                    )
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: CosmosSpacing.gridColumnMin), spacing: CosmosSpacing.gridGap)],
                        spacing: CosmosSpacing.gridGap
                    ) {
                        ForEach(ports) { port in
                            portCard(port)
                        }
                    }
                }

                if let port = selectedPort {
                    portDetail(port)
                }
            }
        }
        .onChange(of: ports) { updated in
            if let selectedID, !updated.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            NewPortSheet(
                bottleNames: bottleNames,
                isRunning: isRunning,
                onCancel: { showCreateSheet = false },
                onCreate: { draft in
                    showCreateSheet = false
                    onCreate(draft)
                }
            )
        }
        .confirmationDialog(
            "Delete this port?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Port", role: .destructive) {
                if let port = pendingDelete {
                    onDelete(port)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Removes the port definition. A Mac app you already built stays where it is.")
        }
    }

    private func portCard(_ port: WinePort) -> some View {
        let isSelected = port.id == selectedID
        return Button {
            selectedID = isSelected ? nil : port.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.title2)
                        .foregroundStyle(Color.cosmosPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(port.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(port.distributionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.cosmosBright)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Text(port.cardDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .cosmosSelectableSurface(isSelected: isSelected, minHeight: 108)
        }
        .buttonStyle(CosmosButtonStyle())
        .disabled(isRunning)
        .opacity(isRunning ? 0.55 : 1)
        .accessibilityLabel("\(port.name), \(port.cardDetail)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func portDetail(_ port: WinePort) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(port.name)
                        .font(.title3.weight(.semibold))
                    Text(port.cardDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    selectedID = nil
                } label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close port details")
            }
            Text(port.exe)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(PortStack.launchSummary(port.renderers, distribution: port.distribution))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if port.distribution == "personal", port.renderers.d3dmetal {
                CosmosNoticeBanner(
                    tint: Color.cosmosWarning,
                    systemImage: "lock.fill",
                    title: "Personal D3DMetal",
                    message: "Game Porting Toolkit stays on this Mac. Cosmos does not include it, and this port cannot be shared with D3DMetal on."
                )
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { portActions(port) }
                VStack(alignment: .leading, spacing: 8) { portActions(port) }
            }
        }
        .padding(CosmosSpacing.cardPadding)
        .cosmosCard()
    }

    @ViewBuilder
    private func portActions(_ port: WinePort) -> some View {
        Button {
            onLaunch(port)
        } label: {
            Label("Open", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.cosmosPrimary)
        .disabled(isRunning)
        Button {
            onBuild(port)
        } label: {
            Label("Make Mac App", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
        .help("Builds an app in ~/Applications/Cosmos Ports")
        Button(role: .destructive) {
            pendingDelete = port
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
    }
}

private struct NewPortSheet: View {
    let bottleNames: [String]
    let isRunning: Bool
    var onCancel: () -> Void
    var onCreate: (WinePortDraft) -> Void

    @State private var draft = WinePortDraft.empty
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CosmosSpacing.cardPadding) {
                Text("New Port")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CosmosGradients.heroTitle)
                Text("Apple Silicon, macOS 14.6 or later. The Windows program opens like a Mac app, using the graphics stack below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Form {
                    TextField("Name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                    HStack {
                        TextField("Windows program", text: $draft.exe)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse") { browseForExecutable() }
                            .disabled(isRunning)
                    }
                    Picker("Bottle", selection: $draft.bottle) {
                        Text("Main environment").tag("")
                        ForEach(bottleNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Picker("Who is this for?", selection: $draft.distribution) {
                        Text("This Mac only").tag("personal")
                        Text("A port I can share").tag("share")
                    }
                    Picker("Windows version", selection: $draft.windows) {
                        ForEach(BottleStore.windowsOptions, id: \.self) { version in
                            Text(SettingLabels.windowsDisplayName(version)).tag(version)
                        }
                    }
                    Picker("This program", selection: $draft.programArch) {
                        ForEach(SettingLabels.programArchOptions, id: \.self) { arch in
                            Text(SettingLabels.programArchDisplayName(arch)).tag(arch)
                        }
                    }
                    TextField("Launch arguments", text: $draft.arguments)
                        .textFieldStyle(.roundedBorder)
                    Text(draft.programArch == "win32"
                        ? "32-bit programs run inside the 64-bit environment. SpockD3D9 uses the 32-bit DirectX 9 DLL when it is built."
                        : "Leave launch arguments empty unless the program needs them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Retina mode", isOn: $draft.retina)
                    Section("Graphics") {
                        Text("These stay on together. DXMT covers DirectX 10 and 11. SpockD3D9 covers DirectX 9. WineD3D covers the rest.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("DXMT — DirectX 10 and 11 on Metal", isOn: $draft.renderers.dxmt)
                        Toggle("SpockD3D9 — DirectX 8 and 9, including 32-bit", isOn: $draft.renderers.d9vk)
                        Toggle("WineD3D — older DirectX", isOn: $draft.renderers.wineD3D)
                        Toggle("CNC-DDRAW — classic DirectDraw", isOn: $draft.renderers.cncDDraw)
                        Toggle("DXVK — DirectX 10 and 11 on Vulkan", isOn: $draft.renderers.dxvk)
                        Toggle("D3DMetal — DirectX 11 and 12", isOn: $draft.renderers.d3dmetal)
                            .disabled(draft.distribution == "share" || isRunning)
                        if draft.distribution == "share" {
                            Text("A shared port cannot include D3DMetal. Apple's license keeps that on this Mac.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
                .disabled(isRunning)
                .onChange(of: draft.distribution) { value in
                    if value == "share" {
                        draft.renderers.d3dmetal = false
                        draft.gptkPath = ""
                    }
                }

                if draft.renderers.cncDDraw {
                    HStack {
                        TextField("ddraw.dll folder (optional)", text: $draft.cncDDrawPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isRunning)
                        Button("Browse") { browseForDirectory(into: \.cncDDrawPath, message: "Select the folder that contains ddraw.dll") }
                            .disabled(isRunning)
                    }
                }
                if draft.renderers.d3dmetal && draft.distribution == "personal" {
                    HStack {
                        TextField("Game Porting Toolkit folder", text: $draft.gptkPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isRunning)
                        Button("Browse") { browseForDirectory(into: \.gptkPath, message: "Select your Game Porting Toolkit install") }
                            .disabled(isRunning)
                    }
                    Text("Cosmos does not download D3DMetal. This path is saved only for this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(PortStack.launchSummary(draft.renderers, distribution: draft.distribution))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let validationError = draft.validationError, !draft.name.isEmpty || !draft.exe.isEmpty {
                    CosmosNoticeBanner(
                        tint: Color.cosmosDanger,
                        systemImage: "exclamationmark.triangle.fill",
                        title: nil,
                        message: validationError
                    )
                }

                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .disabled(isRunning)
                    Button("Create") { onCreate(draft) }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.cosmosPrimary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.validationError != nil || isRunning)
                }
            }
            .padding(20)
        }
        .frame(width: 560)
        .frame(minHeight: 520, maxHeight: 680)
        .background(Color.cosmosContentBackground)
        .onAppear { nameFocused = true }
    }

    private func browseForExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the Windows program"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.exe = url.path
    }

    private func browseForDirectory(into keyPath: WritableKeyPath<WinePortDraft, String>, message: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft[keyPath: keyPath] = url.path
    }
}
