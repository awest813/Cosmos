import AppKit
import SwiftUI

extension ContentView {
    var workspaceGames: [WorkspaceGame] { WorkspaceGame.catalog(ports: ports, profiles: profiles) }
    var workspaceSelectedGame: WorkspaceGame? { workspaceGames.first { $0.id == workspaceGameID } }
    var workspaceBusy: Bool { isRunning || pendingTerminalJobID != nil }
    var workspacePortHostIssue: String? {
        PortHostSupport.unavailableReason(architecture: wineRuntime.chipArchitecture, version: ProcessInfo.processInfo.operatingSystemVersion)
    }
    func workspaceDisabledReason(_ command: WorkspaceCommand) -> String? {
        if command == .checkFiles && workspaceCheckingFiles { return "A file check is already running." }
        return WorkspaceCommandContext(
            game: workspaceDestination == .library && workspaceUtilitySection == nil ? workspaceSelectedGame : nil,
            busy: workspaceBusy, portHostIssue: workspacePortHostIssue,
            runtimeIssue: wineRuntime.canStartWineLaunch ? nil : "Review Wine and platform requirements in Components.",
            modalPresented: workspaceModalPresented
        ).disabledReason(command)
    }

    var workspaceRoot: some View {
        NavigationSplitView {
            List {
                Section("Cosmos") {
                    ForEach(WorkspaceDestination.allCases) { destination in
                        Button { workspaceDestination = destination } label: {
                            Label(destination.rawValue, systemImage: destination.systemImage)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(workspaceDestination == destination ? Color.accentColor.opacity(0.14) : Color.clear)
                        .accessibilityAddTraits(workspaceDestination == destination ? .isSelected : [])
                    }
                }
            }.listStyle(.sidebar).frame(minWidth: 200, idealWidth: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let banner = commandBannerQueue.current {
                        CommandBannerView(banner: banner) { dismissCommandBanner() }
                    }
                    if let section = workspaceUtilitySection { workspaceUtilityContent(section) }
                    else { workspaceDestinationContent }
                }.padding(24).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle(workspaceDestination.rawValue)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if workspaceBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(activeOperationTitle).lineLimit(2)
                        if pendingTerminalJobID != nil { Text("In Terminal").foregroundStyle(.secondary) }
                        Spacer()
                        Button("View Activity") { workspaceDestination = .activity }
                    }.padding(12).background(.bar)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack {
                        Button {
                            if workspaceUtilitySection != nil { workspaceUtilitySection = nil }
                            else { workspaceRouter.goBack() }
                        } label: { Label("Back", systemImage: "chevron.left") }
                            .disabled(workspaceRouter.back.isEmpty && workspaceUtilitySection == nil)
                        Button { workspaceRouter.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                            .disabled(workspaceRouter.forward.isEmpty)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        workspaceButton(.install)
                        workspaceButton(.addExecutable)
                        Divider()
                        Button("Import from Store…") { openWorkspaceUtility(.tools) }.disabled(workspaceBusy)
                    } label: { Label("Add Game", systemImage: "plus") }
                }
                ToolbarItem {
                    Menu {
                        Button("Store Import & Advanced Tools…") { openWorkspaceUtility(.tools) }
                        Button("Game Presets & Compatibility…") { openWorkspaceUtility(.library) }
                        Button("Steam Setup & Settings…") { openWorkspaceUtility(.launch) }
                        Divider()
                        Button("Use Previous Interface") { useRedesignedWorkspace = false }
                    } label: { Label("More", systemImage: "ellipsis.circle") }
                }
            }
        }
        .focusedSceneValue(\.workspaceActions, WorkspaceActions(
            perform: performWorkspaceCommand, disabledReason: workspaceDisabledReason,
            navigate: { workspaceDestination = $0 }, newEnvironment: newWorkspaceEnvironment,
            openHelp: { openRepositoryDoc(relativePath: "docs/SIMCITY_3000_SETUP.md", bundleName: "SIMCITY_3000_SETUP.md", fallbackMessage: "See the Windows installation guide in the Cosmos repository.") },
            checkUpdates: checkForUpdates, environmentReason: workspaceEnvironmentReason, environmentAction: performWorkspaceEnvironmentAction
        ))
        .onAppear {
            if let restored = WorkspaceDestination(rawValue: storedWorkspaceDestination) { workspaceDestination = restored }
        }
        .onChange(of: workspaceDestination) { destination in
            storedWorkspaceDestination = destination.rawValue
            workspaceUtilitySection = nil
        }
        .onChange(of: workspaceGameID) { _ in
            workspaceFileCheck = nil
            if case .profile(let profile)? = workspaceSelectedGame { selectedProfileID = profile.id }
        }
        .onChange(of: workspaceGames) { games in
            workspaceFileCheck = nil
            if let id = workspaceGameID, !games.contains(where: { $0.id == id }) { workspaceGameID = nil }
        }
        .sheet(isPresented: $workspaceAddingExecutable) {
            NewPortSheet(bottleNames: bottles.map(\.name), isRunning: workspaceBusy, presentationTitle: "Add Installed EXE",
                         onCancel: { workspaceAddingExecutable = false }, onCreate: { draft, done in
                let previousIDs = Set(ports.map(\.id))
                runCommand(script: "port.command", arguments: draft.commandArguments, onSuccess: {
                    workspaceDestination = .library
                    ports = WinePortStore.load()
                    let created = ports.filter { !previousIDs.contains($0.id) }
                    if created.count == 1 { workspaceGameID = WorkspaceGame.port(created[0]).id }
                }, onCompletion: { success, message in done(success ? nil : message) })
            })
        }
        .sheet(item: $installationWizard) { request in
            InstallationWizardView(request: request, bottles: bottles, busy: workspaceBusy,
                hostIssue: workspacePortHostIssue,
                requirements: "Wine is required; the selected environment's pinned version may download during setup. \(wineRuntime.needsRosetta && !wineRuntime.rosettaReady ? "Rosetta is required on this Mac; setup may ask to install it in Terminal." : "Review any installer or macOS permission prompts before proceeding.")",
                onCancel: { installationWizard = nil }, onSubmit: { draft, done in
                    guard !workspaceBusy, workspacePortHostIssue == nil else {
                        done(workspacePortHostIssue ?? "Wait for the current operation to finish."); return
                    }
                    runInTerminal(script: "scripts/install_program.command", arguments: draft.importRequest.installerArguments(values: draft.values),
                        onHandoff: { error in
                            if error == nil { workspaceDestination = .installations }
                            done(error)
                        })
                })
        }
        .sheet(item: $workspaceEditingPort) { port in
            NewPortSheet(bottleNames: bottles.map(\.name), isRunning: workspaceBusy,
                         initialDraft: WinePortDraft(port: port), isEditing: true, presentationTitle: "Game Settings",
                         onCancel: { workspaceEditingPort = nil }, onCreate: { draft, done in
                runCommand(script: "port.command", arguments: draft.commandArguments(updating: port.id),
                           onCompletion: { success, message in done(success ? nil : message) })
            })
        }
        .sheet(isPresented: $showNewBottleSheet) { newBottleSheet }
        .sheet(item: $workspaceEnvironmentSettings) { request in
            EnvironmentSettingsView(request: request, busy: workspaceBusy,
                onCancel: { workspaceEnvironmentSettings = nil }, onSave: { draft, done in
                    guard !workspaceBusy, workspaceEnvironments.contains(where: { $0.key == request.environment.key && $0.prefix == request.environment.prefix }) else {
                        done("The environment is unavailable or another operation is running."); return
                    }
                    runCommand(script: "bottle.command", arguments: draft.arguments,
                        onCompletion: { success, message in done(success ? nil : message) })
                })
        }
        .confirmationDialog(workspaceEnvironmentConfirmation?.action.title ?? "Confirm Environment Action",
            isPresented: Binding(get: { workspaceEnvironmentConfirmation != nil }, set: { if !$0 { workspaceEnvironmentConfirmation = nil } }),
            titleVisibility: .visible, presenting: workspaceEnvironmentConfirmation) { pending in
                Button(pending.action.title, role: .destructive) { confirmWorkspaceEnvironmentAction(pending) }
                Button("Cancel", role: .cancel) { workspaceEnvironmentConfirmation = nil }
            } message: { pending in Text(pending.message) }
    }

    private func workspaceUtilityContent(_ section: DashboardSection) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Additional Tools").font(.title2.bold())
                    Spacer()
                    Button("Back to Workspace") { workspaceUtilitySection = nil }
                }
                Text("These existing tools remain available while their screens are redesigned.")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 20) {
                    if section == .launch {
                        setupAssistantSection
                        steamWineSettingsSection
                        performanceGraphicsSection
                        setupToolsGrid
                    } else { dashboardSectionContent }
                }.padding(4)
            }
    }

    @ViewBuilder var workspaceDestinationContent: some View {
        switch workspaceDestination {
        case .library:
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    workspaceLibrary.frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
                    if let game = workspaceSelectedGame { workspaceGameDetail(game).frame(minWidth: 340, maxWidth: .infinity) }
                }
                VStack(alignment: .leading, spacing: 18) {
                    workspaceLibrary
                    if let game = workspaceSelectedGame { workspaceGameDetail(game) }
                }
            }
        case .installations:
            Text("Installations").font(.largeTitle.bold())
            Text("Install Windows games and continue unfinished setup. Steam is optional.").foregroundStyle(.secondary)
            HStack { workspaceButton(.install); Button("Finish an Older Installation…") { installationWizard = InstallationWizardRequest(resuming: true) }.disabled(workspaceBusy || workspacePortHostIssue != nil) }
            if let issue = workspacePortHostIssue { Text(issue).foregroundStyle(.secondary) }
            if pendingGameInstallations.isEmpty {
                Text("No unfinished installations. Registered games appear in Library.").foregroundStyle(.secondary)
            } else {
                PendingGameInstallationsView(installations: pendingGameInstallations, isBusy: workspaceBusy || workspacePortHostIssue != nil,
                    onContinue: { installation, retry in installationWizard = InstallationWizardRequest(resuming: !retry, installation: installation) })
            }
        case .environments:
            WorkspaceEnvironmentsView(environments: workspaceEnvironments, selection: $workspaceEnvironmentID,
                busy: workspaceBusy || workspaceEnvironmentReading, reason: workspaceEnvironmentReason,
                perform: performWorkspaceEnvironmentAction, onCreate: newWorkspaceEnvironment,
                onOpenGame: { port in workspaceGameID = WorkspaceGame.port(port).id; workspaceDestination = .library })
            if workspaceEnvironmentReading { ProgressView("Reading environment settings…") }
        case .components:
            Text("Components").font(.largeTitle.bold())
            Text("Manage Wine and graphics components when a game needs them.").foregroundStyle(.secondary)
            wineRuntimeSection
            Button("Manage Downloads & SpockD3D9…") { showDownloads = true }.disabled(workspaceBusy)
            performanceGraphicsSection
        case .activity:
            Text("Activity").font(.largeTitle.bold())
            Text(workspaceBusy ? activeOperationTitle : "Latest operation output").foregroundStyle(.secondary)
            if pendingTerminalJobID != nil {
                Text("The interactive operation is in Terminal. Keep Cosmos open; returning here does not cancel it.")
            }
            consoleOutputPanel
        }
    }

    private var workspaceLibrary: some View {
        WorkspaceLibraryView(games: workspaceGames, selection: $workspaceGameID, reason: workspaceDisabledReason, perform: performWorkspaceCommand, searchRequest: workspaceSearchRequest)
    }

    private func workspaceGameDetail(_ game: WorkspaceGame) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Text(game.name).font(.title2.bold())
            HStack { workspaceButton(.play); workspaceButton(.reveal); workspaceButton(.edit) }
            if let issue = workspaceDisabledReason(.play) { Text(issue).font(.caption).foregroundStyle(.secondary) }
            LabeledContent("Source", value: game.source)
            if !game.executable.isEmpty { LabeledContent("Executable") { Text(game.executable).textSelection(.enabled) } }
            switch game {
            case .port(let port):
                LabeledContent("Environment", value: port.bottleLabel)
                LabeledContent("Program", value: port.programArch == "win32" ? "32-bit Windows" : "64-bit Windows")
                LabeledContent("Graphics requested", value: port.graphicsLabel)
                Button("Open Environment") {
                    workspaceEnvironmentID = port.bottle.isEmpty ? .main : .named(port.bottle)
                    workspaceDestination = .environments
                }
                if !port.arguments.isEmpty { LabeledContent("Arguments", value: port.arguments) }
                HStack { workspaceButton(.buildApp); workspaceButton(.checkFiles); workspaceButton(.diagnose) }
                if workspaceCheckingFiles { ProgressView("Checking game files…") }
                if let check = workspaceFileCheck { PortFileCheckView(port: port, check: check) }
                Text("File checks and a successful launch handoff do not verify gameplay or the loaded renderer.")
                    .font(.caption).foregroundStyle(.secondary)
            case .profile(let profile):
                LabeledContent("Launch method", value: profile.launchMethodLabel)
                LabeledContent("Shared environment", value: selectedBottle?.name ?? "Main environment")
                if !profile.args.isEmpty { LabeledContent("Arguments", value: profile.args) }
                Button("Open Saved Launcher Tools…") { selectedProfileID = profile.id; openWorkspaceUtility(.library) }
            }
        }.padding(18).background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func workspaceButton(_ command: WorkspaceCommand) -> some View {
        Button(command.title) { performWorkspaceCommand(command) }
            .disabled(workspaceDisabledReason(command) != nil)
            .help(workspaceDisabledReason(command) ?? command.title)
    }
    func newWorkspaceEnvironment() {
        guard workspaceDisabledReason(.refresh) == nil else { return }
        workspaceDestination = .environments
        newBottleName = ""; newBottleBackend = "recommended"; newBottleWindows = "win10"
        newBottleArch = "wow64"; newBottleRetina = false; showNewBottleSheet = true
    }
    func openWorkspaceUtility(_ section: DashboardSection) {
        dashboardSection = section
        workspaceUtilitySection = section
    }
    func performWorkspaceCommand(_ command: WorkspaceCommand) {
        guard workspaceDisabledReason(command) == nil else { return }
        switch command {
        case .install: installationWizard = InstallationWizardRequest()
        case .addExecutable: workspaceAddingExecutable = true
        case .refresh: refreshStatus()
        case .focusSearch:
            workspaceUtilitySection = nil
            workspaceDestination = .library
            workspaceSearchRequest += 1
        default:
            guard let game = workspaceSelectedGame else { return }
            switch game {
            case .port(let port):
                switch command {
                case .play:
                    guard ensureRosettaForWineLaunch() else { return }
                    runCommand(script: "port.command", arguments: ["launch", port.id], intent: .gameLaunch)
                case .edit: workspaceEditingPort = port
                case .buildApp: runCommand(script: "port.command", arguments: ["build", port.id])
                case .reveal: checkWorkspaceFiles(port, reveal: true)
                case .diagnose: runCommand(script: "repair.command", arguments: ["diagnose"], environment: portCommandEnvironment(port), intent: .diagnose)
                case .checkFiles:
                    checkWorkspaceFiles(port)
                default: break
                }
            case .profile(let profile):
                if command == .play { selectedProfileID = profile.id; launchProfile(profile) }
                if command == .reveal { revealInFinder(profile.fileURL) }
            }
        }
    }

    private func checkWorkspaceFiles(_ port: WinePort, reveal: Bool = false) {
        guard !workspaceCheckingFiles else { return }
        workspaceCheckingFiles = true
        DispatchQueue.global(qos: .userInitiated).async {
            let check = PortFileCheck.inspect(port)
            DispatchQueue.main.async {
                workspaceCheckingFiles = false
                guard workspaceSelectedGame == .port(port) else { return }
                workspaceFileCheck = check
                if reveal, let url = check.gameURL, FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }
}
