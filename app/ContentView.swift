import Foundation
import AppKit
import SwiftUI

// Dashboard shell: state, window chrome, and command lifecycle.
// Screens are ContentView extensions: Sidebar, Dashboard, Launch, Library, Tools, Bottles, and Runtime.

typealias CommandIntent = CommandFailureContext

struct ContentView: View {
    let fileManager = FileManager.default
    let repositoryRootURL = CosmosPaths.cosmosRoot()
    let consoleBottomID = "console-bottom"
    let steamLibraryCheckInterval: TimeInterval = 300

    @State var output = "Welcome to Cosmos. Install a Windows game or add an installed EXE from Library. Steam setup is optional."
    @AppStorage("cosmos.useRedesignedWorkspace") var useRedesignedWorkspace = true
    @State var workspaceRouter = WorkspaceRouter()
    var workspaceDestination: WorkspaceDestination {
        get { workspaceRouter.current }
        nonmutating set { workspaceUtilitySection = nil; workspaceRouter.visit(newValue) }
    }
    @State var workspaceSearchRequest = 0
    @AppStorage("cosmos.workspaceDestination") var storedWorkspaceDestination = "Library"
    @State var workspaceGameID: String?
    @State var workspaceAddingExecutable = false
    @State var workspaceEditingPort: WinePort?
    @State var workspaceUtilitySection: DashboardSection?
    @State var workspaceCheckingFiles = false
    @State var workspaceFileCheck: PortFileCheck?
    @State var installationWizard: InstallationWizardRequest?
    @State var profiles: [SavedProfile] = []
    @State var selectedProfileID: String?
    @State var profileSearchText = ""
    @State var librarySearchText = ""
    @AppStorage("cosmos.libraryViewMode") var libraryViewMode: GameLibraryViewMode = .grid
    @State var librarySourceFilter: GameLibrarySourceFilter = .all
    @State var librarySyncFollowUp: (() -> Void)?
    @State var cosmosInstalled = false
    @State var cosmosAppCount = 0
    @State var steamSettings = SteamSettings.defaults
    @State var graphicsSettings = GraphicsSettings.defaults
    @State var gptkValidation = GptkValidationResult.empty
    @State var spockD3D9Validation = SpockD3D9ValidationResult.empty
    @State var showLaunchSettings = false
    @State var showGameTools = false
    @State var activeOperationTitle = "Working…"
    @State var showAdvancedGraphics = false
    @State var showOpenGLFix = false
    @State var showStoreLaunch = false
    @State var showIncludedLaunchers = false
    @State var openGLStatus = OpenGLPatchStatus.empty
    @State var sojuStatus = SojuCommandStatus.empty
    @State var showD3D9Guidance = false
    @State var wineRuntime = WineRuntimeStore.load()
    @State var showDownloads = false
    @State var downloadResult: String?
    @State var downloadFailed = false
    @State var downloadedComponents: Set<CosmosDownload> = []
    @State var downloadOutput = ""
    @State var downloadInProgress = false
    @State var lastDownload: CosmosDownload?
    @State var afterDownloadsDismiss: (() -> Void)?
    @State var isRunning = false
    @State var showResetConfirmation = false
    @State var showUninstallConfirmation = false
    @State var showAdvancedSetupOptions = false
    @State var consoleExpanded = false
    @State var showSetupCompleteBanner = false
    @State var didCopyOutput = false
    @State var dashboardSection: DashboardSection = .launch
    /// Hide Bottles and Tools until the user opts in. Launch, Games, and Ports
    /// stay visible once Steam is ready.
    @AppStorage("cosmos.showAdvancedTabs") var showAdvancedTabs = false
    @State var commandBannerQueue = CommandBannerQueue()
    @EnvironmentObject var appState: CosmosAppState
    @State var outputWasTrimmed = false
    @State var storeImportRequest: StoreImportRequest?
    @State var pendingGameInstallations: [PendingGameInstallation] = []
    @State var pendingTerminalJobID: String?
    @State var updateAvailable = false
    @State var profilePreferences = ProfilePreferencesStore.load()
    @State var sidebarProfileFilter: SidebarProfileFilter = .all
    @State var lastSteamLibraryCheck: Date?
    @State var steamLibraryCheckInFlight = false
    @State var pendingNewSteamGames = 0
    @State var pendingRemovedSteamGames = 0
    @State var steamHealth = SteamHealthStatus.empty
    @State var steamHealthInFlight = false
    @State var pendingUnregisteredGogGames = 0
    @State var pendingLowConfidenceGogGames = 0
    @State var gogDetectionWarning: String?
    @State var pendingBrokenSteamInstalls = 0
    @State var lastWarnedBrokenSteamInstalls = 0
    @State var setupCompatAppID = ""
    @State var consoleHasNewOutput = false
    @State var pendingScrollToImport = false
    @State var pendingScrollToRepair = false
    @State var pendingScrollToGameProfiles = false
    @State var pendingScrollToGameLibrary = false
    @State var pendingScrollToCompatibility = false
    @State var pendingScrollToSteamSettings = false
    @State var pendingScrollToPerformanceGraphics = false
    @State var pendingScrollToBottles = false
    @State var showAddGameProfileSheet = false

