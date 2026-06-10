import Foundation
import AppKit
import SwiftUI

struct ContentView: View {
    private let fileManager = FileManager.default
    private let repositoryRootURL = Self.findRepositoryRoot()
    private let profileDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cosmos/Profiles", isDirectory: true)
    private let cosmosAppsURL = URL(fileURLWithPath: "/Applications/Cosmos Apps", isDirectory: true)
    private let consoleBottomID = "console-bottom"

    @State private var output = "Welcome to Cosmos\n\nNew here? Follow the setup guide below — one button per step.\nFirst-time setup takes about 10–15 minutes (downloads + Steam installer).\n\nWhen finished, launch Steam, install a Windows game, then tap Build Game Launchers."
    @State private var profiles: [SavedProfile] = []
    @State private var selectedProfileID: String?
    @State private var profileSearchText = ""
    @State private var cosmosInstalled = false
    @State private var steamSettings = SteamSettings.defaults
    @State private var graphicsSettings = GraphicsSettings.defaults
    @State private var gptkValidation = GptkValidationResult.empty
    @State private var showAdvancedGraphics = false
    @State private var wineRuntime = WineRuntimeStore.load()
    @State private var isRunning = false
    @State private var showResetConfirmation = false
    @State private var showUninstallConfirmation = false
    @State private var showAdvancedSetupOptions = false
    @State private var consoleExpanded = false
    @State private var showSetupCompleteBanner = false
    @State private var didCopyOutput = false
    @State private var dashboardSection: DashboardSection = .launch
    @State private var commandBanner: CommandBanner?
    @State private var outputWasTrimmed = false
    @State private var storeImportRequest: StoreImportRequest?

    @State private var gameProfiles: [GameProfile] = []
    @State private var selectedGameProfileID: String?
    @State private var dependencyRecipes: [RepairRecipe] = []
    @State private var fixRecipes: [RepairRecipe] = []
    @State private var cosmosReportStatus = "playable"
    @State private var cosmosReportNote = ""
    @State private var resolvedCompatBadge: ResolvedBadge?
    @State private var curatedProfileFilter: CuratedProfileFilter = .all
    @State private var pendingBlockedLaunch: SavedProfile?

