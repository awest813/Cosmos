import AppKit
import SwiftUI

struct PortsDashboard: View {
    let ports: [WinePort]
    let bottleNames: [String]
    let isRunning: Bool
    var unavailableReason: String? = nil
    var onOpenDownloads: (() -> Void)? = nil
    var onInstall: (() -> Void)? = nil
    var onResumeInstall: (() -> Void)? = nil
    var requiresRosetta: Bool = false
    var onCreate: (WinePortDraft, @escaping (String?) -> Void) -> Void
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
            caption: "Turn a Windows program into a Mac app on Apple Silicon. DXMT and SpockD3D9 are enabled by default. D3DMetal is optional and stays on this Mac — it cannot be part of a port you share."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let unavailableReason {
                    CosmosNoticeBanner(
                        tint: Color.cosmosWarning, systemImage: "info.circle",
                        title: "Ports unavailable on this Mac", message: unavailableReason
                    )
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { installationActions }
                    VStack(alignment: .leading, spacing: 8) { installationActions }
                }
                HStack {
                    if let onOpenDownloads {
                        Button(action: onOpenDownloads) {
                            Label("Graphics Downloads", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning || unavailableReason != nil)
                        .help("Get SpockD3D9 and MoltenVK for your ports")
                    }
                    if !ports.isEmpty {
                        Spacer(minLength: 0)
                        Button {
                            showCreateSheet = true
                        } label: {
                            Label("New Port", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning || unavailableReason != nil)
                        .help("Wrap a Windows program as a Mac app")
                    }
                }

                if ports.isEmpty {
                    CosmosEmptyState(
                        systemImage: "macwindow.on.rectangle",
                        title: "No ports yet",
                        message: "Install a game from its setup EXE above, or create a port for a Windows .exe already installed in an environment. Steam setup is optional.",
                        isRunning: isRunning || unavailableReason != nil,
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
        .onAppear {
            if selectedID == nil { selectedID = ports.first?.id }
        }
        .onChange(of: ports) { updated in
            if selectedID == nil || !updated.contains(where: { $0.id == selectedID }) {
                selectedID = updated.first?.id
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            NewPortSheet(
                bottleNames: bottleNames,
                isRunning: isRunning,
                onCancel: { showCreateSheet = false },
                onCreate: onCreate
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

    @ViewBuilder
    private var installationActions: some View {
        if let onInstall {
            Button(action: onInstall) {
                Label("Install Classic Game", systemImage: "shippingbox.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cosmosPrimary)
            .disabled(isRunning || unavailableReason != nil)
            .help("Run setup, choose an installation folder, then open the installed game EXE")
        }
        if let onResumeInstall {
            Button(action: onResumeInstall) {
                Label("Finish Installation", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isRunning || unavailableReason != nil)
            .help("Select the installed game after setup completed; the installer will not run again")
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
            Label(requiresRosetta ? "Install Rosetta 2" : "Open", systemImage: requiresRosetta ? "cpu" : "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.cosmosPrimary)
        .disabled(isRunning || unavailableReason != nil)
        .help(requiresRosetta ? "Install Rosetta in Terminal, then open this port." : "Open this Windows program")
        Button {
            onBuild(port)
        } label: {
            Label("Make Mac App", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.bordered)
        .disabled(isRunning || unavailableReason != nil)
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

struct NewPortSheet: View {
    let bottleNames: [String]
    let isRunning: Bool
    var onCancel: () -> Void
    var onCreate: (WinePortDraft, @escaping (String?) -> Void) -> Void

    @State private var draft = WinePortDraft.empty
    @State private var isSubmitting = false
    @State private var creationError: String?
    private var isBusy: Bool { isRunning || isSubmitting }
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
                            .disabled(isBusy)
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
                        Text("The recommended stack combines DXMT for DirectX 10 and 11, SpockD3D9 for DirectX 9, and WineD3D for older games. Change the switches for this program below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("DXMT — DirectX 10 and 11 on Metal", isOn: $draft.renderers.dxmt)
                        Toggle("SpockD3D9 — DirectX 8 and 9, including 32-bit", isOn: $draft.renderers.d9vk)
                        Toggle("WineD3D — older DirectX", isOn: $draft.renderers.wineD3D)
                        Toggle("CNC-DDRAW — classic DirectDraw", isOn: $draft.renderers.cncDDraw)
                        Toggle("DXVK — DirectX 10 and 11 on Vulkan", isOn: $draft.renderers.dxvk)
                        Toggle("D3DMetal — DirectX 11 and 12", isOn: $draft.renderers.d3dmetal)
                            .disabled(draft.distribution == "share" || isBusy)
                        if draft.distribution == "share" {
                            Text("A shared port cannot include D3DMetal. Apple's license keeps that on this Mac.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
                .disabled(isBusy)
                .onChange(of: draft.exe) { path in
                    if path.hasPrefix("/"), let architecture = WindowsProgramArchitecture.detect(at: URL(fileURLWithPath: path)) {
                        draft.programArch = architecture.rawValue
                    }
                }
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
                            .disabled(isBusy)
                        Button("Browse") { browseForDirectory(into: \.cncDDrawPath, message: "Select the folder that contains ddraw.dll") }
                            .disabled(isBusy)
                    }
                }
                if draft.renderers.d3dmetal && draft.distribution == "personal" {
                    HStack {
                        TextField("Game Porting Toolkit folder", text: $draft.gptkPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isBusy)
                        Button("Browse") { browseForDirectory(into: \.gptkPath, message: "Select your Game Porting Toolkit install") }
                            .disabled(isBusy)
                    }
                    Text("Cosmos does not download D3DMetal. This path is saved only for this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(PortStack.launchSummary(draft.renderers, distribution: draft.distribution))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let creationError {
                    CosmosNoticeBanner(
                        tint: Color.cosmosDanger, systemImage: "exclamationmark.triangle.fill",
                        title: "Could not create port", message: creationError
                    )
                }

                if let validationError = draft.validationError, !draft.name.isEmpty || !draft.exe.isEmpty {
                    CosmosNoticeBanner(
                        tint: Color.cosmosDanger,
                        systemImage: "exclamationmark.triangle.fill",
                        title: nil,
                        message: validationError
                    )
                }

                HStack {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                        Text("Creating port…").font(.caption)
                    }
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .disabled(isBusy)
                    Button("Create") {
                        guard !isBusy else { return }
                        creationError = nil
                        isSubmitting = true
                        onCreate(draft) { error in
                            isSubmitting = false
                            if let error { creationError = error }
                            else { onCancel() }
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.cosmosPrimary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.validationError != nil || isBusy)
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
        panel.allowedFileTypes = ["exe"]
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