    @State var gameProfiles: [GameProfile] = []
    @State var selectedGameProfileID: String?
    @State var dependencyRecipes: [RepairRecipe] = []
    @State var fixRecipes: [RepairRecipe] = []
    @State var cosmosReportStatus = "playable"
    @State var cosmosReportNote = ""
    @State var resolvedCompatBadge: ResolvedBadge?
    @State var curatedProfileFilter: CuratedProfileFilter = .all
    @State var pendingBlockedLaunch: SavedProfile?

    @State var bottles: [Bottle] = []
    @State var ports: [WinePort] = []
    @State var selectedBottleID: String?
    @State var showNewBottleSheet = false
    @State var showBottleResetConfirmation = false
    @State var showBottleDeleteConfirmation = false
    @State var newBottleName = ""
    @State var newBottleBackend = "recommended"
    @State var newBottleWindows = "win10"
    @State var newBottleRetina = false
    @State var newBottleArch = "wow64"
    @FocusState var newBottleNameFocused: Bool

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var selectedProfile: SavedProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    /// Saved profiles narrowed by the sidebar search field. Matches name,
    /// executable path, and Steam App ID so users with large libraries can
    /// jump straight to a title.
    var profileSearchQuery: String {
        profileSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearchingProfiles: Bool {
        !profileSearchQuery.isEmpty
    }

    var filteredProfiles: [SavedProfile] {
        guard isSearchingProfiles else { return profiles }
        return profiles.filter { profile in
            profile.name.localizedCaseInsensitiveContains(profileSearchQuery)
                || profile.path.localizedCaseInsensitiveContains(profileSearchQuery)
                || (profile.steamAppID?.localizedCaseInsensitiveContains(profileSearchQuery) ?? false)
        }
    }

    var favoriteProfiles: [SavedProfile] {
        let ids = Set(profilePreferences.favoriteIDs)
        return profiles
            .filter { ids.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var recentProfiles: [SavedProfile] {
        let favorites = Set(profilePreferences.favoriteIDs)
        return profilePreferences.recentIDs.compactMap { id in
            profiles.first { $0.id == id }
        }.filter { !favorites.contains($0.id) }
    }

    /// Saved profiles not already shown under Favorites or Recent.
    var pinnedProfileIDs: Set<String> {
        Set(profilePreferences.favoriteIDs + profilePreferences.recentIDs)
    }

    var catalogProfiles: [SavedProfile] {
        profiles
            .filter { !pinnedProfileIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var selectedBottle: Bottle? {
        bottles.first { $0.id == selectedBottleID }
    }

    var selectedGameProfile: GameProfile? {
        gameProfiles.first { $0.id == selectedGameProfileID }
    }

    var filteredGameProfiles: [GameProfile] {
        guard curatedProfileFilter != .all else { return gameProfiles }
        return gameProfiles.filter { curatedProfileFilter.matches($0) }
    }

    var curatedProfileFilterCaption: String {
        guard curatedProfileFilter != .all else {
            return "\(gameProfiles.count) profiles"
        }
        return "\(filteredGameProfiles.count) of \(gameProfiles.count) match “\(curatedProfileFilter.label)”"
    }

    /// Active Steam App ID from the launcher config or curated YAML profile selection.
    var activeSteamAppID: String? {
        if let id = selectedProfile?.steamAppID, !id.isEmpty { return id }
        if let id = selectedGameProfile?.steamAppID, !id.isEmpty { return id }
        return nil
    }

    /// GOG slug from a saved launcher config or curated GOG YAML profile.
    var activeGogSlug: String? {
        if let slug = selectedProfile?.gogSlug, !slug.isEmpty { return slug }
        if let slug = selectedGameProfile?.gogSlug, !slug.isEmpty { return slug }
        if selectedGameProfile?.store == "gog" { return selectedGameProfile?.id }
        return nil
    }

    var body: some View {
        presentationModifiers(
            commandNotificationHandlers(
                stateChangeHandlers(
                    lifecycleHandlers(
                        dashboardRoot
                            .tint(Color.cosmosPrimary)
                    )
                )
            )
        )
    }

    @ViewBuilder var dashboardRoot: some View {
        if useRedesignedWorkspace { workspaceRoot }
        else { previousDashboardRoot }
    }

    var previousDashboardRoot: some View {
        NavigationSplitView {
            sidebarContent
                .frame(minWidth: 270)
        } detail: {
            detailContent
        }
    }

    func lifecycleHandlers<Content: View>(_ content: Content) -> some View {
        content
        .task {
            appState.usesRedesignedWorkspace = useRedesignedWorkspace
            refreshStatus()
            resumeTerminalJobs()
            checkForUpdatesSilently()
            refreshSteamHealth()
            checkGogLibraryForUnregistered()
            if isSetupComplete {
                checkSteamLibraryForNewGames(autoSync: true)
            }
            appState.updateCommandAvailability(
                canAccept: !isRunning,
                canLaunchSelected: selectedProfileCanLaunch && wineRuntime.canStartWineLaunch,
                hasSelected: selectedProfile != nil
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosRefreshStatus)) { _ in
            refreshStatus(message: "Status refreshed.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosContinueSetup)) { _ in
            menuContinueSetup()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosOpenDownloads)) { _ in
            showDownloads = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosOpenSetupHelp)) { _ in
            openSetupHelp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosSelectSection)) { notification in
            guard let section = notification.object as? DashboardSection else { return }
            focusDashboardSection(section)
            if section == .bottles {
                pendingScrollToBottles = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosSyncSteamLibrary)) { _ in
            focusGameLibrary()
            syncAllLibrarySources(preferSteamOnly: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosSyncAllLibrary)) { _ in
            focusGameLibrary()
            syncAllLibrarySources()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosSyncGogLibrary)) { _ in
            focusGameLibrary()
            syncGogLibrary(build: false, announce: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosSyncGogLibraryBuild)) { _ in
            focusGameLibrary()
            syncGogLibrary(build: true, announce: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosBuildLaunchers)) { _ in
            focusGameLibrary()
            buildLaunchers()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosDetectSteamGames)) { _ in
            focusGameLibrary()
            runCommand(
                script: "detect_steam_games.command",
                arguments: ["--list"],
                environment: steamDetectionEnvironment()
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
            resumeTerminalJobs()
            refreshSteamHealth()
            checkGogLibraryForUnregistered()
            checkSteamLibraryForNewGames(autoSync: true)
        }
    }

    func stateChangeHandlers<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: useRedesignedWorkspace) { enabled in
            appState.usesRedesignedWorkspace = enabled
        }
        .onChange(of: isSetupComplete) { complete in
            DispatchQueue.main.async {
                appState.updateSetupComplete(complete)
                appState.updateSteamReady(isSteamReady)
            }
            if complete {
                if !showSetupCompleteBanner {
                    showSetupCompleteBanner = true
                }
                checkSteamLibraryForNewGames(autoSync: true)
            }
        }
        .onChange(of: selectedBottleID) { newID in
            reloadGraphicsSettings()
            if newID != nil, isSteamReady {
                dashboardSection = .bottles
            }
        }
        .onChange(of: selectedGameProfileID) { newID in
            if newID != nil, isSteamReady {
                dashboardSection = .library
            }
        }
        .onChange(of: selectedProfileID) { _ in
            refreshCompatBadge()
            DispatchQueue.main.async {
                appState.updateCommandAvailability(
                    canAccept: !isRunning,
                    canLaunchSelected: selectedProfileCanLaunch && wineRuntime.canStartWineLaunch,
                    hasSelected: selectedProfile != nil
                )
            }
        }
        .onChange(of: isRunning) { running in
            DispatchQueue.main.async {
                appState.updateCommandAvailability(
                    canAccept: !isRunning,
                    canLaunchSelected: selectedProfileCanLaunch && wineRuntime.canStartWineLaunch,
                    hasSelected: selectedProfile != nil
                )
            }
        }
        .onChange(of: profiles.count) { _ in
            DispatchQueue.main.async {
                appState.updateCommandAvailability(
                    canAccept: !isRunning,
                    canLaunchSelected: selectedProfileCanLaunch && wineRuntime.canStartWineLaunch,
                    hasSelected: selectedProfile != nil
                )
            }
        }
    }