    @State private var bottles: [Bottle] = []
    @State private var selectedBottleID: String?
    @State private var showNewBottleSheet = false
    @State private var showBottleResetConfirmation = false
    @State private var showBottleDeleteConfirmation = false
    @State private var newBottleName = ""
    @State private var newBottleBackend = "recommended"
    @State private var newBottleWindows = "win10"
    @State private var newBottleRetina = false
    @FocusState private var newBottleNameFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedProfile: SavedProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    /// Saved profiles narrowed by the sidebar search field. Matches name,
    /// executable path, and Steam App ID so users with large libraries can
    /// jump straight to a title.
    private var filteredProfiles: [SavedProfile] {
        let query = profileSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return profiles }
        return profiles.filter { profile in
            profile.name.localizedCaseInsensitiveContains(query)
                || profile.path.localizedCaseInsensitiveContains(query)
                || (profile.steamAppID?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedBottle: Bottle? {
        bottles.first { $0.id == selectedBottleID }
    }

    private var selectedGameProfile: GameProfile? {
        gameProfiles.first { $0.id == selectedGameProfileID }
    }

    private var filteredGameProfiles: [GameProfile] {
        guard curatedProfileFilter != .all else { return gameProfiles }
        return gameProfiles.filter { curatedProfileFilter.matches($0) }
    }

    private var curatedProfileFilterCaption: String {
        guard curatedProfileFilter != .all else {
            return "\(gameProfiles.count) profiles"
        }
        return "\(filteredGameProfiles.count) of \(gameProfiles.count) match “\(curatedProfileFilter.label)”"
    }

    /// Active Steam App ID from the launcher config or curated YAML profile selection.
    private var activeSteamAppID: String? {
        if let id = selectedProfile?.steamAppID, !id.isEmpty { return id }
        if let id = selectedGameProfile?.steamAppID, !id.isEmpty { return id }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .frame(minWidth: 270)
        } detail: {
            detailContent
        }
        .tint(Color.cosmosPrimary)
        .task {
            refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosRefreshStatus)) { _ in
            refreshStatus(message: "Status refreshed.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosContinueSetup)) { _ in
            performNextSetupStep()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosOpenSetupHelp)) { _ in
            openSetupHelp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmosSelectSection)) { notification in
            if let section = notification.object as? DashboardSection, isSetupComplete {
                dashboardSection = section
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
        .onChange(of: isSetupComplete) { complete in
            if complete && !showSetupCompleteBanner {
                showSetupCompleteBanner = true
            }
        }
        .onChange(of: selectedBottleID) { _, newID in
            if newID != nil, isSetupComplete {
                dashboardSection = .bottles
            }
        }
        .onChange(of: selectedGameProfileID) { _, newID in
            if newID != nil, isSetupComplete {
                dashboardSection = .library
            }
        }
        .onChange(of: selectedProfileID) { _, newID in
            refreshCompatBadge()
            if newID != nil, isSetupComplete {
                dashboardSection = .launch
            }
        }
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
            }
        }
        .sheet(item: $storeImportRequest) { request in
            StoreImportSheet(
                request: request,
                onCancel: { storeImportRequest = nil },
                onSubmit: { values in
                    submitStoreImport(request, values: values)
                    storeImportRequest = nil
                }
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if isSetupComplete, let bottle = selectedBottle {
                    StatusChip(
                        label: "Bottle: \(bottle.name)",
                        systemImage: "cylinder.split.1x2.fill"
                    )
                } else if isSetupComplete {
                    StatusChip(
                        label: "Default bottle",
                        systemImage: "cylinder.split.1x2",
                        tint: .secondary
                    )
                }
                if isRunning {
                    StatusChip(
                        label: "Running…",
                        systemImage: "gearshape.arrow.triangle.2.circlepath",
                        tint: Color.cosmosBright
                    )
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if !isSetupComplete {
                    Button {
                        performNextSetupStep()
                    } label: {
                        Label(setupPrimaryTitle, systemImage: setupPrimarySystemImage)
                    }
                    .help(setupPrimarySubtitle)
                    .disabled(isRunning)
                }
                Button {
                    refreshStatus(message: "Status refreshed.")
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload installation status (⌘R)")
                .disabled(isRunning)
            }
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    openSetupHelp()
                } label: {
                    Label("Setup Help", systemImage: "questionmark.circle")
                }
                .help("Open the Steam setup guide")
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(alignment: .center, spacing: 0) {
            // Logo header
            VStack(spacing: 6) {
                CosmosLogo(markSize: 64)
                Text("Apple Silicon Launcher")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)

            Divider()

            // Status summary
            statusSummary
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Divider()
                .padding(.top, 14)

            // Search field — only worth showing once there are profiles to filter.
            if !profiles.isEmpty {
                profileSearchField
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            // Profile list
            List(selection: $selectedProfileID) {
                Section(profileSectionTitle) {
                    if profiles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("No profiles yet", systemImage: "tray")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                            Text(isSetupComplete ? "Run Detect Games after installing Steam to discover titles." : "Complete setup above, then build launchers to see games here.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("No saved game profiles. Run Detect Games after installing Steam.")
                    } else if filteredProfiles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("No matches", systemImage: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                            Text("No saved game matches “\(profileSearchText.trimmingCharacters(in: .whitespacesAndNewlines))”.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("No saved games match the search.")
                    } else {
                        ForEach(filteredProfiles) { profile in
                            profileRow(profile)
                                .tag(profile.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .disabled(isRunning)
        }
    }

    private var profileSectionTitle: String {
        let query = profileSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if profiles.isEmpty || query.isEmpty {
            return "Saved Profiles"
        }
        return "Saved Profiles (\(filteredProfiles.count) of \(profiles.count))"
    }

    private var profileSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Search games", text: $profileSearchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .accessibilityLabel("Search saved games")
            if !profileSearchText.isEmpty {
                Button {
                    profileSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .disabled(isRunning)
    }

    private func profileRow(_ profile: SavedProfile) -> some View {
        let badge = sidebarCompatBadge(for: profile)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)
                if let badge {
                    CosmosCompatBadge(status: badge.status, compact: true)
                }
                if profile.path.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("No executable path — edit the profile config")
                }
            }
            Text(profile.args.isEmpty ? profile.path : profile.args)
                .font(.caption)
                .foregroundStyle(profile.path.isEmpty ? .tertiary : .secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sidebarProfileAccessibilityLabel(profile, badge: badge))
        .accessibilityAddTraits(profile.id == selectedProfileID ? .isSelected : [])
        .contextMenu {
            Button {
                selectedProfileID = profile.id
                launchProfile(profile)
            } label: {
                Label("Launch", systemImage: "play.fill")
            }
            .disabled(profile.path.isEmpty || isRunning)

            Button {
                revealInFinder(profile.fileURL)
            } label: {
                Label("Reveal Config in Finder", systemImage: "folder")
            }

            if !profile.path.isEmpty {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(profile.path, forType: .string)
                } label: {
                    Label("Copy Executable Path", systemImage: "doc.on.doc")
                }
            }
        }
    }

    // MARK: - Detail

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CosmosSpacing.section) {
                if showSetupCompleteBanner && isSetupComplete {
                    setupCompleteBanner
                }
                if let commandBanner {
                    CommandBannerView(banner: commandBanner) {
                        self.commandBanner = nil
                    }
                }
                heroSection
                if isSetupComplete {
                    dashboardSectionPicker
                }
                setupAssistantSection
                if isSetupComplete {
                    dashboardSectionContent
                } else {
                    setupLaunchHintSection
                    if showAdvancedSetupOptions {
                        steamWineSettingsSection
                        managementGrid
                    } else {
                        newUserMaintenanceSection
                    }
                }
                if (!isSetupComplete || dashboardSection == .launch), let selectedProfile {
                    selectedProfileSection(selectedProfile)
                }
                consoleSection
            }
            .padding(CosmosSpacing.contentPadding)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Segmented navigation for the post-setup dashboard — one focus area at a time.
    private var dashboardSectionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Section", selection: $dashboardSection) {
                ForEach(DashboardSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Dashboard section")

            HStack(spacing: 8) {
                Text(dashboardSection.subtitle)
                Text("·")
                Text("⌘1–4 to switch")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var dashboardSectionContent: some View {
        switch dashboardSection {
        case .launch:
            wineRuntimeSection
            launchSection
            steamWineSettingsSection
            performanceGraphicsSection
        case .library:
            curatedProfilesSection
            compatibilitySection
            repairSection
        case .tools:
            managementGrid
            storeExpansionSection
        case .bottles:
            bottlesSection
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heroTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.cosmosPrimary)
            Text(heroSubtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var heroTitle: String {
        if let selectedProfile { return selectedProfile.name }
        if let selectedBottle { return selectedBottle.name }
        if !isSetupComplete { return "Welcome to Cosmos" }
        return "Launcher Dashboard"
    }

    private var isSetupComplete: Bool {
        cosmosInstalled
            && steamSettings.isPrefixInitialized
            && steamSettings.isSteamInstalled
            && !profiles.isEmpty
    }

    private var setupProgress: Double {
        var completed = 0.0
        if cosmosInstalled { completed += 1 }
        if steamSettings.isPrefixInitialized { completed += 1 }
        if steamSettings.isSteamInstalled { completed += 1 }
        if !profiles.isEmpty { completed += 1 }
        return completed / 4.0
    }

    private var setupStepNumber: Int {
        if !cosmosInstalled { return 1 }
        if !steamSettings.isPrefixInitialized { return 2 }
        if !steamSettings.isSteamInstalled { return 3 }
        if profiles.isEmpty { return 4 }
        return 4
    }

    private var setupPrimaryTitle: String {
        if !cosmosInstalled { return "Install Cosmos" }
        if !steamSettings.isPrefixInitialized { return "Prepare Steam Bottle" }
        if !steamSettings.isSteamInstalled { return "Install Steam" }
        if profiles.isEmpty { return "Build Game Launchers" }
        return "Refresh Status"
    }

    private var setupPrimarySubtitle: String {
        if !cosmosInstalled {
            return "Installs launchers into /Applications/Cosmos Apps · opens Terminal"
        }
        if !steamSettings.isPrefixInitialized {
            return "Downloads Wine, creates the prefix, and installs Steam"
        }
        if !steamSettings.isSteamInstalled {
            return steamSettings.silentInstallEnabled
                ? "Installs Steam automatically (wizard fallback if needed)"
                : "Opens the graphical Steam installer wizard in Terminal"
        }
        if profiles.isEmpty {
            return "Detect installed games and create Dock-friendly .app launchers"
        }
        return "Update the checklist and sidebar"
    }

    private var setupPrimarySystemImage: String {
        if !cosmosInstalled { return "arrow.down.circle.fill" }
        if !steamSettings.isPrefixInitialized { return "externaldrive.fill.badge.checkmark" }
        if !steamSettings.isSteamInstalled { return "shippingbox.fill" }
        if profiles.isEmpty { return "square.grid.2x2.fill" }
        return "arrow.clockwise"
    }

    private var heroSubtitle: String {
        if !isSetupComplete, selectedProfile == nil, selectedBottle == nil {
            return "Follow the setup guide below — one button per step. First-time setup takes about 10–15 minutes."
        }
        if let selectedProfile {
            return selectedProfileHasExecutablePath
                ? "Ready to launch this saved profile through the Wine-based shell flow."
                : "This profile has no executable path — edit its config file or pick another profile."
        }
        if let selectedBottle {
            return "Bottle selected — adjust backend and launch Steam from the controls below."
        }
        if !cosmosInstalled {
            return "Install Cosmos first, then prepare the Steam bottle and detect games."
        }
        if !steamSettings.isPrefixInitialized {
            return "Prepare the Steam bottle to download Wine and create the prefix, then install Steam."
        }
        if !steamSettings.isSteamInstalled {
            return steamSettings.silentInstallEnabled
                ? "Run Install Steam to finish the unattended install, then detect games."
                : "Run Install Steam to complete the installer wizard, then detect games."
        }
        if profiles.isEmpty {
            return "Steam is ready — run Detect Games to populate saved profiles."
        }
        return "Manage Cosmos, launch Steam, and jump into saved game profiles from one place."
    }

    private var setupAssistantSection: some View {
        Group {
            if isSetupComplete {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("First-time setup")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.cosmosPrimary)
                        Text("About 10–15 minutes the first time. Each step opens Terminal when needed — complete any prompts there, then press Refresh here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Step \(setupStepNumber) of 4")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.cosmosPrimary)
                            Spacer()
                            Text("\(Int(setupProgress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: setupProgress)
                            .tint(Color.cosmosPrimary)
                    }

                    prominentButton(
                        title: setupPrimaryTitle,
                        subtitle: setupPrimarySubtitle,
                        systemImage: setupPrimarySystemImage,
                        help: "Run the next recommended setup step"
                    ) {
                        performNextSetupStep()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if wineRuntime.needsRosetta {
                            setupStep(
                                done: wineRuntime.rosettaReady,
                                title: "Install Rosetta 2",
                                detail: wineRuntime.rosettaReady
                                    ? "x86_64 Wine can run on Apple Silicon"
                                    : "Required before Wine can launch on Apple Silicon"
                            )
                        }
                        setupStep(
                            done: cosmosInstalled,
                            title: "Install Cosmos",
                            detail: cosmosInstalled
                                ? "Launchers are in /Applications/Cosmos Apps"
                                : "Wine runtime and Spotlight-friendly launchers"
                        )
                        setupStep(
                            done: steamSettings.isPrefixInitialized,
                            title: "Prepare Steam bottle",
                            detail: steamSettings.isPrefixInitialized
                                ? "Prefix at \(steamSettings.prefixURL.lastPathComponent)"
                                : "Wine + graphics backend (DXMT by default)"
                        )
                        setupStep(
                            done: steamSettings.isSteamInstalled,
                            title: "Install Steam",
                            detail: steamSettings.isSteamInstalled
                                ? "Steam is in the Wine prefix"
                                : (steamSettings.silentInstallEnabled
                                    ? "Unattended install (wizard fallback if needed)"
                                    : "Complete the graphical Steam installer wizard")
                        )
                        setupStep(
                            done: !profiles.isEmpty,
                            title: "Build game launchers",
                            detail: profiles.isEmpty
                                ? "After you install a Windows game in Steam"
                                : "\(profiles.count) profile\(profiles.count == 1 ? "" : "s") ready"
                        )
                    }

                    HStack(spacing: 12) {
                        Button {
                            runInTerminal(script: "setup.command")
                        } label: {
                            Label("All-in-one setup", systemImage: "terminal.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning)

                        Button {
                            openSetupHelp()
                        } label: {
                            Label("Help", systemImage: "questionmark.circle")
                        }
                        .buttonStyle(.bordered)

                        if steamSettings.isSteamInstalled {
                            Button {
                                openMultiplayerHelp()
                            } label: {
                                Label("Multiplayer", systemImage: "person.2.fill")
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {
                            runCommand(script: "run.command", arguments: ["--logs"])
                        } label: {
                            Label("Logs", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning)
                    }
                    .font(.subheadline)
                }
                .cosmosCard(prominent: true)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("First-time setup guide, step \(setupStepNumber) of 4")
            }
        }
    }

    private func setupStep(done: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
                .font(.body.weight(.semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(done ? "done" : "not done"). \(detail)")
    }

    private var setupLaunchHintSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("After setup", systemImage: "play.circle")
            Text(steamSettings.isSteamInstalled
                ? "Launch Steam to sign in and download a Windows game, then continue with Build Game Launchers above."
                : "Quick Launch unlocks once Steam is installed. Use the setup guide above for the next step.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if steamSettings.isSteamInstalled {
                prominentButton(
                    title: "Launch Steam",
                    subtitle: "Sign in and install a Windows game",
                    systemImage: "play.fill",
                    help: "Open Steam in the Wine prefix"
                ) {
                    runCommand(script: "run.command", arguments: ["--steam"])
                }
            }
        }
    }

    private var newUserMaintenanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $showAdvancedSetupOptions) {
                managementGrid
            } label: {
                Label("More options", systemImage: "ellipsis.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.cosmosPrimary)
            }
            Text("Optional: reset bottle, open logs, or run individual tools. Recommended defaults work for most games.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func performNextSetupStep() {
        consoleExpanded = true
        if wineRuntime.needsRosetta && !wineRuntime.rosettaReady {
            runInTerminal(script: "run.command", arguments: ["--install-rosetta"])
            return
        }
        if !cosmosInstalled {
            runInTerminal(script: "install_cosmos.command")
            return
        }
        if !steamSettings.isPrefixInitialized {
            runInTerminal(script: "run.command", arguments: ["--setup-steam"])
            return
        }
        if !steamSettings.isSteamInstalled {
            runInTerminal(script: "run.command", arguments: ["--install-steam"])
            return
        }
        if profiles.isEmpty {
            runInTerminal(script: "detect_steam_games.command", arguments: ["--install"])
            return
        }
        refreshStatus(message: "Setup looks complete.")
    }

    // MARK: - Quick launch

    @ViewBuilder
    private var quickLaunchButtons: some View {
        prominentButton(
            title: "Launch Steam",
            subtitle: "Open Steam in the bottle",
            systemImage: "play.fill",
            help: "Start Steam in the default Wine prefix"
        ) {
            runCommand(script: "run.command", arguments: ["--steam"])
        }

        prominentButton(
            title: "Launch Profile",
            subtitle: selectedProfileLaunchSubtitle,
            systemImage: "gamecontroller.fill",
            disabled: !selectedProfileHasExecutablePath,
            help: selectedProfileHasExecutablePath
                ? "Launch the selected profile's game executable"
                : "Select a profile with an executable path in the sidebar"
        ) {
            guard let selectedProfile else { return }
            launchProfile(selectedProfile)
        }
    }

    /// Launch a saved profile's game executable through the Wine shell flow.
    /// Shared by the Quick Launch button and the sidebar context menu.
    private func launchProfile(_ profile: SavedProfile) {
        guard !profile.path.isEmpty else { return }
        if let appid = profile.steamAppID,
           let yaml = GameProfileStore.find(steamAppID: appid),
           yaml.isBlocked {
            pendingBlockedLaunch = profile
            return
        }
        launchProfileUnchecked(profile)
    }

    private func launchProfileUnchecked(_ profile: SavedProfile) {
        guard !profile.path.isEmpty else { return }
        runCommand(
            script: "run.command",
            arguments: ["--game", profile.path] + ShellArgumentParser.parse(profile.args)
        )
    }

    private func sidebarCompatBadge(for profile: SavedProfile) -> ResolvedBadge? {
        guard let appid = profile.steamAppID, !appid.isEmpty else { return nil }
        let resolved = CosmosBadgeStore.resolve(
            steamAppID: appid,
            curated: GameProfileStore.find(steamAppID: appid)
        )
        return resolved.isKnown ? resolved : nil
    }

    private func sidebarProfileAccessibilityLabel(_ profile: SavedProfile, badge: ResolvedBadge?) -> String {
        var parts = [profile.name]
        if let badge {
            parts.append("compatibility \(badge.status)")
        }
        parts.append(profile.path.isEmpty ? "No executable path set" : profile.path)
        return parts.joined(separator: ". ")
    }

    /// Reveal a file in Finder, selecting it in its enclosing folder.
    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private var wineRuntimeSection: some View {
        Group {
            if wineRuntime.needsRosetta && !wineRuntime.rosettaReady {
                runtimeNoticeBanner(
                    tint: .orange,
                    systemImage: "cpu",
                    title: "Rosetta 2 required",
                    message: "Cosmos downloads x86_64 Wine builds from Gcenx. Apple Silicon Macs need Rosetta 2 before Wine can run. Install Rosetta, then continue setup."
                )
            } else if !wineRuntime.wineInstalled {
                runtimeNoticeBanner(
                    tint: Color.cosmosPrimary,
                    systemImage: "wineglass",
                    title: "Wine not downloaded yet",
                    message: "Run Prepare Steam bottle to download Wine \(wineRuntime.wineVersion). \(wineRuntime.translationNote)"
                )
            }
        }
    }

    private func runtimeNoticeBanner(
        tint: Color,
        systemImage: String,
        title: String,
        message: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(tint.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var launchSection: some View {
        CosmosSection(title: "Quick Launch", systemImage: "bolt.fill", inCard: true) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CosmosSpacing.sectionInner + 2) {
                    quickLaunchButtons
                }
                VStack(spacing: CosmosSpacing.sectionInner + 2) {
                    quickLaunchButtons
                }
            }
        }
    }

    // MARK: - Steam Wine settings

    private var steamWineSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Steam Wine Settings", systemImage: "gearshape.2.fill")

            Text("These apply to the default Steam prefix on the next launch. Use Bottles below for extra isolated prefixes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Graphics backend")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                            .textCase(.uppercase)
                        Picker("Backend", selection: steamBackendBinding) {
                            ForEach(SteamSettingsStore.backendOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 220, alignment: .leading)
                        .disabled(isRunning)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Windows version")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                            .textCase(.uppercase)
                        Picker("Windows", selection: steamWindowsBinding) {
                            Text("Wine default").tag("")
                            ForEach(SteamSettingsStore.windowsOptions.filter { !$0.isEmpty }, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 200, alignment: .leading)
                        .disabled(isRunning)
                    }
                }

                Toggle(isOn: steamRetinaBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Retina mode")
                            .font(.subheadline.weight(.medium))
                        Text("Higher UI resolution in Wine — can help sharpness or hurt performance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isRunning)

                Toggle(isOn: steamSilentBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unattended Steam install")
                            .font(.subheadline.weight(.medium))
                        Text("Installs Steam automatically without the wizard. Falls back to the wizard if the silent install can't finish.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isRunning)

                Toggle(isOn: steamDetachBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detach Steam from Terminal")
                            .font(.subheadline.weight(.medium))
                        Text("When on, you can close Terminal after launch without quitting Steam.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isRunning)

                Divider()

                HStack(alignment: .top, spacing: 24) {
                    detailRow(title: "Wine", value: wineRuntime.wineInstalled
                        ? (wineRuntime.wineReportedVersion ?? wineRuntime.wineVersion)
                        : "Not downloaded (v\(wineRuntime.wineVersion))")
                    detailRow(title: "Rosetta", value: wineRuntime.rosettaLabel)
                }
                HStack(alignment: .top, spacing: 24) {
                    detailRow(title: "Prefix status", value: steamSettings.statusText)
                    detailRow(title: "CPU layer", value: wineRuntime.chipArchitecture)
                }
                Text(wineRuntime.translationNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                detailRow(title: "Prefix path", value: steamSettings.prefixURL.path)
                if wineRuntime.wineInstalled {
                    detailRow(title: "Wine binary", value: wineRuntime.wineBinaryPath)
                }
            }
            .cosmosCard()
        }
    }

    // MARK: - Performance & graphics (Phase E)

    private var performanceGraphicsSection: some View {
        CosmosSection(
            title: "Performance & Graphics",
            systemImage: "speedometer",
            caption: "Thread sync, D3D12 (GPTK), and advanced DXMT / MoltenVK tuning for the default Steam bottle."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Thread sync")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                        .textCase(.uppercase)
                    Picker("Thread sync", selection: syncModeBinding) {
                        ForEach(GraphicsSettings.syncModeOptions, id: \.self) { mode in
                            Text(mode).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRunning)
                    Text(graphicsSettings.syncModeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                gptkSetupCard

                DisclosureGroup(isExpanded: $showAdvancedGraphics) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DXMT channel")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                                .textCase(.uppercase)
                            Picker("DXMT channel", selection: dxmtChannelBinding) {
                                Text("Pinned (0.80)").tag("stable")
                                Text("Latest (LGPL)").tag("latest")
                            }
                            .pickerStyle(.segmented)
                            .disabled(isRunning)
                            Text(graphicsSettings.dxmtChannel == "latest"
                                ? "Tracks the newest DXMT from the runtime manifest (LGPL). Source offer: runtime/DXMT-SOURCE-OFFER.txt."
                                : "Uses the pinned runtime manifest (DXMT 0.80, MIT).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Toggle(isOn: metalFXBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("MetalFX upscaling (DXMT)")
                                    .font(.subheadline.weight(.medium))
                                Text("Appends d3d11.metalFxUpscale=1 to DXMT_CONFIG. Experimental — game-dependent.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isRunning)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("MoltenVK preset (DXVK path)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                                .textCase(.uppercase)
                            Picker("MoltenVK preset", selection: moltenvkPresetBinding) {
                                Text("Default").tag("default")
                                Text("Performance").tag("performance")
                                Text("Compatibility").tag("compatibility")
                            }
                            .pickerStyle(.segmented)
                            .disabled(isRunning)
                            Text("Sets MVK_CONFIG_* env vars when using the experimental DXVK backend.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Advanced graphics options")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.cosmosPrimary)
                }
            }
            .cosmosCard()
        }
    }

    private var gptkSetupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("D3D12 — Game Porting Toolkit")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if gptkValidation.valid {
                    Label("Valid", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if graphicsSettings.gptkConfigured {
                    Label("Invalid", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Text("Apple's GPTK is not bundled. Download from developer.apple.com, then point Cosmos at the install folder for D3D12 titles (Cyberpunk, Elden Ring, etc.).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("GPTK_PATH", text: gptkPathBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .disabled(isRunning)
                Button("Browse…") { browseForGptkPath() }
                    .disabled(isRunning)
            }

            if !gptkValidation.errorMessage.isEmpty, !gptkValidation.valid {
                Text(gptkValidation.errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if gptkValidation.valid {
                Text("Found \(gptkValidation.dllCount) DLL(s) in \(gptkValidation.dllDirectory)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Button {
                    validateGptkPath()
                } label: {
                    Label("Validate", systemImage: "checkmark.shield")
                }
                .buttonStyle(.bordered)
                .disabled(isRunning || !graphicsSettings.gptkConfigured)

                Button {
                    saveGptkPathAndTest()
                } label: {
                    Label("Save & Test Steam", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.cosmosPrimary)
                .disabled(isRunning || !gptkValidation.valid)

                Button {
                    openRepositoryDoc(
                        relativePath: "docs/BACKENDS.md",
                        bundleName: "BACKENDS.md",
                        fallbackMessage: "See docs/BACKENDS.md in the Cosmos repository."
                    )
                } label: {
                    Label("Guide", systemImage: "book")
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline)
        }
    }

    private var syncModeBinding: Binding<String> {
        Binding(
            get: { graphicsSettings.syncMode },
            set: { applyGraphicsSetting(key: "COSMOS_SYNC_MODE", value: $0) }
        )
    }

    private var dxmtChannelBinding: Binding<String> {
        Binding(
            get: { graphicsSettings.dxmtChannel },
            set: { applyGraphicsSetting(key: "COSMOS_DXMT_CHANNEL", value: $0) }
        )
    }

    private var moltenvkPresetBinding: Binding<String> {
        Binding(
            get: { graphicsSettings.moltenvkPreset },
            set: { applyGraphicsSetting(key: "COSMOS_MVK_PRESET", value: $0) }
        )
    }

    private var metalFXBinding: Binding<Bool> {
        Binding(
            get: { graphicsSettings.metalFXEnabled },
            set: { applyGraphicsSetting(key: "COSMOS_METALFX", value: $0 ? "1" : "0") }
        )
    }

    private var gptkPathBinding: Binding<String> {
        Binding(
            get: { graphicsSettings.gptkPath },
            set: { graphicsSettings.gptkPath = $0 }
        )
    }

    private func applyGraphicsSetting(key: String, value: String) {
        do {
            try SteamSettingsStore.set(key: key, value: value)
            reloadGraphicsSettings()
            let message = "Saved \(key). Changes apply on the next launch."
            output = message + "\n\n" + output
            showBanner(kind: .success, message: message)
        } catch {
            let message = "Could not save \(key): \(error.localizedDescription)"
            output = message + "\n\n" + output
            showBanner(kind: .failure, message: message)
        }
    }

    private func reloadGraphicsSettings() {
        graphicsSettings = GraphicsSettingsStore.loadSteam()
        if graphicsSettings.gptkConfigured {
            gptkValidation = GraphicsSettingsStore.validateGptkPath(
                graphicsSettings.gptkPath,
                repositoryRoot: repositoryRootURL
            )
        } else {
            gptkValidation = .empty
        }
    }

    private func browseForGptkPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your Game Porting Toolkit install folder"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        graphicsSettings.gptkPath = url.path
        validateGptkPath()
    }

    private func validateGptkPath() {
        let path = graphicsSettings.gptkPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            gptkValidation = .empty
            return
        }
        gptkValidation = GraphicsSettingsStore.validateGptkPath(path, repositoryRoot: repositoryRootURL)
    }

    private func saveGptkPathAndTest() {
        let path = graphicsSettings.gptkPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        applyGraphicsSetting(key: "GPTK_PATH", value: path)
        if steamSettings.backend == "dxmt" {
            applySteamSetting(key: "COSMOS_BACKEND", value: "d3dmetal")
        }
        runCommand(
            script: "run.command",
            arguments: ["--steam"],
            environment: ["GPTK_PATH": path, "COSMOS_BACKEND": "d3dmetal"]
        )
    }

    private var steamBackendBinding: Binding<String> {
        Binding(
            get: { steamSettings.backend },
            set: { applySteamSetting(key: "COSMOS_BACKEND", value: $0) }
        )
    }

    private var steamWindowsBinding: Binding<String> {
        Binding(
            get: { steamSettings.windowsVersion },
            set: { applySteamSetting(key: "WINDOWS_VERSION", value: $0) }
        )
    }

    private var steamRetinaBinding: Binding<Bool> {
        Binding(
            get: { steamSettings.retinaEnabled },
            set: { applySteamSetting(key: "WINE_RETINA_MODE", value: $0 ? "1" : "0") }
        )
    }

    private var steamDetachBinding: Binding<Bool> {
        Binding(
            get: { steamSettings.detachEnabled },
            set: { applySteamSetting(key: "COSMOS_DETACH", value: $0 ? "1" : "0") }
        )
    }

    private var steamSilentBinding: Binding<Bool> {
        Binding(
            get: { steamSettings.silentInstallEnabled },
            set: { applySteamSetting(key: "COSMOS_STEAM_SILENT", value: $0 ? "1" : "0") }
        )
    }

    private func applySteamSetting(key: String, value: String) {
        do {
            try SteamSettingsStore.set(key: key, value: value)
            steamSettings = SteamSettingsStore.load()
            let message = "Saved \(key). Changes apply on the next Steam or game launch."
            output = message + "\n\n" + output
            showBanner(kind: .success, message: message)
        } catch {
            let message = "Could not save \(key): \(error.localizedDescription)"
            output = message + "\n\n" + output
            showBanner(kind: .failure, message: message)
        }
    }

    // MARK: - Management grid

    private var managementGrid: some View {
        CosmosSection(title: "Setup & Maintenance", systemImage: "wrench.and.screwdriver.fill") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: CosmosSpacing.gridColumnMin), spacing: CosmosSpacing.gridGap)],
                spacing: CosmosSpacing.gridGap
            ) {
                if wineRuntime.needsRosetta && !wineRuntime.rosettaReady {
                    secondaryButton(
                        title: "Install Rosetta 2",
                        subtitle: "Required on Apple Silicon",
                        systemImage: "cpu",
                        help: "Install Rosetta 2 so x86_64 Wine can run (may ask for your password)"
                    ) {
                        runInTerminal(script: "run.command", arguments: ["--install-rosetta"])
                    }
                }

                secondaryButton(title: "Install Cosmos", subtitle: "Wine & deps · Terminal", systemImage: "arrow.down.circle.fill", help: "Opens Terminal to install Wine and dependencies (may ask for your password)") {
                    runInTerminal(script: "install_cosmos.command")
                }

                secondaryButton(title: "Prepare Bottle", subtitle: "Wine prefix & Steam · Terminal", systemImage: "externaldrive.fill.badge.checkmark", help: "Opens Terminal to download Wine, create the prefix, install Steam, and configure the graphics backend without launching Steam") {
                    runInTerminal(script: "run.command", arguments: ["--setup-steam"])
                }

                secondaryButton(title: "Detect Games", subtitle: "List Steam games", systemImage: "magnifyingglass", help: "Scan the Steam library and list installable titles in the output pane") {
                    runCommand(script: "detect_steam_games.command", arguments: ["--list"], environment: bottleEnvironment())
                }

                secondaryButton(title: "Verify Detection", subtitle: "Check install folders", systemImage: "checkmark.shield.fill", help: "List games and verify each installdir exists on disk") {
                    runCommand(script: "detect_steam_games.command", arguments: ["--verify"], environment: bottleEnvironment())
                }

                secondaryButton(title: "Build Launchers", subtitle: "Detect → build apps · Terminal", systemImage: "square.grid.2x2.fill", help: "Opens Terminal to detect games and install Spotlight launchers into Cosmos Apps") {
                    runInTerminal(script: "detect_steam_games.command", arguments: ["--install"])
                }

                secondaryButton(title: "Profiles Folder", subtitle: "Open in Finder", systemImage: "folder.fill", help: "Reveal saved game profiles in Finder") {
                    runCommand(script: "run.command", arguments: ["--profiles"])
                }

                secondaryButton(title: "Open Logs", subtitle: "Latest launch log", systemImage: "doc.text.magnifyingglass", help: "Open the most recent launch log for troubleshooting") {
                    runCommand(script: "run.command", arguments: ["--logs"])
                }

                secondaryButton(title: "Refresh", subtitle: "Reload status", systemImage: "arrow.clockwise", help: "Reload profiles, bottles, and installation status") {
                    refreshStatus(message: "Status refreshed.")
                }

                secondaryButton(title: "Reset Bottle", subtitle: "Delete prefix", systemImage: "arrow.counterclockwise", destructive: true, help: "Delete the default Wine prefix (Steam and games inside it)") {
                    showResetConfirmation = true
                }

                secondaryButton(title: "Uninstall", subtitle: "Remove everything · Terminal", systemImage: "trash.fill", destructive: true, help: "Opens Terminal to remove Cosmos Apps, the prefix, and downloaded runtimes") {
                    showUninstallConfirmation = true
                }
            }
        }
        .confirmationDialog("Reset the Steam bottle?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset Bottle", role: .destructive) {
                runCommand(script: "run.command", arguments: ["--reset-bottle", "--force"])
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the Wine prefix and everything installed inside it (including Steam and games). Wine and DXMT downloads are kept.")
        }
        .confirmationDialog("Uninstall Cosmos?", isPresented: $showUninstallConfirmation, titleVisibility: .visible) {
            Button("Uninstall in Terminal", role: .destructive) {
                runInTerminal(script: "uninstall.command")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Opens Terminal to remove the installed Cosmos apps, the Wine prefix, and the downloaded Wine and DXMT runtimes. The uninstaller asks before deleting each item.")
        }
    }

    // MARK: - Curated profiles (YAML)

    private var curatedProfilesSection: some View {
        CosmosSection(
            title: "Curated Game Profiles",
            systemImage: "doc.text.fill",
            caption: "Known-good YAML recipes (roadmap 0.4). Apply writes overrides and runs winetricks/fixes."
        ) {
            if gameProfiles.isEmpty {
                Text("No profiles found in profiles/. Rebuild the app bundle or run from the repository checkout.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CuratedProfileFilter.allCases) { filter in
                                curatedProfileFilterChip(filter)
                            }
                        }
                    }
                    Text(curatedProfileFilterCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if filteredGameProfiles.isEmpty {
                        Text("No profiles match this filter. Try All or another chip.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 200), spacing: CosmosSpacing.gridGap)],
                            spacing: CosmosSpacing.gridGap
                        ) {
                            ForEach(filteredGameProfiles) { profile in
                                curatedProfileCard(profile)
                            }
                        }
                    }
                }
            }

            if let profile = selectedGameProfile {
                curatedProfileControls(profile)
            }
        }
    }

    private func curatedProfileFilterChip(_ filter: CuratedProfileFilter) -> some View {
        let isSelected = curatedProfileFilter == filter
        return Button {
            curatedProfileFilter = filter
            if let id = selectedGameProfileID,
               !filteredGameProfiles.contains(where: { $0.id == id }) {
                selectedGameProfileID = nil
            }
        } label: {
            Text(filter.label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.cosmosPrimary.opacity(0.18) : Color.primary.opacity(0.06),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.cosmosPrimary : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .accessibilityLabel("\(filter.label) filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func curatedProfileCard(_ profile: GameProfile) -> some View {
        let isSelected = profile.id == selectedGameProfileID
        return Button {
            selectedGameProfileID = isSelected ? nil : profile.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack {
                    Text(profile.recommendedBackend)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cosmosBright)
                    Spacer()
                    CosmosCompatBadge(status: profile.statusLabel, compact: true)
                }
                HStack(spacing: 8) {
                    if !profile.steamAppID.isEmpty {
                        Text("App ID \(profile.steamAppID)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if profile.dependencyCount > 0 || profile.fixCount > 0 {
                        Text("\(profile.dependencyCount) deps · \(profile.fixCount) fixes")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if !profile.multiplayerTagLabel.isEmpty {
                    Text(profile.multiplayerTagLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.cosmosBright.opacity(0.9))
                }
            }
            .cosmosSelectableSurface(isSelected: isSelected)
        }
        .buttonStyle(CosmosButtonStyle())
        .disabled(isRunning)
        .accessibilityLabel(curatedProfileAccessibilityLabel(profile, isSelected: isSelected))
    }

    private func curatedProfileAccessibilityLabel(_ profile: GameProfile, isSelected: Bool) -> String {
        var parts = [profile.name, profile.statusLabel, profile.recommendedBackend]
        if !profile.multiplayerTagLabel.isEmpty {
            parts.append(profile.multiplayerTagLabel)
        }
        if isSelected {
            parts.append("selected")
        }
        return parts.joined(separator: ", ")
    }

    private func curatedProfileControls(_ profile: GameProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(profile.name)
                    .font(.headline)
                Spacer()
                Text(profile.statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.cosmosPrimary)
            }
            detailRow(title: "Backend", value: profile.recommendedBackend)
            if profile.dependencyCount > 0 || profile.fixCount > 0 {
                detailRow(
                    title: "Recipes",
                    value: "\(profile.dependencyCount) dependencies, \(profile.fixCount) fixes"
                )
            }
            if profile.hasMultiplayerInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Multiplayer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if !profile.multiplayerTagLabel.isEmpty {
                        Text(profile.multiplayerTagLabel)
                            .font(.subheadline.weight(.medium))
                    }
                    if !profile.antiCheat.isEmpty, profile.antiCheat != "none" {
                        Text("Anti-cheat: \(profile.antiCheat)")
                            .font(.subheadline)
                            .foregroundStyle(profile.status == "blocked" ? .red : .primary)
                    }
                    if !profile.multiplayerNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(profile.multiplayerNotes)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if profile.hasNotes {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compatibility notes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(profile.notes)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            detailRow(title: "Apply path", value: profile.commandRelativePath)

            HStack(spacing: 12) {
                Button {
                    runCommand(
                        script: "profile.command",
                        arguments: ["show", profile.commandRelativePath],
                        environment: bottleEnvironment()
                    )
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .disabled(isRunning)

                Button {
                    runCommand(
                        script: "profile.command",
                        arguments: ["apply", profile.commandRelativePath],
                        environment: bottleEnvironment()
                    )
                } label: {
                    Label("Apply Profile", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.cosmosPrimary)
                .disabled(isRunning)
            }
        }
        .cosmosCard()
    }

    // MARK: - Repair

    private var repairSection: some View {
        CosmosSection(
            title: "Repair & Dependencies",
            systemImage: "bandage.fill",
            caption: "Winetricks installs may take several minutes. Requires brew install winetricks.",
            inCard: true
        ) {
            HStack(spacing: CosmosSpacing.gridGap) {
                Button {
                    runCommand(
                        script: "repair.command",
                        arguments: ["diagnose"],
                        environment: repairEnvironment()
                    )
                } label: {
                    Label("Diagnose Logs", systemImage: "stethoscope")
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)
                .help("Scan the launch log and prefix for common issues, then suggest fixes")

                Button {
                    runCommand(
                        script: "repair.command",
                        arguments: ["apply-suggested"],
                        environment: repairEnvironment()
                    )
                } label: {
                    Label("Apply Suggested", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)
                .help("Diagnose and auto-apply safe dependency/fix recipes")

                if let profile = selectedGameProfile,
                   profile.dependencyCount > 0 || profile.fixCount > 0 {
                    Button {
                        runCommand(
                            script: "profile.command",
                            arguments: ["for-appid", profile.steamAppID, "apply"],
                            environment: bottleEnvironment()
                        )
                    } label: {
                        Label("Apply Profile Repairs", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunning || profile.steamAppID.isEmpty)
                    .help("Install this profile's winetricks dependencies and fixes")
                }
            }

            if !dependencyRecipes.isEmpty {
                CosmosSubsectionLabel(title: "Dependencies")
                recipeButtonGrid(dependencyRecipes, prefix: "install-dep")
            }

            if !fixRecipes.isEmpty {
                CosmosSubsectionLabel(title: "Fixes")
                    .padding(.top, 4)
                recipeButtonGrid(fixRecipes, prefix: "apply-fix")
            }
        }
    }

    private func recipeButtonGrid(_ recipes: [RepairRecipe], prefix: String) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: CosmosSpacing.compactGridColumnMin), spacing: CosmosSpacing.gridGap)],
            spacing: CosmosSpacing.gridGap
        ) {
            ForEach(recipes) { recipe in
                Button {
                    runCommand(
                        script: "repair.command",
                        arguments: [prefix, recipe.id],
                        environment: bottleEnvironment()
                    )
                } label: {
                    CosmosActionTile(title: recipe.id, subtitle: recipe.description)
                }
                .buttonStyle(CosmosButtonStyle())
                .disabled(isRunning)
                .help(recipe.description)
            }
        }
    }

    // MARK: - Store expansion (0.6)

    private var storeExpansionSection: some View {
        CosmosSection(
            title: "Add Non-Steam Games",
            systemImage: "plus.rectangle.on.folder.fill",
            caption: "Import standalone Windows games from installers, GOG offline setups, itch.io downloads, Battle.net / Blizzard titles, or Epic via Legendary."
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: CosmosSpacing.gridGap)],
                spacing: CosmosSpacing.gridGap
            ) {
                storeActionButton(
                    title: "List Imports",
                    subtitle: "Standalone configs",
                    systemImage: "list.bullet",
                    script: "import_game.command",
                    arguments: ["list"]
                )
                storeActionButton(
                    title: "Run Installer",
                    subtitle: "EXE / MSI in prefix",
                    systemImage: "arrow.down.doc.fill",
                    script: "import_game.command",
                    arguments: ["run-installer"],
                    needsPath: true,
                    pathPrompt: "Path to Windows installer (.exe or .msi)"
                )
                storeActionButton(
                    title: "Register EXE",
                    subtitle: "Already installed",
                    systemImage: "app.badge.checkmark.fill",
                    script: "import_game.command",
                    arguments: ["add-exe"],
                    needsPath: true,
                    pathPrompt: "Game .exe path (drive_c/... or inside prefix)"
                )
                storeActionButton(
                    title: "GOG Installer",
                    subtitle: "Offline setup.exe",
                    systemImage: "opticaldisc.fill",
                    script: "import_game.command",
                    arguments: ["add-gog"],
                    needsStoreTitle: true,
                    pathPrompt: "Path to GOG setup.exe"
                )
                storeActionButton(
                    title: "List GOG Games",
                    subtitle: "Detected in prefix",
                    systemImage: "list.bullet.rectangle",
                    script: "import_game.command",
                    arguments: ["list-gog"]
                )
                storeActionButton(
                    title: "itch.io Folder",
                    subtitle: "Windows download",
                    systemImage: "folder.fill",
                    script: "import_game.command",
                    arguments: ["add-itch"],
                    needsStoreTitle: true,
                    pathPrompt: "Path to extracted itch.io game folder"
                )
                storeActionButton(
                    title: "Install Battle.net",
                    subtitle: "Blizzard client setup",
                    systemImage: "arrow.down.circle.fill",
                    script: "import_game.command",
                    arguments: ["install-battlenet"],
                    needsPath: true,
                    pathPrompt: "Path to Battle.net-Setup.exe"
                )
                storeActionButton(
                    title: "List Blizzard Games",
                    subtitle: "Detected in prefix",
                    systemImage: "list.bullet.rectangle",
                    script: "import_game.command",
                    arguments: ["list-battlenet"]
                )
                storeActionButton(
                    title: "Add Blizzard Game",
                    subtitle: "Battle.net launcher",
                    systemImage: "gamecontroller.fill",
                    script: "import_game.command",
                    arguments: ["add-battlenet"],
                    needsBattlenetSlug: true
                )
                storeActionButton(
                    title: "List Epic Games",
                    subtitle: "Legendary library",
                    systemImage: "list.bullet.rectangle",
                    script: "import_game.command",
                    arguments: ["list-epic"]
                )
                storeActionButton(
                    title: "Epic Login",
                    subtitle: "legendary auth",
                    systemImage: "person.badge.key.fill",
                    script: "import_game.command",
                    arguments: ["auth-epic"],
                    forceTerminal: true
                )
                storeActionButton(
                    title: "Add Epic Game",
                    subtitle: "Legendary install",
                    systemImage: "gamecontroller.fill",
                    script: "import_game.command",
                    arguments: ["add-epic"],
                    needsEpicAppName: true
                )
            }

            Text("After importing, run Install Cosmos to build the .app launcher into /Applications/Cosmos Apps.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func storeActionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        script: String,
        arguments: [String],
        needsPath: Bool = false,
        needsStoreTitle: Bool = false,
        pathPrompt: String = "",
        needsEpicAppName: Bool = false,
        needsBattlenetSlug: Bool = false,
        forceTerminal: Bool = false
    ) -> some View {
        Button {
            if needsEpicAppName {
                storeImportRequest = StoreImportRequest(
                    title: "Legendary app name",
                    message: "Use the App name from list-epic (e.g. Sugar), not always the store title. Requires: brew install legendary-gl",
                    fields: [
                        .init(id: .epicAppName, label: "Legendary app name", placeholder: "Legendary app name"),
                        .init(id: .displayName, label: "Display name", placeholder: "Display name for launcher"),
                    ],
                    submitLabel: "Install in Terminal",
                    script: script,
                    baseArguments: arguments,
                    forceTerminal: true
                )
            } else if needsBattlenetSlug {
                storeImportRequest = StoreImportRequest(
                    title: "Battle.net game",
                    message: "Use a slug from list-battlenet (e.g. starcraft-ii) or a full .exe path inside the prefix.",
                    fields: [
                        .init(id: .battlenetSlug, label: "Slug or path", placeholder: "starcraft-ii"),
                        .init(id: .displayName, label: "Display name", placeholder: "Display name for launcher"),
                    ],
                    submitLabel: "Register in Terminal",
                    script: script,
                    baseArguments: arguments,
                    forceTerminal: true
                )
            } else if needsStoreTitle {
                storeImportRequest = StoreImportRequest(
                    title: pathPrompt,
                    message: "Provide the file or folder path and a display name for the Cosmos launcher.",
                    fields: [
                        .init(
                            id: .path,
                            label: "Path",
                            placeholder: arguments.contains("add-gog")
                                ? "/Users/you/Downloads/setup_game.exe"
                                : "/Users/you/Downloads/MyGame",
                            allowsFilePicker: true
                        ),
                        .init(id: .displayName, label: "Display name", placeholder: "Display name for launcher"),
                    ],
                    submitLabel: "Run in Terminal",
                    script: script,
                    baseArguments: arguments,
                    forceTerminal: true
                )
            } else if needsPath {
                storeImportRequest = StoreImportRequest(
                    title: pathPrompt,
                    message: "Enter the full path on your Mac, or use Choose to pick a file.",
                    fields: [
                        .init(id: .path, label: "Path", placeholder: "/Users/you/Downloads/GameSetup.exe", allowsFilePicker: true),
                    ],
                    submitLabel: "Run in Terminal",
                    script: script,
                    baseArguments: arguments,
                    forceTerminal: true
                )
            } else if forceTerminal {
                runInTerminal(script: script, arguments: arguments, environment: bottleEnvironment())
            } else {
                runCommand(script: script, arguments: arguments, environment: bottleEnvironment())
            }
        } label: {
            CosmosActionTile(title: title, subtitle: subtitle, systemImage: systemImage)
        }
        .buttonStyle(CosmosButtonStyle())
        .disabled(isRunning)
    }

    private func submitStoreImport(
        _ request: StoreImportRequest,
        values: [StoreImportRequest.FieldKind: String]
    ) {
        func trimmed(_ kind: StoreImportRequest.FieldKind) -> String {
            (values[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var args = request.baseArguments
        let path = trimmed(.path)
        if !path.isEmpty { args.append(path) }
        let slug = trimmed(.battlenetSlug)
        if !slug.isEmpty { args.append(slug) }
        let epic = trimmed(.epicAppName)
        if !epic.isEmpty { args.append(epic) }
        let name = trimmed(.displayName)
        if !name.isEmpty { args.append(contentsOf: ["--name", name]) }
        if request.baseArguments.contains("add-epic") {
            args.append("--install")
        }

        runInTerminal(script: request.script, arguments: args, environment: bottleEnvironment())
    }

    private func repairEnvironment() -> [String: String] {
        var env = bottleEnvironment()
        if let appid = activeSteamAppID, !appid.isEmpty {
            env["COSMOS_PROFILE_APPID"] = appid
            env["STEAM_APPID"] = appid
        }
        return env
    }

    // MARK: - CosmosDB

    private var compatibilitySection: some View {
        CosmosSection(
            title: "Compatibility",
            systemImage: "chart.bar.doc.horizontal",
            caption: "Hints from ProtonDB, AppleGamingWiki, MacGamingDB, and the community DB. Local reports capture your macOS results.",
            inCard: true
        ) {
            if let appid = activeSteamAppID {
                detailRow(title: "Steam App ID", value: appid)

                if let badge = resolvedCompatBadge, badge.isKnown {
                    HStack(spacing: 8) {
                        CosmosCompatBadge(status: badge.status)
                        Text("via \(badge.source.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !badge.label.isEmpty, badge.source != "profile" {
                            Text("· \(badge.label)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                HStack(spacing: CosmosSpacing.gridGap) {
                    Button {
                        runCommand(script: "cosmosdb.command", arguments: ["lookup", appid])
                    } label: {
                        Label("Compatibility Lookup", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunning)

                    Button {
                        runCommand(script: "cosmosdb.command", arguments: ["sync"])
                    } label: {
                        Label("Sync Community DB", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunning)

                    if selectedGameProfile != nil {
                        Button {
                            runCommand(
                                script: "profile.command",
                                arguments: ["for-appid", appid, "apply"],
                                environment: bottleEnvironment()
                            )
                        } label: {
                            Label("Apply YAML Profile", systemImage: "doc.text.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning)
                    } else {
                        Button {
                            runCommand(script: "cosmosdb.command", arguments: ["suggest-profile", appid, "--write"])
                        } label: {
                            Label("Suggest Profile Draft", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Report macOS result")
                        .font(.subheadline.weight(.medium))
                    Picker("Status", selection: $cosmosReportStatus) {
                        ForEach(Self.cosmosStatusOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .leading)
                    TextField("Optional note", text: $cosmosReportNote)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        var args = ["report", appid, cosmosReportStatus]
                        let note = cosmosReportNote.trimmingCharacters(in: .whitespaces)
                        if !note.isEmpty { args.append(note) }
                        runCommand(
                            script: "cosmosdb.command",
                            arguments: args,
                            environment: bottleEnvironment()
                        )
                    } label: {
                        Label("Save Local Report", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isRunning)
                }
                .padding(.top, 4)
            } else {
                Text("Select a saved launcher profile or curated YAML profile with a Steam App ID to look up or report compatibility.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .cosmosCard()
        .onChange(of: activeSteamAppID) { _, _ in refreshCompatBadge() }
        .onChange(of: selectedGameProfileID) { _, _ in refreshCompatBadge() }
    }

    private static let cosmosStatusOptions = [
        "platinum", "gold", "silver", "playable", "bronze", "broken", "blocked",
    ]

    // MARK: - Bottles

    private var bottlesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Bottles", systemImage: "cylinder.split.1x2.fill")
                Spacer()
                Button {
                    newBottleName = ""
                    newBottleBackend = "recommended"
                    newBottleWindows = "win10"
                    newBottleRetina = false
                    showNewBottleSheet = true
                } label: {
                    Label("New Bottle", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.cosmosPrimary)
                .disabled(isRunning)
                .help("Create a new isolated Wine bottle")
            }

            if bottles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No bottles yet. Each bottle is an isolated Wine prefix with its own graphics backend and settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        newBottleName = ""
                        newBottleBackend = "recommended"
                        newBottleWindows = "win10"
                        newBottleRetina = false
                        showNewBottleSheet = true
                    } label: {
                        Label("Create your first bottle", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.cosmosPrimary)
                    .disabled(isRunning)
                }
                .accessibilityElement(children: .combine)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    ForEach(bottles) { bottle in
                        bottleCard(bottle)
                    }
                }
            }

            if let bottle = selectedBottle {
                bottleControls(bottle)
            }
        }
        .sheet(isPresented: $showNewBottleSheet) { newBottleSheet }
        .confirmationDialog("Reset this bottle?", isPresented: $showBottleResetConfirmation, titleVisibility: .visible) {
            Button("Reset Prefix", role: .destructive) {
                if let bottle = selectedBottle {
                    runCommand(script: "bottle.command", arguments: ["reset", bottle.name, "--force"])
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes the bottle's Wine prefix (Steam and games inside it). Its settings and logs are kept; the next launch recreates the prefix.")
        }
        .confirmationDialog("Delete this bottle?", isPresented: $showBottleDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Bottle", role: .destructive) {
                if let bottle = selectedBottle {
                    runCommand(script: "bottle.command", arguments: ["delete", bottle.name, "--force"])
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the bottle entirely — its prefix, settings, and logs. This cannot be undone.")
        }
    }

    private func bottleCard(_ bottle: Bottle) -> some View {
        let isSelected = bottle.id == selectedBottleID
        return Button {
            selectedBottleID = isSelected ? nil : bottle.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "cylinder.split.1x2.fill")
                        .foregroundStyle(Color.cosmosPrimary)
                    Text(bottle.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }
                Text(bottle.backend)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.cosmosBright)
                Text(bottle.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .cosmosSelectableSurface(isSelected: isSelected, minHeight: 86)
        }
        .buttonStyle(CosmosButtonStyle())
        .disabled(isRunning)
        .accessibilityLabel("\(bottle.name), \(bottle.backend), \(bottle.statusText)")
        .accessibilityHint(isSelected ? "Double-tap to deselect" : "Double-tap to select and show controls")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func bottleControls(_ bottle: Bottle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(bottle.name)
                .font(.title3.weight(.semibold))

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Graphics backend")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                        .textCase(.uppercase)
                    Picker("Backend", selection: backendBinding(for: bottle)) {
                        ForEach(BottleStore.backendOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200, alignment: .leading)
                    .disabled(isRunning)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Windows version")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                        .textCase(.uppercase)
                    Picker("Windows", selection: windowsBinding(for: bottle)) {
                        Text("Wine default").tag("")
                        ForEach(BottleStore.windowsOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 160, alignment: .leading)
                    .disabled(isRunning)
                }
            }

            Toggle(isOn: retinaBinding(for: bottle)) {
                Text("Retina mode")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(isRunning)

            VStack(alignment: .leading, spacing: 6) {
                Text("Thread sync")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                    .textCase(.uppercase)
                Picker("Thread sync", selection: bottleSyncBinding(for: bottle)) {
                    ForEach(GraphicsSettings.syncModeOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(isRunning)
            }

            HStack(alignment: .top, spacing: 24) {
                detailRow(title: "Wine", value: bottle.wineVersion)
                detailRow(title: "Status", value: bottle.statusText)
            }

            detailRow(title: "Prefix", value: bottle.prefixURL.path)

            HStack(spacing: 12) {
                bottleActionButton("Launch", systemImage: "play.fill", prominent: true, help: "Launch Steam in this bottle") {
                    runCommand(script: "bottle.command", arguments: ["launch", bottle.name, "--steam"])
                }
                bottleActionButton("Open Logs", systemImage: "doc.text.magnifyingglass", help: "Open this bottle's log folder") {
                    runCommand(script: "bottle.command", arguments: ["logs", bottle.name])
                }
                bottleActionButton("Reset", systemImage: "arrow.counterclockwise", destructive: true, help: "Delete this bottle's Wine prefix") {
                    showBottleResetConfirmation = true
                }
                bottleActionButton("Delete", systemImage: "trash.fill", destructive: true, help: "Remove this bottle and all of its data") {
                    showBottleDeleteConfirmation = true
                }
            }
        }
        .cosmosCard()
    }

    private func bottleActionButton(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        destructive: Bool = false,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let tint: Color = destructive ? Color.red : Color.cosmosPrimary
        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(tint.opacity(prominent ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .help(help ?? title)
    }

    private var newBottleSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Bottle")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.cosmosPrimary)

            Text("Creates an isolated Wine prefix you can tune independently from the default bottle.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                TextField("Name", text: $newBottleName)
                    .textFieldStyle(.roundedBorder)
                    .focused($newBottleNameFocused)
                Picker("Backend", selection: $newBottleBackend) {
                    ForEach(BottleStore.backendOptions, id: \.self) { Text($0).tag($0) }
                }
                Picker("Windows version", selection: $newBottleWindows) {
                    ForEach(BottleStore.windowsOptions, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Enable Retina mode", isOn: $newBottleRetina)
            }
            .formStyle(.grouped)

            if !newBottleName.isEmpty && !BottleStore.isValidName(newBottleName) {
                Text("Use letters, digits, '.', '_' or '-' (not starting with '.', '_' or '-').")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { showNewBottleSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { createBottle() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cosmosPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!BottleStore.isValidName(newBottleName))
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { newBottleNameFocused = true }
    }

    private func backendBinding(for bottle: Bottle) -> Binding<String> {
        Binding(
            get: { selectedBottle?.backend ?? bottle.backend },
            set: { newValue in
                guard newValue != bottle.backend else { return }
                runCommand(script: "bottle.command", arguments: ["set", bottle.name, "COSMOS_BACKEND", newValue])
            }
        )
    }

    private func windowsBinding(for bottle: Bottle) -> Binding<String> {
        Binding(
            get: { selectedBottle?.windowsVersion ?? bottle.windowsVersion },
            set: { newValue in
                guard newValue != bottle.windowsVersion else { return }
                runCommand(script: "bottle.command", arguments: ["set", bottle.name, "WINDOWS_VERSION", newValue])
            }
        )
    }

    private func retinaBinding(for bottle: Bottle) -> Binding<Bool> {
        Binding(
            get: { selectedBottle?.retinaEnabled ?? bottle.retinaEnabled },
            set: { newValue in
                let flag = newValue ? "1" : "0"
                let current = bottle.retinaEnabled ? "1" : "0"
                guard flag != current else { return }
                runCommand(script: "bottle.command", arguments: ["set", bottle.name, "WINE_RETINA_MODE", flag])
            }
        )
    }

    private func bottleSyncBinding(for bottle: Bottle) -> Binding<String> {
        Binding(
            get: { selectedBottle?.syncMode ?? bottle.syncMode },
            set: { newValue in
                guard newValue != bottle.syncMode else { return }
                runCommand(script: "bottle.command", arguments: ["set", bottle.name, "COSMOS_SYNC_MODE", newValue])
            }
        )
    }

    private func createBottle() {
        let name = newBottleName.trimmingCharacters(in: .whitespaces)
        guard BottleStore.isValidName(name) else { return }
        showNewBottleSheet = false
        let args = [
            "create", name,
            "--backend", newBottleBackend,
            "--windows", newBottleWindows,
            "--retina", newBottleRetina ? "1" : "0",
        ]
        selectedBottleID = name
        runCommand(script: "bottle.command", arguments: args)
    }

    private func selectedProfileSection(_ profile: SavedProfile) -> some View {
        let curated = profile.steamAppID.flatMap { GameProfileStore.find(steamAppID: $0) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Selected Launcher", systemImage: "gamecontroller.fill")
                Spacer()
                if let curated, let badge = sidebarCompatBadge(for: profile) {
                    CosmosCompatBadge(status: badge.status)
                }
                Button {
                    revealInFinder(profile.fileURL)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.cosmosPrimary)
                .help("Show this profile's config file in Finder")
            }

            if let curated, curated.isBlocked {
                CosmosNoticeBanner(
                    tint: .red,
                    systemImage: "exclamationmark.octagon.fill",
                    title: "Blocked on macOS",
                    message: curated.blockedLaunchMessage
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                detailRow(title: "Executable", value: profile.path)
                Divider()
                detailRow(title: "Arguments", value: profile.args.isEmpty ? "None" : profile.args)
                if let appid = profile.steamAppID, !appid.isEmpty {
                    Divider()
                    detailRow(title: "Steam App ID", value: appid)
                }
                Divider()
                detailRow(title: "Config file", value: profile.fileURL.lastPathComponent)
            }
            .cosmosCard()

            if let yaml = curated, !yaml.isBlocked {
                HStack {
                    Text("Curated preset: \(yaml.name) · \(yaml.recommendedBackend) backend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply") {
                        runCommand(
                            script: "profile.command",
                            arguments: ["apply", yaml.commandRelativePath],
                            environment: bottleEnvironment()
                        )
                    }
                    .disabled(isRunning)
                }
            }
        }
    }

    private var selectedProfileLaunchSubtitle: String {
        guard let selectedProfile else { return "Select a profile first" }
        return selectedProfileHasExecutablePath ? "Ready to launch" : "Set an executable path"
    }

    private var selectedProfileHasExecutablePath: Bool {
        selectedProfile?.path.isEmpty == false
    }

    // MARK: - Console

    private var consoleSection: some View {
        Group {
            if isSetupComplete {
                consoleOutputPanel
            } else {
                DisclosureGroup(isExpanded: $consoleExpanded) {
                    consoleOutputPanel
                } label: {
                    Label("Technical output", systemImage: "terminal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.cosmosPrimary)
                }
            }
        }
    }

    private var consoleOutputPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if isSetupComplete {
                    sectionHeader("Launcher Output", systemImage: "terminal.fill")
                }
                if isRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.cosmosPrimary)
                        Text("Running…")
                            .font(.caption)
                            .foregroundStyle(Color.cosmosPrimary)
                    }
                }
                Spacer()
                Button {
                    copyOutputToClipboard()
                } label: {
                    Label(didCopyOutput ? "Copied" : "Copy", systemImage: didCopyOutput ? "checkmark.circle" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(didCopyOutput ? Color.green : .secondary)
                .disabled(output.isEmpty)
                .help("Copy the output log to the clipboard")
                .accessibilityLabel(didCopyOutput ? "Output copied" : "Copy output")
                Button {
                    output = ""
                    outputWasTrimmed = false
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(output.isEmpty || isRunning)
                .help("Clear the output log")
                .accessibilityLabel("Clear output")
            }

            if outputWasTrimmed {
                CosmosNoticeBanner(
                    tint: .secondary,
                    systemImage: "scissors",
                    title: nil,
                    message: "Earlier log lines were trimmed to keep the view responsive. Copy output to save the full log."
                )
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(output)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .foregroundStyle(Color(red: 0.85, green: 0.80, blue: 1.0))
                        Color.clear
                            .frame(height: 1)
                            .id(consoleBottomID)
                    }
                    .padding(16)
                }
                .frame(minHeight: isSetupComplete ? 220 : 140)
                .background(Color(red: 0.07, green: 0.03, blue: 0.16), in: RoundedRectangle(cornerRadius: 16))
                .onChange(of: output) { _ in
                    if reduceMotion {
                        proxy.scrollTo(consoleBottomID, anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(consoleBottomID, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var setupCompleteBanner: some View {
        CosmosNoticeBanner(
            tint: .green,
            systemImage: "party.popper.fill",
            title: "Setup complete",
            message: "Launch Steam or pick a saved profile in the sidebar. Game launchers are in /Applications/Cosmos Apps.",
            onDismiss: { showSetupCompleteBanner = false }
        )
    }

    private func openSetupHelp() {
        openRepositoryDoc(
            relativePath: "docs/STEAM_SETUP.md",
            bundleName: "STEAM_SETUP.md",
            fallbackMessage: "Setup guide not found. See docs/STEAM_SETUP.md in the Cosmos repository."
        )
    }

    private func openMultiplayerHelp() {
        openRepositoryDoc(
            relativePath: "docs/MULTIPLAYER.md",
            bundleName: "MULTIPLAYER.md",
            fallbackMessage: "Multiplayer guide not found. See docs/MULTIPLAYER.md in the Cosmos repository."
        )
    }

    private func openRepositoryDoc(relativePath: String, bundleName: String, fallbackMessage: String) {
        let candidates: [URL] = [
            repositoryRootURL?.appendingPathComponent(relativePath),
            Bundle.main.resourceURL?.appendingPathComponent(relativePath),
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
        ].compactMap { $0 }

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
            output = "Opened guide: \(url.path)\n\n" + output
            return
        }
        output = "\(fallbackMessage)\n\n" + output
    }

    private func copyOutputToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
        didCopyOutput = true
        // Revert the transient "Copied" confirmation after a moment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopyOutput = false
        }
    }

    // MARK: - Reusable components

    private var steamPrefixStatusLabel: String {
        if steamSettings.isSteamInstalled { return "Steam ready" }
        if steamSettings.isPrefixInitialized { return "Prefix ready — install Steam" }
        return "Steam bottle not prepared"
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if wineRuntime.needsRosetta {
                statusRow(
                    label: wineRuntime.rosettaLabel,
                    icon: wineRuntime.rosettaReady ? "checkmark.circle.fill" : "cpu",
                    color: wineRuntime.rosettaReady ? Color.green : Color.orange
                )
            }
            statusRow(
                label: wineRuntime.wineLabel,
                icon: wineRuntime.wineInstalled ? "wineglass.fill" : "arrow.down.circle",
                color: wineRuntime.wineInstalled ? Color.cosmosBright : Color.secondary
            )
            statusRow(
                label: cosmosInstalled ? "Cosmos installed" : "Cosmos required",
                icon: cosmosInstalled ? "checkmark.circle.fill" : "arrow.down.circle",
                color: cosmosInstalled ? Color.green : Color.orange
            )
            statusRow(
                label: steamPrefixStatusLabel,
                icon: steamSettings.isSteamInstalled ? "shippingbox.fill" : "shippingbox",
                color: steamSettings.isSteamInstalled ? Color.cosmosBright : Color.secondary
            )
            statusRow(
                label: "\(profiles.count) profile\(profiles.count == 1 ? "" : "s") saved",
                icon: "gamecontroller.fill",
                color: Color.cosmosPrimary.opacity(0.8)
            )
            statusRow(
                label: bottles.isEmpty
                    ? "No bottles yet"
                    : "\(bottles.count) bottle\(bottles.count == 1 ? "" : "s")",
                icon: "cylinder.split.1x2.fill",
                color: bottles.isEmpty ? Color.secondary : Color.cosmosPrimary.opacity(0.8)
            )
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup status")
    }

    private func statusRow(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 18)
            Text(label)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.cosmosPrimary)
    }

    private func prominentButton(
        title: String,
        subtitle: String,
        systemImage: String,
        disabled: Bool = false,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .opacity(0.85)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.cosmosBright, Color.cosmosPrimary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .shadow(color: Color.cosmosPrimary.opacity(0.4), radius: 8, y: 4)
            .hoverBrighten()
        }
        .buttonStyle(CosmosButtonStyle())
        .disabled(disabled || isRunning)
        .opacity((disabled || isRunning) ? 0.55 : 1)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityHint(disabled ? subtitle : (help ?? subtitle))
        .help(help ?? subtitle)
    }

    private func secondaryButton(
        title: String,
        subtitle: String,
        systemImage: String,
        destructive: Bool = false,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(destructive ? Color.red.opacity(0.8) : Color.cosmosPrimary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: CosmosSpacing.buttonRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CosmosSpacing.buttonRadius)
                    .strokeBorder(
                        destructive ? Color.red.opacity(0.2) : Color.cosmosPrimary.opacity(0.12),
                        lineWidth: 1
                    )
            )
            .hoverBrighten()
        }
        .buttonStyle(CosmosButtonStyle())
        .disabled(isRunning)
        .opacity(isRunning ? 0.55 : 1)
        .accessibilityLabel("\(title). \(subtitle)")
        .help(help ?? subtitle)
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                .textCase(.uppercase)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private func refreshStatus(message: String? = nil) {
        SteamSettingsStore.ensureOnDisk()
        cosmosInstalled = fileManager.fileExists(atPath: cosmosAppsURL.path)
        steamSettings = SteamSettingsStore.load()
        reloadGraphicsSettings()
        wineRuntime = WineRuntimeStore.load(wineVersion: steamSettings.wineVersion)
        profiles = loadProfiles()
        bottles = BottleStore.load()
        gameProfiles = GameProfileStore.load()
        dependencyRecipes = RecipeStore.loadDependencies()
        fixRecipes = RecipeStore.loadFixes()

        if !profiles.contains(where: { $0.id == selectedProfileID }) {
            self.selectedProfileID = profiles.first?.id
        }
        if let id = selectedGameProfileID, !gameProfiles.contains(where: { $0.id == id }) {
            self.selectedGameProfileID = nil
        }
        if let id = selectedBottleID, !bottles.contains(where: { $0.id == id }) {
            self.selectedBottleID = nil
        }

        refreshCompatBadge()

        if let message {
            output = message + "\n\n" + output
        }
    }

    private func refreshCompatBadge() {
        guard let appid = activeSteamAppID else {
            resolvedCompatBadge = nil
            return
        }
        resolvedCompatBadge = CosmosBadgeStore.resolve(
            steamAppID: appid,
            curated: selectedGameProfile ?? GameProfileStore.find(steamAppID: appid)
        )
    }

    private func loadProfiles() -> [SavedProfile] {
        let profileURLs = (try? fileManager.contentsOfDirectory(at: profileDirectoryURL, includingPropertiesForKeys: nil)) ?? []

        return profileURLs
            .filter { $0.pathExtension == "conf" }
            .compactMap(loadProfile)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadProfile(from fileURL: URL) -> SavedProfile? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        var name = fileURL.deletingPathExtension().lastPathComponent
        var path = ""
        var args = ""
        var steamAppID: String?

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("["),
                  let separatorIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: separatorIndex)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))

            switch key {
            case "name":
                if !value.isEmpty {
                    name = value
                }
            case "path":
                path = value
            case "args":
                args = value
            case "STEAM_GAME_ID":
                steamAppID = value
            default:
                break
            }
        }

        return SavedProfile(
            id: fileURL.lastPathComponent,
            name: name,
            path: path,
            args: args,
            steamAppID: steamAppID,
            fileURL: fileURL
        )
    }

    /// Pass the selected bottle into CLI tools that honor COSMOS_BOTTLE.
    private func bottleEnvironment() -> [String: String] {
        guard let bottle = selectedBottle else { return [:] }
        return ["COSMOS_BOTTLE": bottle.name]
    }

    // Locate a helper script, preferring a copy bundled into the app's
    // Resources (installed Cosmos.app) and falling back to the repository
    // checkout (running from a development build).
    private func resolveScript(_ script: String) -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent(script)
            if fileManager.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }
        if let repositoryRootURL {
            let dev = repositoryRootURL.appendingPathComponent(script)
            if fileManager.isExecutableFile(atPath: dev.path) {
                return dev
            }
        }
        return nil
    }

    // Run a helper in Terminal.app instead of the embedded console. Use this for
    // actions that need a real TTY — `sudo` password entry and interactive
    // confirmations — which the piped Process runner cannot provide. We launch it
    // and return; completion happens in Terminal, so the user taps Refresh after.
    private func runInTerminal(
        script: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) {
        guard let scriptURL = resolveScript(script) else {
            let message = "Script not found or not executable: \(script)"
            output = message
            showBanner(kind: .failure, message: message)
            return
        }

        var parts: [String] = []
        beginCommandOutput()
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            parts.append("export \(key)=\(ShellArgumentParser.shellQuote(value))")
        }
        parts.append(([scriptURL.path] + arguments).map(ShellArgumentParser.shellQuote).joined(separator: " "))
        let shellCommand = parts.joined(separator: "; ")

        let appleScript = """
        tell application "Terminal"
            activate
            do script "\(ShellArgumentParser.appleScriptEscape(shellCommand))"
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", appleScript]

        do {
            try task.run()
            let displayed = ([script] + arguments).joined(separator: " ")
            output = """
            Opened Terminal to run: \(displayed)

            Complete any password or confirmation prompts in the Terminal window, \
            then click Refresh in the toolbar (⌘R) or switch back to this window — status updates automatically.
            """
            showBanner(
                kind: .info,
                message: "Running in Terminal — complete prompts there, then refresh status (⌘R)."
            )
        } catch {
            let message = "Could not open Terminal: \(error.localizedDescription)"
            output = message
            showBanner(kind: .failure, message: message)
        }
    }

    private func showBanner(kind: CommandBannerKind, message: String) {
        commandBanner = CommandBanner(kind: kind, message: message)
    }

    private func beginCommandOutput() {
        commandBanner = nil
        consoleExpanded = true
    }

    private func runCommand(script: String, arguments: [String] = [], environment: [String: String] = [:]) {
        guard let scriptURL = resolveScript(script) else {
            let message = "Script not found or not executable: \(script)"
            output = message
            showBanner(kind: .failure, message: message)
            return
        }

        let displayedCommand = ([script] + arguments).joined(separator: " ")
        beginCommandOutput()
        output = "Running: \(displayedCommand)\n\n"
        isRunning = true

        let task = Process()
        task.executableURL = scriptURL
        task.arguments = arguments
        task.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        var mergedEnvironment = ProcessInfo.processInfo.environment
        mergedEnvironment.removeValue(forKey: "COSMOS_BOTTLE")
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        task.environment = mergedEnvironment

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                return
            }

            DispatchQueue.main.async {
                output += text
                // Keep the buffer bounded: detached launches (e.g. Steam) can
                // stream logs indefinitely, which would otherwise grow memory and
                // stall the text view.
                if output.count > 120_000 {
                    output = "…(earlier output trimmed)…\n" + String(output.suffix(100_000))
                    outputWasTrimmed = true
                }
            }
        }

        task.terminationHandler = { process in
            pipe.fileHandleForReading.readabilityHandler = nil
            // Drain anything written between the last readability callback and exit
            // so a script's final lines are not truncated from the output pane.
            let tail = pipe.fileHandleForReading.readDataToEndOfFile()
            let tailText = String(data: tail, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                if !tailText.isEmpty {
                    output += tailText
                }
                isRunning = false
                let succeeded = process.terminationStatus == 0
                output += succeeded ? "\nDone." : "\nExited with status \(process.terminationStatus)."
                showBanner(
                    kind: succeeded ? .success : .failure,
                    message: succeeded
                        ? "Command finished successfully."
                        : "Command exited with status \(process.terminationStatus). Check the output below."
                )
                refreshStatus()
            }
        }

        do {
            try task.run()
        } catch {
            isRunning = false
            let message = "Failed to run command: \(error.localizedDescription)"
            output = message
            showBanner(kind: .failure, message: message)
        }
    }

    private static func findRepositoryRoot() -> URL? {
        let fileManager = FileManager.default
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        while candidate.path != "/" {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("run.command").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        if fileManager.fileExists(atPath: currentDirectory.appendingPathComponent("run.command").path) {
            return currentDirectory
        }

        return nil
    }

}

private struct SavedProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let args: String
    let steamAppID: String?
    let fileURL: URL
}

extension Notification.Name {
    static let cosmosRefreshStatus = Notification.Name("com.cosmos.refreshStatus")
    static let cosmosContinueSetup = Notification.Name("com.cosmos.continueSetup")
    static let cosmosOpenSetupHelp = Notification.Name("com.cosmos.openSetupHelp")
    static let cosmosSelectSection = Notification.Name("com.cosmos.selectSection")
}

#if DEBUG
#Preview {
    ContentView()
}
#endif
