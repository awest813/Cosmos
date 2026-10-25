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
    var pendingInstallations: [PendingGameInstallation] = []
    var onContinueInstallation: ((PendingGameInstallation, Bool) -> Void)? = nil
    var requiresRosetta: Bool = false
    var onUpdate: ((WinePort, WinePortDraft, @escaping (String?) -> Void) -> Void)? = nil
    var onOpenLogs: ((WinePort) -> Void)? = nil
    var onCreate: (WinePortDraft, @escaping (String?) -> Void) -> Void
    var onLaunch: (WinePort) -> Void
    var onBuild: (WinePort) -> Void
    var onDelete: (WinePort) -> Void

    @State private var selectedID: String?
    @State private var showCreateSheet = false
    @State private var pendingDelete: WinePort?
    @State private var editingPort: WinePort?
    @State private var fileCheck: PortFileCheck?

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
                if !pendingInstallations.isEmpty, let onContinueInstallation {
                    PendingGameInstallationsView(
                        installations: pendingInstallations,
                        isBusy: isRunning || unavailableReason != nil,
                        onContinue: onContinueInstallation
                    )
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
            fileCheck = nil
            if selectedID == nil || !updated.contains(where: { $0.id == selectedID }) {
                selectedID = updated.first?.id
            }
        }
        .onChange(of: selectedID) { _ in fileCheck = nil }
        .sheet(isPresented: $showCreateSheet) {
            NewPortSheet(
                bottleNames: bottleNames,
                isRunning: isRunning,
                onCancel: { showCreateSheet = false },
                onCreate: onCreate
            )
        }
        .sheet(item: $editingPort) { port in
            NewPortSheet(
                bottleNames: bottleNames, isRunning: isRunning,
                initialDraft: WinePortDraft(port: port), isEditing: true,
                onCancel: { editingPort = nil },
                onCreate: { draft, completion in onUpdate?(port, draft, completion) }
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
                Label("Install Windows Game", systemImage: "shippingbox.fill")
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
            Text("Environment: \(port.bottleLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { recoveryActions(port) }
                VStack(alignment: .leading, spacing: 8) { recoveryActions(port) }
            }
            if let fileCheck {
                PortFileCheckView(port: port, check: fileCheck)
                    .id(fileCheck.report(for: port))
            }
            if let prefix = port.environmentPrefixURL {
                DisclosureGroup("Windows environment files") {
                    WineEnvironmentFilesView(layout: WineEnvironmentLayout(prefix: prefix))
                        .padding(.top, 8)
                }
            }
        }
        .padding(CosmosSpacing.cardPadding)
        .cosmosCard()
    }

    @ViewBuilder
    private func recoveryActions(_ port: WinePort) -> some View {
        Button {
            fileCheck = PortFileCheck.inspect(port)
        } label: {
            Label("Check Game Files", systemImage: "checkmark.doc")
        }
        .buttonStyle(.bordered)
        .help("Check the game EXE, saved architecture and environment without running Wine")
        Button {
            let check = PortFileCheck.inspect(port)
            fileCheck = check
            if let url = check.gameURL, FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } label: {
            Label("Show Game Files", systemImage: "folder")
        }
        .buttonStyle(.bordered)
        if let onOpenLogs {
            Button { onOpenLogs(port) } label: {
                Label("Open Launch Log", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .disabled(isRunning)
            .help("Open the launch log for this port's environment")
        }
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
        if onUpdate != nil {
            Button { editingPort = port } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .disabled(isRunning || unavailableReason != nil)
            .help("Change the program, arguments, Windows version, or graphics without reinstalling")
        }
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

struct PendingGameInstallationsView: View {
    let installations: [PendingGameInstallation]
    let isBusy: Bool
    var onContinue: (PendingGameInstallation, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unfinished installations").font(.headline)
            ForEach(installations) { installation in
                VStack(alignment: .leading, spacing: 6) {
                    Text(installation.name).font(.subheadline.weight(.semibold))
                    Text(installation.statusLabel).font(.caption).foregroundStyle(.secondary)
                    Text(installation.folder).font(.caption2).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if installation.stage != "prepared" {
                            Button("Finish Installation") { onContinue(installation, false) }
                                .help("Skip setup and select the installed game EXE")
                        }
                        Button(installation.stage == "prepared" ? "Run Setup" : "Retry Setup") {
                            onContinue(installation, true)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }
                .accessibilityElement(children: .contain)
            }
        }
        .padding(CosmosSpacing.cardPadding)
        .cosmosCard()
    }
}

struct WineEnvironmentFilesView: View {
    let layout: WineEnvironmentLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(layout.locations) { location in locationRow(location) }
            if !layout.drives.isEmpty {
                Text("Windows drive mappings").font(.headline)
                ForEach(layout.drives) { location in locationRow(location) }
            }
            Text("Some Windows folders link to Mac folders. Browsing changes no files. In a 64-bit/WoW64 environment, system32 holds 64-bit DLLs and syswow64 holds 32-bit DLLs; a 32-bit-only environment uses system32 for 32-bit DLLs.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func locationRow(_ location: WineEnvironmentLayout.Location) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(location.title).font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location.url.path)
                } label: { Image(systemName: "folder") }
                .buttonStyle(.bordered)
                .accessibilityLabel("Open \(location.title) in Finder")
                .help("Open this folder in Finder")
                .disabled(!location.isAvailable)
            }
            Text(location.url.path).font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if !location.isAvailable {
                Text("Not created or unavailable").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct PortFileCheckView: View {
    let port: WinePort
    let check: PortFileCheck
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Game file checks").font(.headline)
            ForEach(check.findings) { finding in
                Label(finding.message, systemImage: finding.passed ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(finding.passed ? Color.secondary : Color.cosmosWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("These checks do not run the game or verify Wine, graphics, or gameplay.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(copied ? "Details Copied" : "Copy Check Details") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(check.report(for: port), forType: .string)
                copied = true
            }
            .buttonStyle(.bordered)
        }
        .font(.subheadline)
        .accessibilityElement(children: .contain)
    }
}

struct NewPortSheet: View {
    let bottleNames: [String]
    let isRunning: Bool
    let isEditing: Bool
    var onCancel: () -> Void
    var onCreate: (WinePortDraft, @escaping (String?) -> Void) -> Void

    @State private var draft: WinePortDraft
    @State private var isSubmitting = false
    @State private var creationError: String?
    private var isBusy: Bool { isRunning || isSubmitting }
    @FocusState private var nameFocused: Bool

    init(
        bottleNames: [String], isRunning: Bool,
        initialDraft: WinePortDraft = .empty, isEditing: Bool = false,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (WinePortDraft, @escaping (String?) -> Void) -> Void
    ) {
        self.bottleNames = bottleNames
        self.isRunning = isRunning
        self.isEditing = isEditing
        self.onCancel = onCancel
        self.onCreate = onCreate
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CosmosSpacing.cardPadding) {
                Text(isEditing ? "Edit Port" : "New Port")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CosmosGradients.heroTitle)
                Text("Apple Silicon, macOS 14.6 or later. The Windows program opens like a Mac app, using the graphics stack below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isEditing {
                    Text("Saving updates this port without reinstalling the game. Use Make Mac App afterward to apply changes to a previously built app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                        ForEach(Array(Set(bottleNames + (draft.bottle.isEmpty ? [] : [draft.bottle]))).sorted(), id: \.self) { name in
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
                        title: isEditing ? "Could not save port" : "Could not create port", message: creationError
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
                        Text(isEditing ? "Saving port…" : "Creating port…").font(.caption)
                    }
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .disabled(isBusy)
                    Button(isEditing ? "Save Changes" : "Create") {
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