    func commandNotificationHandlers<Content: View>(_ content: Content) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: .cosmosLaunchSelectedGame)) { _ in
            focusDashboardSection(.launch)
            launchSelectedProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosLaunchSteam)) { _ in
            focusDashboardSection(.launch)
            launchSteamFromDashboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosVerifySteam)) { _ in
            focusGameLibrary()
            verifySteamInstall()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosListGogGames)) { _ in
            openImportTools()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosOpenLogs)) { _ in
            consoleExpanded = true
            openLatestLogs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosRunDiagnose)) { _ in
            focusGameLibrary(scrollToRepair: true)
            runDiagnose()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosCheckForUpdates)) { _ in
            checkForUpdates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosOpenImportTools)) { _ in
            openImportTools()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosAddGameProfile)) { _ in
            openAddGameProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosShowSelectedInLibrary)) { _ in
            showSelectedProfileInLibrary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosShowSelectedOnLaunch)) { _ in
            showSelectedProfileOnLaunch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosApplyInstalledProfiles)) { _ in
            focusGameLibrary(scrollToProfiles: true)
            applyInstalledCuratedProfiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosOpenSteamSettings)) { _ in
            openSteamSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosOpenPerformanceGraphics)) { _ in
            openPerformanceGraphicsSettings(expandAdvanced: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosRevealSteamConf)) { _ in
            revealSteamConf()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosOpenBackendsGuide)) { _ in
            openRepositoryDoc(
                relativePath: "docs/BACKENDS.md",
                bundleName: "BACKENDS.md",
                fallbackMessage: "See docs/BACKENDS.md in the Cosmos repository."
            )
        }
    }

    func presentationModifiers<Content: View>(_ content: Content) -> some View {
        content
        .confirmationDialog(
            "Launch blocked title?",
            isPresented: Binding(
                get: { pendingBlockedLaunch != nil },
                set: { if !$0 { pendingBlockedLaunch = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Launch Anyway", role: .destructive) {
                if let profile = pendingBlockedLaunch {
                    pendingBlockedLaunch = nil
                    launchProfileUnchecked(profile)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingBlockedLaunch = nil
            }
        } message: {
            if let profile = pendingBlockedLaunch,
               let appid = profile.steamAppID,
               let yaml = GameProfileStore.find(steamAppID: appid) {
                Text(yaml.blockedLaunchMessage)
            } else if let profile = pendingBlockedLaunch {
                Text("\(profile.name) is marked blocked on macOS. Launch anyway?")
            }
        }
        .sheet(isPresented: $showDownloads, onDismiss: {
            let action = afterDownloadsDismiss
            afterDownloadsDismiss = nil
            action?()
        }) {
            CosmosDownloadsView(
                busy: isRunning || pendingTerminalJobID != nil,
                operationTitle: activeOperationTitle,
                result: downloadResult,
                failed: downloadFailed,
                output: downloadInProgress ? output : downloadOutput,
                wineInstalled: wineRuntime.wineInstalled,
                completed: downloadedComponents,
                activeDownload: downloadInProgress ? lastDownload : nil,
                onDownload: downloadComponent,
                onRetry: {
                    if let component = lastDownload { downloadComponent(component) }
                },
                onContinueSetup: {
                    afterDownloadsDismiss = { focusDashboardSection(.launch) }
                    showDownloads = false
                },
                onChooseSpock: {
                    afterDownloadsDismiss = {
                        openPerformanceGraphicsSettings(expandAdvanced: true)
                        browseForSpockD3D9Path()
                    }
                    showDownloads = false
                },
                onChooseGPTK: {
                    afterDownloadsDismiss = {
                        openPerformanceGraphicsSettings(expandAdvanced: true)
                        browseForGptkPath()
                    }
                    showDownloads = false
                }
            )
        }
        .sheet(item: $storeImportRequest) { request in
            StoreImportSheet(
                request: request,
                onCancel: { storeImportRequest = nil },
                onSubmit: { values in
                    submitStoreImport(request, values: values)
                    return nil
                }
            )
        }
        .sheet(isPresented: $showAddGameProfileSheet) {
            if let root = repositoryRootURL {
                AddGameProfileSheet(
                    repositoryRoot: root,
                    onCancel: { showAddGameProfileSheet = false },
                    onSaved: { profile in
                        showAddGameProfileSheet = false
                        gameProfiles = GameProfileStore.load()
                        selectedGameProfileID = profile.id
                        curatedProfileFilter = .mine
                        dashboardSection = .library
                        showBanner(kind: .success, message: "Saved game profile “\(profile.name)” to your personal library.")
                    }
                )
            }
        }
        .toolbar {
            dashboardToolbar
        }
    }

    @ToolbarContentBuilder
    var dashboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if isSteamReady, let bottle = selectedBottle {
                StatusChip(
                    label: "Bottle: \(bottle.name)",
                    systemImage: "cylinder.split.1x2.fill",
                    action: { dashboardSection = .bottles },
                    accessibilityHint: "Open Bottles tab. Control-click to clear selection."
                )
                .contextMenu {
                    Button("Open Bottles Tab") {
                        dashboardSection = .bottles
                    }
                    Button("Use Default Bottle") {
                        selectedBottleID = nil
                    }
                }
            } else if isSteamReady {
                StatusChip(
                    label: "Default bottle",
                    systemImage: "cylinder.split.1x2",
                    tint: .secondary,
                    action: { dashboardSection = .bottles },
                    accessibilityHint: "Open Bottles tab"
                )
            }
            if isRunning {
                StatusChip(
                    label: activeOperationTitle,
                    systemImage: "gearshape.arrow.triangle.2.circlepath",
                    tint: Color.cosmosBright,
                    accessibilityHint: "A command is running"
                )
            } else if steamHealthInFlight || steamLibraryCheckInFlight {
                StatusChip(
                    label: "Checking library…",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .secondary,
                    accessibilityHint: "Checking Steam library for changes"
                )
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showDownloads = true } label: {
                Label("Downloads", systemImage: "arrow.down.circle").labelStyle(.titleAndIcon)
            }
            .help("Download Wine and graphics components")

            if !isSetupComplete {
                Button {
                    performNextSetupStep()
                } label: {
                    Label(setupPrimaryTitle, systemImage: setupPrimarySystemImage)
                }
                .help(setupPrimarySubtitle)
                .accessibilityLabel(setupPrimaryTitle)
                .accessibilityHint(setupPrimarySubtitle)
                .disabled(isRunning)
            }
            Button {
                refreshStatus(message: "Status refreshed.")
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload installation status (⌘R)")
            .accessibilityLabel("Refresh status")
            .disabled(isRunning)
        }
        ToolbarItemGroup(placement: .automatic) {
            if isSteamReady {
                Menu {
                    Button("Steam & Wine…") {
                        openSteamSettings()
                    }
                    Button("Performance & Graphics…") {
                        openPerformanceGraphicsSettings()
                    }
                    Divider()
                    Button("Bottles…") {
                        focusBottlesSection()
                    }
                    Divider()
                    Button("Reveal steam.conf in Finder") {
                        revealSteamConf()
                    }
                    Button("Graphics Backends Guide…") {
                        NotificationCenter.default.post(name: .cosmosOpenBackendsGuide, object: nil)
                    }
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Steam prefix, graphics, and bottle settings (⌘,)")
                .accessibilityLabel("Settings")
                .disabled(isRunning)
            }
            Button {
                openSetupHelp()
            } label: {
                Label("Setup Help", systemImage: "questionmark.circle")
            }
            .help("Open the Steam setup guide")
            .accessibilityLabel("Setup help")
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
        .environmentObject(CosmosAppState.shared)
}
#endif
