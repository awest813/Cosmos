import Foundation
import AppKit
import SwiftUI

private typealias CommandIntent = CommandFailureContext

struct ContentView: View {
    private let fileManager = FileManager.default
    private let repositoryRootURL = CosmosPaths.cosmosRoot()
    private let consoleBottomID = "console-bottom"
    private let steamLibraryCheckInterval: TimeInterval = 300

    @State private var output = "Welcome to Cosmos\n\nNew here? Follow the setup guide below — one button per step.\nFirst-time setup takes about 10–15 minutes (downloads + Steam installer).\n\nWhen finished, launch Steam, install a Windows game, then tap Build Game Launchers."
    @State private var profiles: [SavedProfile] = []
    @State private var selectedProfileID: String?
    @State private var profileSearchText = ""
    @State private var cosmosInstalled = false
    @State private var cosmosAppCount = 0
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
    @State private var commandBannerQueue = CommandBannerQueue()
    @EnvironmentObject private var appState: CosmosAppState
    @State private var outputWasTrimmed = false
    @State private var storeImportRequest: StoreImportRequest?
    @State private var pendingTerminalJobID: String?
    @State private var updateAvailable = false
    @State private var profilePreferences = ProfilePreferencesStore.load()
    @State private var sidebarProfileFilter: SidebarProfileFilter = .all
    @State private var lastSteamLibraryCheck: Date?
    @State private var steamLibraryCheckInFlight = false
    @State private var pendingNewSteamGames = 0
    @State private var pendingRemovedSteamGames = 0
    @State private var steamHealth = SteamHealthStatus.empty
    @State private var steamHealthInFlight = false
    @State private var pendingUnregisteredGogGames = 0
    @State private var pendingBrokenSteamInstalls = 0
    @State private var lastWarnedBrokenSteamInstalls = 0
    @State private var setupCompatAppID = ""
    @State private var consoleHasNewOutput = false

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
    private var profileSearchQuery: String {
        profileSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchingProfiles: Bool {
        !profileSearchQuery.isEmpty
    }

    private var filteredProfiles: [SavedProfile] {
        guard isSearchingProfiles else { return profiles }
        return profiles.filter { profile in
            profile.name.localizedCaseInsensitiveContains(profileSearchQuery)
                || profile.path.localizedCaseInsensitiveContains(profileSearchQuery)
                || (profile.steamAppID?.localizedCaseInsensitiveContains(profileSearchQuery) ?? false)
        }
    }

    private var favoriteProfiles: [SavedProfile] {
        let ids = Set(profilePreferences.favoriteIDs)
        return profiles
            .filter { ids.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var recentProfiles: [SavedProfile] {
        let favorites = Set(profilePreferences.favoriteIDs)
        return profilePreferences.recentIDs.compactMap { id in
            profiles.first { $0.id == id }
        }.filter { !favorites.contains($0.id) }
    }

    /// Saved profiles not already shown under Favorites or Recent.
    private var pinnedProfileIDs: Set<String> {
        Set(profilePreferences.favoriteIDs + profilePreferences.recentIDs)
    }

    private var catalogProfiles: [SavedProfile] {
        profiles
            .filter { !pinnedProfileIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    /// GOG slug from a saved launcher config or curated GOG YAML profile.
    private var activeGogSlug: String? {
        if let slug = selectedProfile?.gogSlug, !slug.isEmpty { return slug }
        if let slug = selectedGameProfile?.gogSlug, !slug.isEmpty { return slug }
        if selectedGameProfile?.store == "gog" { return selectedGameProfile?.id }
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
            resumeTerminalJobs()
            checkForUpdatesSilently()
            refreshSteamHealth()
            checkGogLibraryForUnregistered()
            if isSetupComplete {
                checkSteamLibraryForNewGames(autoSync: true)
            }
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
            resumeTerminalJobs()
            refreshSteamHealth()
            checkGogLibraryForUnregistered()
            checkSteamLibraryForNewGames(autoSync: true)
        }
        .onChange(of: isSetupComplete) { complete in
            appState.updateSetupComplete(complete)
            if complete {
                if !showSetupCompleteBanner {
                    showSetupCompleteBanner = true
                }
                checkSteamLibraryForNewGames(autoSync: true)
            }
        }
        .onChange(of: selectedBottleID) { newID in
            if newID != nil, isSteamReady {
                dashboardSection = .bottles
            }
        }
        .onChange(of: selectedGameProfileID) { newID in
            if newID != nil, isSteamReady {
                dashboardSection = .library
            }
        }
        .onChange(of: selectedProfileID) { newID in
            refreshCompatBadge()
            if newID != nil, isSteamReady {
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
                    return nil
                }
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if isSteamReady, let bottle = selectedBottle {
                    StatusChip(
                        label: "Bottle: \(bottle.name)",
                        systemImage: "cylinder.split.1x2.fill"
                    )
                } else if isSteamReady {
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
                } else if steamHealthInFlight || steamLibraryCheckInFlight {
                    StatusChip(
                        label: "Checking library…",
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: .secondary
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
                Text("\(wineRuntime.platformDisplayName) Launcher")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .background(CosmosGradients.sidebarHeader)

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

                if !isSearchingProfiles {
                    sidebarProfileFilterChips
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }

            // Profile list
            List(selection: $selectedProfileID) {
                if isSearchingProfiles {
                    Section("Search") {
                        if filteredProfiles.isEmpty {
                            sidebarEmptySearchRow
                        } else {
                            ForEach(filteredProfiles) { profile in
                                profileRow(profile)
                                    .tag(profile.id)
                            }
                        }
                    }
                } else if profiles.isEmpty {
                    Section("Saved Profiles") {
                        sidebarEmptyProfilesRow
                    }
                } else {
                    switch sidebarProfileFilter {
                    case .all:
                        if !favoriteProfiles.isEmpty {
                            Section("Favorites") {
                                ForEach(favoriteProfiles) { profile in
                                    profileRow(profile)
                                        .tag(profile.id)
                                }
                            }
                        }
                        if !recentProfiles.isEmpty {
                            Section("Recent") {
                                ForEach(recentProfiles) { profile in
                                    profileRow(profile)
                                        .tag(profile.id)
                                }
                            }
                        }
                        if !catalogProfiles.isEmpty {
                            Section(profileSectionTitle) {
                                ForEach(catalogProfiles) { profile in
                                    profileRow(profile)
                                        .tag(profile.id)
                                }
                            }
                        }
                    case .favorites:
                        Section("Favorites") {
                            if favoriteProfiles.isEmpty {
                                sidebarEmptyFilterRow
                            } else {
                                ForEach(favoriteProfiles) { profile in
                                    profileRow(profile)
                                        .tag(profile.id)
                                }
                            }
                        }
                    case .recent:
                        Section("Recent") {
                            if recentProfiles.isEmpty {
                                sidebarEmptyFilterRow
                            } else {
                                ForEach(recentProfiles) { profile in
                                    profileRow(profile)
                                        .tag(profile.id)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .cosmosSidebarBackground()
    }

    private var profileSectionTitle: String {
        "All Games (\(catalogProfiles.count))"
    }

    private var sidebarProfileFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SidebarProfileFilter.allCases) { filter in
                    CosmosFilterChip(
                        label: filter.label,
                        isSelected: sidebarProfileFilter == filter
                    ) {
                        sidebarProfileFilter = filter
                    }
                    .disabled(isRunning)
                    .accessibilityLabel("\(filter.label) sidebar filter")
                }
            }
        }
    }

    private var sidebarEmptyProfilesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No profiles yet", systemImage: "tray")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text(isSteamReady ? "Run Detect Games or Build Launchers to populate saved profiles." : "Complete setup above, then build launchers to see games here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No saved game profiles. Run Detect Games after installing Steam.")
    }

    private var sidebarEmptySearchRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No matches", systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text("No saved game matches “\(profileSearchQuery)”.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No saved games match the search.")
    }

    private var sidebarEmptyFilterRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Nothing here yet", systemImage: "tray")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text(sidebarFilterEmptyCaption)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sidebarFilterEmptyCaption)
    }

    private var sidebarFilterEmptyCaption: String {
        switch sidebarProfileFilter {
        case .all:
            return "No saved game profiles."
        case .favorites:
            return "Star a game in the sidebar to pin it here."
        case .recent:
            return "Launch a game to see it in Recent."
        }
    }

    private var profileSearchField: some View {
        CosmosSearchField(placeholder: "Search games", text: $profileSearchText, disabled: isRunning)
            .accessibilityLabel("Search saved games")
    }

    private func profileRow(_ profile: SavedProfile) -> some View {
        let badge = sidebarCompatBadge(for: profile)
        let isFavorite = ProfilePreferencesStore.isFavorite(profileID: profile.id, in: profilePreferences)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favorite")
                }
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)
                if let badge {
                    CosmosCompatBadge(status: badge.status, compact: true)
                }
                if !profile.canLaunchFromDashboard {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("No launch method configured — edit the profile config")
                }
            }
            Text(profileSubtitle(profile))
                .font(.caption)
                .foregroundStyle(profile.canLaunchFromDashboard ? .secondary : .tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(sidebarProfileAccessibilityLabel(profile, badge: badge))
        .accessibilityAddTraits(profile.id == selectedProfileID ? .isSelected : [])
        .contextMenu {
            Button {
                selectedProfileID = profile.id
                launchProfile(profile)
            } label: {
                Label("Launch", systemImage: "play.fill")
            }
            .disabled(!profile.canLaunchFromDashboard || !wineRuntime.canStartWineLaunch || isRunning)

            Button {
                profilePreferences = ProfilePreferencesStore.toggleFavorite(profileID: profile.id)
            } label: {
                let isFavorite = ProfilePreferencesStore.isFavorite(profileID: profile.id, in: profilePreferences)
                Label(isFavorite ? "Remove Favorite" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star")
            }

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
                if let commandBanner = commandBannerQueue.current {
                    VStack(alignment: .leading, spacing: 6) {
                        CommandBannerView(banner: commandBanner) {
                            dismissCommandBanner()
                        }
                        if commandBannerQueue.pendingCount > 0 {
                            Text("\(commandBannerQueue.pendingCount) more notification\(commandBannerQueue.pendingCount == 1 ? "" : "s") — dismiss to see next")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                steamHealthNoticesSection
                heroSection
                if isSetupComplete {
                    dashboardSectionPicker
                } else if isSteamReady {
                    almostDoneSection
                }
                setupAssistantSection
                if isSetupComplete {
                    dashboardSectionContent
                } else if !isSteamReady {
                    setupLaunchHintSection
                    if showAdvancedSetupOptions {
                        steamWineSettingsSection
                        setupToolsGrid
                    } else {
                        newUserMaintenanceSection
                    }
                }
                if isSteamReady, let selectedProfile {
                    if isSetupComplete, dashboardSection != .launch {
                        selectedProfileCompactBar(selectedProfile)
                    } else {
                        selectedProfileSection(selectedProfile)
                    }
                }
                consoleSection
            }
            .padding(CosmosSpacing.contentPadding)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .cosmosContentBackground()
        .onChange(of: output) { _ in
            if !isSetupComplete, !consoleExpanded {
                consoleHasNewOutput = true
            }
        }
    }

    /// Tab navigation for the post-setup dashboard — one focus area at a time.
    private var dashboardSectionPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosmosDashboardTabBar(selection: $dashboardSection)

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
            maintenanceGrid
            storeExpansionSection
        case .bottles:
            bottlesSection
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heroTitle)
                .font(CosmosTypography.heroTitle)
                .foregroundStyle(CosmosGradients.heroTitle)
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

    /// Wine prefix + Steam are ready; unlocks the dashboard tabs.
    private var isSteamReady: Bool {
        setupRosettaReady
            && cosmosInstalled
            && steamSettings.isPrefixInitialized
            && steamSettings.isSteamInstalled
    }

    /// Saved profiles or Dock launchers exist.
    private var hasGameLaunchers: Bool {
        !profiles.isEmpty || cosmosAppCount > 0
    }

    private var isSetupComplete: Bool {
        isSteamReady && hasGameLaunchers
    }

    /// Rosetta is step 1 on Apple Silicon; Intel hosts skip it.
    private var setupIncludesRosetta: Bool {
        wineRuntime.needsRosetta
    }

    private var setupRosettaReady: Bool {
        !setupIncludesRosetta || wineRuntime.rosettaReady
    }

    private var setupStepTotal: Int {
        setupIncludesRosetta ? 5 : 4
    }

    private var setupProgress: Double {
        var completed = 0.0
        if setupRosettaReady { completed += 1 }
        if cosmosInstalled { completed += 1 }
        if steamSettings.isPrefixInitialized { completed += 1 }
        if steamSettings.isSteamInstalled { completed += 1 }
        if hasGameLaunchers { completed += 1 }
        return completed / Double(setupStepTotal)
    }

    private var setupStepNumber: Int {
        if setupIncludesRosetta && !wineRuntime.rosettaReady { return 1 }
        if !cosmosInstalled { return setupIncludesRosetta ? 2 : 1 }
        if !steamSettings.isPrefixInitialized { return setupIncludesRosetta ? 3 : 2 }
        if !steamSettings.isSteamInstalled { return setupIncludesRosetta ? 4 : 3 }
        if !hasGameLaunchers { return setupStepTotal }
        return setupStepTotal
    }

    /// Saved profiles that match a shipped curated YAML preset.
    private var installedCuratedProfiles: [GameProfile] {
        var seen = Set<String>()
        return profiles.compactMap { saved -> GameProfile? in
            guard let appid = saved.steamAppID, !appid.isEmpty,
                  let yaml = GameProfileStore.find(steamAppID: appid),
                  !seen.contains(appid) else {
                return nil
            }
            seen.insert(appid)
            return yaml
        }
    }

    private var setupPrimaryTitle: String {
        if setupIncludesRosetta && !wineRuntime.rosettaReady { return "Install Rosetta 2" }
        if !cosmosInstalled { return "Install Cosmos" }
        if !steamSettings.isPrefixInitialized { return "Prepare Steam Bottle" }
        if !steamSettings.isSteamInstalled { return "Install Steam" }
        if !hasGameLaunchers { return "Build Game Launchers" }
        return "Refresh Status"
    }

    private var setupPrimarySubtitle: String {
        if setupIncludesRosetta && !wineRuntime.rosettaReady {
            return "Required before x86_64 Wine can run on Apple Silicon · opens Terminal"
        }
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
        if !hasGameLaunchers {
            return "Detect installed games and create Dock-friendly .app launchers"
        }
        return "Update the checklist and sidebar"
    }

    private var setupPrimarySystemImage: String {
        if setupIncludesRosetta && !wineRuntime.rosettaReady { return "cpu" }
        if !cosmosInstalled { return "arrow.down.circle.fill" }
        if !steamSettings.isPrefixInitialized { return "externaldrive.fill.badge.checkmark" }
        if !steamSettings.isSteamInstalled { return "shippingbox.fill" }
        if !hasGameLaunchers { return "square.grid.2x2.fill" }
        return "arrow.clockwise"
    }

    private var heroSubtitle: String {
        if !isSetupComplete, selectedProfile == nil, selectedBottle == nil {
            return "Follow the setup guide below — one button per step. First-time setup takes about 10–15 minutes."
        }
        if let selectedProfile {
            if selectedProfileCanLaunch {
                return "Launch via \(selectedProfile.launchMethodLabel.lowercased())."
            }
            return "This profile has no launch path — edit its config file or pick another profile."
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
        if !hasGameLaunchers {
            return "Steam is ready — run Detect Games or Build Launchers to populate saved profiles."
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
                            Text("Step \(setupStepNumber) of \(setupStepTotal)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.cosmosPrimary)
                            Spacer()
                            Text("\(Int(setupProgress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: setupProgress)
                            .tint(Color.cosmosBright)
                            .scaleEffect(y: 1.35, anchor: .center)
                    }

                    prominentButton(
                        title: setupPrimaryTitle,
                        subtitle: setupPrimarySubtitle,
                        systemImage: setupPrimarySystemImage,
                        help: "Run the next recommended setup step (⌘⇧L)"
                    ) {
                        performNextSetupStep()
                    }

                    Text("Shortcut: ⌘⇧L continues setup · ⌘R refreshes status")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    CosmosNoticeBanner(
                        tint: .orange,
                        systemImage: "terminal.fill",
                        title: "Terminal steps",
                        message: "Most setup steps open Terminal for passwords or sudo. If a step fails, use Open Logs below before retrying — then press Refresh (⌘R)."
                    )

                    setupCompatibilityLookupSection

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
                            done: hasGameLaunchers,
                            title: "Build game launchers",
                            detail: hasGameLaunchers
                                ? launcherSummaryText
                                : "After you install a Windows game in Steam"
                        )
                    }

                    HStack(spacing: 12) {
                        Button {
                            runInTerminal(script: "setup.command", intent: .setup)
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
                .accessibilityLabel("First-time setup guide, step \(setupStepNumber) of \(setupStepTotal)")
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
            sectionHeader("While setup runs", systemImage: "play.circle")
            Text("Quick Launch and the full dashboard unlock once Steam is installed. Use the setup guide above for the next step.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Steam is ready but launchers are not — keep focus on the last setup step.
    private var almostDoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CosmosNoticeBanner(
                tint: Color.cosmosBright,
                systemImage: "gamecontroller.fill",
                title: "Almost there",
                message: "Steam is ready. Install a Windows game in Steam, then build launchers to finish setup and unlock the full dashboard tabs."
            )
            HStack(spacing: 10) {
                Button("Build Game Launchers") {
                    buildLaunchers()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                Button("Detect Games First") {
                    runCommand(
                        script: "detect_steam_games.command",
                        arguments: ["--list"],
                        environment: bottleEnvironment()
                    )
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)
            }
            .font(.subheadline)
        }
    }

    private var launcherSummaryText: String {
        var parts: [String] = []
        if !profiles.isEmpty {
            parts.append("\(profiles.count) profile\(profiles.count == 1 ? "" : "s")")
        }
        if cosmosAppCount > 0 {
            parts.append("\(cosmosAppCount) Dock app\(cosmosAppCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Launchers ready" : parts.joined(separator: " · ")
    }

    private var newUserMaintenanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $showAdvancedSetupOptions) {
                setupToolsGrid
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
            runInTerminal(script: "run.command", arguments: ["--install-rosetta"], intent: .setup)
            return
        }
        if !cosmosInstalled {
            runInTerminal(script: "install_cosmos.command", intent: .setup)
            return
        }
        if !steamSettings.isPrefixInitialized {
            runInTerminal(script: "run.command", arguments: ["--setup-steam"], intent: .setup)
            return
        }
        if !steamSettings.isSteamInstalled {
            runInTerminal(script: "run.command", arguments: ["--install-steam"], intent: .setup)
            return
        }
        if !hasGameLaunchers {
            buildLaunchers()
            return
        }
        refreshStatus(message: "Setup looks complete.")
    }

    /// Build Dock launchers in the embedded console (no Terminal unless sudo is required).
    private func buildLaunchers() {
        runCommand(
            script: "detect_steam_games.command",
            arguments: ["--install"],
            environment: steamLibraryEnvironment(),
            intent: .setup
        )
    }

    private func steamDetectionEnvironment() -> [String: String] {
        var env = bottleEnvironment()
        env["COSMOS_STEAM_SNAPSHOT"] = SteamLibraryMonitor.snapshotURL(bottleName: selectedBottle?.name).path
        return env
    }

    private func steamLibraryEnvironment(seedOnly: Bool = false) -> [String: String] {
        var env = steamDetectionEnvironment()
        env["COSMOS_ALLOW_USER_APPS"] = "1"
        if steamSettings.nativeSteamScanEnabled {
            env["COSMOS_STEAM_NATIVE_SCAN"] = "1"
        }
        if seedOnly {
            env["COSMOS_SYNC_SEED_ONLY"] = "1"
        } else {
            env["COSMOS_SYNC_FULL"] = "1"
        }
        return env
    }

    private func refreshSteamHealth() {
        guard !steamHealthInFlight else { return }
        steamHealthInFlight = true
        let env = bottleEnvironment()
        DispatchQueue.global(qos: .utility).async {
            let status = SteamHealthMonitor.load(environment: env) ?? .empty
            DispatchQueue.main.async {
                steamHealthInFlight = false
                steamHealth = status
            }
        }
    }

    private func checkGogLibraryForUnregistered() {
        guard isSteamReady, !isRunning, pendingTerminalJobID == nil else { return }
        guard let importScript = resolveScript("import_game.command") else { return }
        let env = bottleEnvironment()
        let configsDir = SavedProfileStore.configsDirectory()
        DispatchQueue.global(qos: .utility).async {
            guard let games = GogLibraryMonitor.listGames(importScript: importScript, environment: env) else { return }
            let missing = GogLibraryMonitor.unregistered(games: games, configsDirectory: configsDir)
            DispatchQueue.main.async {
                pendingUnregisteredGogGames = missing.count
            }
        }
    }

    private func syncGogLibrary(build: Bool, announce: Bool) {
        guard !isRunning, pendingTerminalJobID == nil else { return }
        guard let importScript = resolveScript("import_game.command") else { return }
        consoleExpanded = true
        isRunning = true
        let env = bottleEnvironment()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = GogLibraryMonitor.syncUnregistered(
                importScript: importScript,
                environment: env,
                build: build
            )
            DispatchQueue.main.async {
                isRunning = false
                applyGogLibrarySyncResult(result, build: build, announce: announce)
            }
        }
    }

    private func applyGogLibrarySyncResult(
        _ result: GogLibraryMonitor.SyncResult?,
        build: Bool,
        announce: Bool
    ) {
        guard let result else {
            if announce {
                showBanner(kind: .failure, message: "GOG sync failed — could not run import_game.command sync-gog.")
            }
            return
        }
        if !result.output.isEmpty {
            output = result.output + "\n\n" + output
        }
        pendingUnregisteredGogGames = max(0, pendingUnregisteredGogGames - result.newCount)
        refreshStatus()
        checkGogLibraryForUnregistered()
        guard announce else { return }
        if result.newCount > 0 {
            let built = build ? " Launchers built where possible." : ""
            showBanner(
                kind: .success,
                message: "Registered \(result.newCount) GOG game\(result.newCount == 1 ? "" : "s").\(built)"
            )
        } else {
            showBanner(kind: .info, message: "All detected GOG games already have launcher configs.")
        }
    }

    private func checkSteamLibraryForNewGames(autoSync: Bool, force: Bool = false) {
        guard isSteamReady, !isRunning, !steamLibraryCheckInFlight, pendingTerminalJobID == nil else { return }
        if !force,
           let lastSteamLibraryCheck,
           Date().timeIntervalSince(lastSteamLibraryCheck) < steamLibraryCheckInterval {
            return
        }

        guard let detectScript = resolveScript("detect_steam_games.command") else { return }
        let env = steamDetectionEnvironment()
        let bottleName = selectedBottle?.name
        let snapshotURL = SteamLibraryMonitor.snapshotURL(bottleName: bottleName)
        steamLibraryCheckInFlight = true
        DispatchQueue.global(qos: .utility).async {
            let games = SteamLibraryMonitor.listInstalledGames(detectScript: detectScript, environment: env)
            DispatchQueue.main.async {
                steamLibraryCheckInFlight = false
                lastSteamLibraryCheck = Date()
                guard let games else { return }

                pendingBrokenSteamInstalls = SteamLibraryMonitor.brokenInstalls(in: games).count

                let snapshotExists = FileManager.default.fileExists(atPath: snapshotURL.path)
                let snapshot = SteamLibraryMonitor.loadSnapshotAppIDs(bottleName: bottleName)
                let currentIDs = Set(games.map(\.appID))
                let newGames = SteamLibraryMonitor.newGames(comparedTo: snapshot, current: games)
                pendingRemovedSteamGames = snapshotExists ? snapshot.subtracting(currentIDs).count : 0

                if !snapshotExists {
                    pendingNewSteamGames = 0
                    if autoSync && isSetupComplete {
                        syncSteamLibrary(announce: false, seedOnly: true)
                    }
                    return
                }

                pendingNewSteamGames = newGames.count

                if autoSync && isSetupComplete {
                    if newGames.count > 0 || pendingRemovedSteamGames > 0 {
                        syncSteamLibrary(announce: false)
                    }
                    announceBrokenSteamInstallsIfNeeded()
                    return
                }

                if newGames.count > 0 {
                    showNewSteamGamesBanner(count: newGames.count)
                } else if pendingRemovedSteamGames > 0 {
                    showSteamCleanupBanner(count: pendingRemovedSteamGames)
                } else {
                    announceBrokenSteamInstallsIfNeeded()
                }
            }
        }
    }

    private func syncSteamLibrary(announce: Bool, seedOnly: Bool = false) {
        guard !isRunning, pendingTerminalJobID == nil else { return }
        if announce {
            runCommand(
                script: "detect_steam_games.command",
                arguments: ["--sync"],
                environment: steamLibraryEnvironment(seedOnly: seedOnly),
                intent: .setup
            )
            return
        }
        guard let detectScript = resolveScript("detect_steam_games.command") else { return }
        isRunning = true
        let env = steamLibraryEnvironment(seedOnly: seedOnly)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SteamLibraryMonitor.syncNewGames(detectScript: detectScript, environment: env)
            DispatchQueue.main.async {
                isRunning = false
                applySteamLibrarySyncResult(result, announce: false, seedOnly: seedOnly)
            }
        }
    }

    private func applySteamLibrarySyncResult(
        _ result: SteamLibraryMonitor.SyncResult?,
        announce: Bool,
        seedOnly: Bool
    ) {
        guard let result else {
            showSteamSyncFailureBanner(ifAnnounced: announce)
            return
        }

        if announce {
            output += result.output
        }

        guard result.succeeded else {
            showSteamSyncFailureBanner(ifAnnounced: announce)
            refreshStatus()
            return
        }

        if result.status == "seeded" {
            pendingNewSteamGames = 0
            if !seedOnly {
                refreshStatus(message: "Initialized Steam library tracking.")
            }
            return
        }

        if result.newCount > 0 {
            pendingNewSteamGames = 0
            pendingRemovedSteamGames = 0
            refreshStatus(message: "Synced \(result.newCount) new game(s).")
            if announce {
                showBanner(
                    kind: .success,
                    message: "Added \(result.newCount) new launcher\(result.newCount == 1 ? "" : "s") from Steam."
                )
            }
            return
        }

        if result.removedCount > 0 {
            pendingNewSteamGames = 0
            pendingRemovedSteamGames = 0
            refreshStatus(message: "Removed \(result.removedCount) uninstalled game(s).")
            if announce {
                let dockNote = " Dock apps in Cosmos Apps may need manual removal or a full rebuild."
                showBanner(
                    kind: .info,
                    message: "Removed \(result.removedCount) launcher config\(result.removedCount == 1 ? "" : "s") for uninstalled games.\(dockNote)"
                )
            }
            return
        }

        if pendingNewSteamGames > 0, announce {
            showBanner(
                kind: .info,
                message: "No new launchers were built — titles may already have curated configs or native-only installs."
            )
        }

        pendingNewSteamGames = 0
        pendingRemovedSteamGames = 0
        refreshStatus()
    }

    private func showSteamSyncFailureBanner(ifAnnounced announce: Bool) {
        if announce {
            showBanner(
                kind: .failure,
                message: "Steam library sync failed.",
                actions: steamSyncTerminalActions()
            )
        } else {
            showBanner(
                kind: .failure,
                message: "Background Steam library sync failed.",
                actions: [
                    CommandBannerAction(title: "Retry Sync", systemImage: "arrow.triangle.2.circlepath") {
                        syncSteamLibrary(announce: true)
                    },
                ]
            )
        }
    }

    private func showSteamCleanupBanner(count: Int) {
        showBanner(
            kind: .info,
            message: "\(count) uninstalled Steam game\(count == 1 ? "" : "s") detected.",
            actions: [
                CommandBannerAction(title: "Sync Library", systemImage: "arrow.triangle.2.circlepath") {
                    syncSteamLibrary(announce: true)
                },
            ]
        )
    }

    private func steamSyncTerminalActions() -> [CommandBannerAction] {
        [
            CommandBannerAction(title: "Run in Terminal", systemImage: "terminal.fill") {
                runInTerminal(
                    script: "detect_steam_games.command",
                    arguments: ["--sync"],
                    environment: steamLibraryEnvironment(),
                    intent: .setup
                )
            },
        ]
    }

    private func showNewSteamGamesBanner(count: Int) {
        showBanner(
            kind: .info,
            message: "\(count) new Steam game\(count == 1 ? "" : "s") detected.",
            actions: [
                CommandBannerAction(title: "Sync Launchers", systemImage: "arrow.triangle.2.circlepath") {
                    syncSteamLibrary(announce: true)
                },
                CommandBannerAction(title: "Build All", systemImage: "square.grid.2x2.fill") {
                    buildLaunchers()
                },
            ]
        )
    }

    private func announceBrokenSteamInstallsIfNeeded() {
        guard pendingBrokenSteamInstalls > 0,
              pendingBrokenSteamInstalls > lastWarnedBrokenSteamInstalls else { return }
        lastWarnedBrokenSteamInstalls = pendingBrokenSteamInstalls
        showBrokenSteamInstallsBanner(count: pendingBrokenSteamInstalls)
    }

    private func showBrokenSteamInstallsBanner(count: Int) {
        showBanner(
            kind: .failure,
            message: "\(count) Wine Steam install\(count == 1 ? "" : "s") missing a folder or game .exe.",
            actions: [
                CommandBannerAction(title: "Verify Library", systemImage: "checkmark.shield.fill") {
                    runCommand(script: "run.command", arguments: ["--verify-steam"], environment: bottleEnvironment())
                },
                CommandBannerAction(title: "Sync Launchers", systemImage: "arrow.triangle.2.circlepath") {
                    syncSteamLibrary(announce: true)
                },
            ]
        )
    }

    @ViewBuilder
    private var steamHealthNoticesSection: some View {
        if isSteamReady {
            VStack(alignment: .leading, spacing: 10) {
                if steamHealth.needsMingwForWrapper || steamHealth.needsWrapperInstall {
                    VStack(alignment: .leading, spacing: 8) {
                        CosmosNoticeBanner(
                            tint: .orange,
                            systemImage: "hammer.fill",
                            title: steamHealth.needsMingwForWrapper ? "mingw-w64 recommended" : "steamwebhelper wrapper missing",
                            message: steamHealth.needsMingwForWrapper
                                ? "Install Homebrew mingw-w64 so Cosmos can build the MIT steamwebhelper wrapper. Without it, Steam's store browser may be unstable."
                                : "Steam is installed but the CEF wrapper is not active. Install it to stabilize the store browser and login pages."
                        )
                        if steamHealth.needsWrapperInstall {
                            Button("Install Wrapper") {
                                runCommand(
                                    script: "repair.command",
                                    arguments: ["apply-fix", "install_steamwebhelper_wrapper"],
                                    environment: bottleEnvironment()
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRunning)
                            .font(.subheadline)
                        }
                    }
                }
                if steamHealth.hasBrokenInstalls || pendingBrokenSteamInstalls > 0 {
                    let broken = max(steamHealth.gamesBroken, pendingBrokenSteamInstalls)
                    VStack(alignment: .leading, spacing: 8) {
                        CosmosNoticeBanner(
                            tint: .orange,
                            systemImage: "exclamationmark.triangle.fill",
                            title: "Steam installs need attention",
                            message: "\(broken) Wine Steam game\(broken == 1 ? "" : "s") have a missing install folder or game .exe. Reinstall in Steam or verify the library."
                        )
                        HStack(spacing: 10) {
                            Button("Verify Library") {
                                runCommand(script: "run.command", arguments: ["--verify-steam"], environment: bottleEnvironment())
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRunning)
                            Button("Sync Launchers") {
                                syncSteamLibrary(announce: true)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                        }
                        .font(.subheadline)
                    }
                }
                if steamHealth.hasDualInstallWarning {
                    let ids = steamHealth.dualInstallAppIDs.prefix(6).joined(separator: ", ")
                    VStack(alignment: .leading, spacing: 8) {
                        CosmosNoticeBanner(
                            tint: .orange,
                            systemImage: "icloud.slash",
                            title: "Dual Steam installs",
                            message: "\(steamHealth.dualInstallCount) App ID(s) exist in both Wine Steam and native macOS Steam (\(ids)). Steam Cloud saves use different paths — pick one client per game."
                        )
                        Button("Open Setup Guide") {
                            openSetupHelp()
                        }
                        .buttonStyle(.bordered)
                        .font(.subheadline)
                    }
                }
                if steamHealth.hasCloudWarning {
                    VStack(alignment: .leading, spacing: 8) {
                        CosmosNoticeBanner(
                            tint: .orange,
                            systemImage: "icloud.and.arrow.up",
                            title: "Steam Cloud",
                            message: "Cloud sync issues were detected in recent Steam logs or userdata is missing."
                        )
                        HStack(spacing: 10) {
                            Button("Setup Guide") {
                                openSetupHelp()
                            }
                            .buttonStyle(.bordered)
                            .font(.subheadline)
                            Button("Diagnose") {
                                runCommand(script: "repair.command", arguments: ["diagnose"], environment: repairEnvironment())
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                            Button("Apply Cloud Fix") {
                                runCommand(
                                    script: "repair.command",
                                    arguments: ["apply-fix", "fix_steam_cloud_paths"],
                                    environment: repairEnvironment()
                                )
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                        }
                        .font(.subheadline)
                    }
                }
                if pendingUnregisteredGogGames > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        CosmosNoticeBanner(
                            tint: .blue,
                            systemImage: "opticaldisc.fill",
                            title: "GOG games ready to register",
                            message: "\(pendingUnregisteredGogGames) GOG install\(pendingUnregisteredGogGames == 1 ? "" : "s") found without launcher configs."
                        )
                        HStack(spacing: 10) {
                            Button("Register All") {
                                syncGogLibrary(build: false, announce: true)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRunning)
                            Button("Register + Build") {
                                syncGogLibrary(build: true, announce: true)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                            Button("List Games") {
                                runCommand(script: "import_game.command", arguments: ["list-gog"], environment: bottleEnvironment())
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    private var setupCompatibilityLookupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Check compatibility before you buy")
                .font(.subheadline.weight(.semibold))
            Text("Enter a Steam App ID to see curated status and community hints before installing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TextField("Steam App ID (e.g. 1145360)", text: $setupCompatAppID)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button("Lookup") {
                    let appid = setupCompatAppID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !appid.isEmpty else { return }
                    consoleExpanded = true
                    runCommand(script: "run.command", arguments: ["--compat-check", appid])
                    runCommand(
                        script: "cosmosdb.command",
                        arguments: ["badge", appid, "--json"],
                        chain: true
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || setupCompatAppID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Quick launch

    @ViewBuilder
    private var quickLaunchButtons: some View {
        prominentButton(
            title: launchSteamButtonTitle,
            subtitle: launchSteamButtonSubtitle,
            systemImage: wineRuntime.needsRosetta && !wineRuntime.rosettaReady ? "cpu" : "play.fill",
            disabled: !wineRuntime.canStartWineLaunch,
            help: launchSteamButtonHelp
        ) {
            launchSteamFromDashboard()
        }

        prominentButton(
            title: "Launch Profile",
            subtitle: selectedProfileLaunchSubtitle,
            systemImage: "gamecontroller.fill",
            disabled: !selectedProfileCanLaunch || !wineRuntime.canStartWineLaunch,
            help: selectedProfileLaunchHelp
        ) {
            guard let selectedProfile else { return }
            launchProfile(selectedProfile)
        }
    }

    /// Launch a saved profile's game executable through the Wine shell flow.
    /// Shared by the Quick Launch button and the sidebar context menu.
    private func launchProfile(_ profile: SavedProfile) {
        guard profile.canLaunchFromDashboard else { return }
        guard ensureRosettaForWineLaunch() else { return }
        if let appid = profile.steamAppID,
           let yaml = GameProfileStore.find(steamAppID: appid),
           yaml.isBlocked {
            pendingBlockedLaunch = profile
            return
        }
        launchProfileUnchecked(profile)
    }

    private func launchProfileUnchecked(_ profile: SavedProfile) {
        guard profile.canLaunchFromDashboard else { return }
        guard ensureRosettaForWineLaunch() else { return }
        profilePreferences = ProfilePreferencesStore.recordRecentLaunch(profileID: profile.id)
        if !profile.path.isEmpty {
            runCommand(
                script: "run.command",
                arguments: ["--game", profile.path] + ShellArgumentParser.parse(profile.args),
                environment: dashboardLaunchEnvironment(),
                intent: .gameLaunch
            )
            return
        }
        guard let appid = profile.steamAppID, !appid.isEmpty else { return }
        var env = bottleEnvironment()
        env["STEAM_GAME_ID"] = appid
        if !profile.args.isEmpty {
            env["STEAM_GAME_ARGS"] = profile.args
        }
        runCommand(
            script: "run.command",
            arguments: ["--steam"],
            environment: dashboardLaunchEnvironment(extra: env),
            intent: .gameLaunch
        )
    }

    private var launchSteamButtonTitle: String {
        wineRuntime.needsRosetta && !wineRuntime.rosettaReady ? "Install Rosetta 2" : "Launch Steam"
    }

    private var launchSteamButtonSubtitle: String {
        if wineRuntime.needsRosetta && !wineRuntime.rosettaReady {
            return "Required before x86_64 Wine can run · opens Terminal"
        }
        return "Open Steam in the bottle"
    }

    private var launchSteamButtonHelp: String {
        if wineRuntime.needsRosetta && !wineRuntime.rosettaReady {
            return "Install Rosetta 2 so Wine can run on Apple Silicon (may ask for your password)"
        }
        return "Start Steam in the default Wine prefix"
    }

    /// Rosetta install needs Terminal for sudo; game/Steam launch needs Rosetta on Apple Silicon.
    @discardableResult
    private func ensureRosettaForWineLaunch() -> Bool {
        guard wineRuntime.needsRosetta, !wineRuntime.rosettaReady else { return true }
        runInTerminal(script: "run.command", arguments: ["--install-rosetta"])
        return false
    }

    private func launchSteamFromDashboard() {
        if wineRuntime.needsRosetta, !wineRuntime.rosettaReady {
            runInTerminal(script: "run.command", arguments: ["--install-rosetta"])
            return
        }
        runCommand(
            script: "run.command",
            arguments: ["--steam"],
            environment: dashboardLaunchEnvironment(),
            intent: .gameLaunch
        )
    }

    private func applyInstalledCuratedProfiles() {
        runCommand(
            script: "profile.command",
            arguments: ["apply-installed"],
            environment: bottleEnvironment()
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
        if profile.canLaunchFromDashboard {
            parts.append(profile.launchMethodLabel)
            if !profile.path.isEmpty {
                parts.append(profile.path)
            } else if let appid = profile.steamAppID {
                parts.append("App ID \(appid)")
            }
        } else {
            parts.append("Not configured")
        }
        return parts.joined(separator: ". ")
    }

    private func profileSubtitle(_ profile: SavedProfile) -> String {
        if !profile.args.isEmpty { return profile.args }
        if !profile.path.isEmpty { return profile.path }
        if let appid = profile.steamAppID, !appid.isEmpty {
            return "Steam App ID \(appid)"
        }
        return profile.launchMethodLabel
    }

    /// Reveal a file in Finder, selecting it in its enclosing folder.
    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private var wineRuntimeSection: some View {
        Group {
            if wineRuntime.needsRosetta && !wineRuntime.rosettaReady {
                CosmosNoticeBanner(
                    tint: .orange,
                    systemImage: "cpu",
                    title: "Rosetta 2 required",
                    message: "Cosmos downloads x86_64 Wine builds from Gcenx. Apple Silicon Macs need Rosetta 2 before Wine can run. Install Rosetta, then continue setup."
                )
            } else if !wineRuntime.wineInstalled {
                CosmosNoticeBanner(
                    tint: Color.cosmosPrimary,
                    systemImage: "wineglass",
                    title: "Wine not downloaded yet",
                    message: "Run Prepare Steam bottle to download Wine \(wineRuntime.wineVersion). \(wineRuntime.translationNote)"
                )
            }
        }
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

            if let bottle = selectedBottle {
                CosmosNoticeBanner(
                    tint: .blue,
                    systemImage: "cylinder.split.1x2.fill",
                    title: "Launches use bottle: \(bottle.name)",
                    message: "Settings in this section apply to the default Steam prefix. Adjust \(bottle.name) under the Bottles tab, or clear the bottle selection in the toolbar to use defaults."
                )
            } else {
                Text("These apply to the default Steam prefix on the next launch. Use the Bottles tab for extra isolated prefixes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                        .accessibilityLabel("Graphics backend")
                        .accessibilityValue(steamSettings.backend)
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
                        .accessibilityLabel("Windows version")
                        .accessibilityValue(steamSettings.windowsVersion.isEmpty ? "Wine default" : steamSettings.windowsVersion)
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

                Toggle(isOn: steamNativeScanBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan native Steam libraries")
                            .font(.subheadline.weight(.medium))
                        Text("Also detect games installed in macOS Steam. Warns when the same App ID exists in both Wine and native Steam (Steam Cloud path conflicts).")
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
                    detailRow(title: "Mac", value: "\(wineRuntime.platformDisplayName) (\(wineRuntime.chipArchitecture))")
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
            let message = SettingLabels.savedMessage(for: key, appliesToSteam: false)
            output = "Saved \(key)=\(value)\n\n" + output
            showBanner(kind: .success, message: message)
        } catch {
            let label = SettingLabels.displayName(for: key)
            let message = "Could not save \(label): \(error.localizedDescription)"
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
            environment: dashboardLaunchEnvironment(extra: [
                "GPTK_PATH": path,
                "COSMOS_BACKEND": "d3dmetal",
            ])
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

    private var steamNativeScanBinding: Binding<Bool> {
        Binding(
            get: { steamSettings.nativeSteamScanEnabled },
            set: {
                applySteamSetting(key: "COSMOS_STEAM_NATIVE_SCAN", value: $0 ? "1" : "0")
                refreshSteamHealth()
            }
        )
    }

    private func applySteamSetting(key: String, value: String) {
        do {
            try SteamSettingsStore.set(key: key, value: value)
            steamSettings = SteamSettingsStore.load()
            let message = SettingLabels.savedMessage(for: key)
            output = "Saved \(key)=\(value)\n\n" + output
            showBanner(kind: .success, message: message)
        } catch {
            let label = SettingLabels.displayName(for: key)
            let message = "Could not save \(label): \(error.localizedDescription)"
            output = message + "\n\n" + output
            showBanner(kind: .failure, message: message)
        }
    }

    @ViewBuilder
    private var gameDiscoveryButtons: some View {
        secondaryButton(title: "Detect Games", subtitle: "List Steam library", systemImage: "magnifyingglass", help: "Scan the Steam library and list installable titles in the output pane") {
            runCommand(script: "detect_steam_games.command", arguments: ["--list"], environment: bottleEnvironment())
        }

        secondaryButton(title: "Verify Detection", subtitle: "Check install folders", systemImage: "checkmark.shield.fill", help: "List games and verify each installdir exists on disk") {
            runCommand(script: "detect_steam_games.command", arguments: ["--verify"], environment: bottleEnvironment())
        }

        secondaryButton(title: "Build Launchers", subtitle: "Detect → Dock apps", systemImage: "square.grid.2x2.fill", help: "Detect games and install Spotlight launchers into Cosmos Apps") {
            buildLaunchers()
        }

        if pendingBrokenSteamInstalls > 0 {
            secondaryButton(
                title: "Verify Broken Installs",
                subtitle: "\(pendingBrokenSteamInstalls) need attention",
                systemImage: "exclamationmark.triangle.fill",
                help: "List Wine Steam games with missing install folders or game executables"
            ) {
                runCommand(script: "run.command", arguments: ["--verify-steam"], environment: bottleEnvironment())
            }
        } else if pendingNewSteamGames > 0 {
            secondaryButton(
                title: "Sync New Games",
                subtitle: "\(pendingNewSteamGames) detected",
                systemImage: "arrow.triangle.2.circlepath",
                help: "Build launchers for newly installed Steam games only"
            ) {
                syncSteamLibrary(announce: true)
            }
        } else {
            secondaryButton(
                title: "Sync Steam Library",
                subtitle: "New installs only",
                systemImage: "arrow.triangle.2.circlepath",
                help: "Build launchers for newly installed Steam games since the last sync"
            ) {
                syncSteamLibrary(announce: true)
            }
        }

        if pendingUnregisteredGogGames > 0 {
            secondaryButton(
                title: "Register GOG Games",
                subtitle: "\(pendingUnregisteredGogGames) unregistered",
                systemImage: "opticaldisc.fill",
                help: "Create launcher configs for detected GOG installs"
            ) {
                syncGogLibrary(build: false, announce: true)
            }
        }
    }

    // MARK: - Setup tools (first-time, advanced options)

    private var setupToolsGrid: some View {
        CosmosSection(title: "Optional tools", systemImage: "wrench.and.screwdriver") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: CosmosSpacing.gridColumnMin), spacing: CosmosSpacing.gridGap)],
                spacing: CosmosSpacing.gridGap
            ) {
                gameDiscoveryButtons
                secondaryButton(title: "Profiles Folder", subtitle: "Open in Finder", systemImage: "folder.fill", help: "Reveal saved game profiles in Finder") {
                    runCommand(script: "run.command", arguments: ["--profiles"])
                }
                secondaryButton(title: "Open Logs", subtitle: "Latest launch log", systemImage: "doc.text.magnifyingglass", help: "Open the most recent launch log for troubleshooting") {
                    runCommand(script: "run.command", arguments: ["--logs"])
                }
            }
        }
    }

    // MARK: - Maintenance grid (post-setup Tools tab)

    private var maintenanceGrid: some View {
        CosmosSection(title: "Maintenance", systemImage: "wrench.and.screwdriver.fill") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: CosmosSpacing.gridColumnMin), spacing: CosmosSpacing.gridGap)],
                spacing: CosmosSpacing.gridGap
            ) {
                gameDiscoveryButtons

                if !installedCuratedProfiles.isEmpty {
                    secondaryButton(
                        title: "Apply Curated Profiles",
                        subtitle: "\(installedCuratedProfiles.count) installed title\(installedCuratedProfiles.count == 1 ? "" : "s")",
                        systemImage: "arrow.down.circle.fill",
                        help: "Batch-apply shipped YAML presets (overrides, deps, fixes) for detected games"
                    ) {
                        applyInstalledCuratedProfiles()
                    }
                }

                secondaryButton(title: "Profiles Folder", subtitle: "Open in Finder", systemImage: "folder.fill", help: "Reveal saved game profiles in Finder") {
                    runCommand(script: "run.command", arguments: ["--profiles"])
                }

                secondaryButton(title: "Open Logs", subtitle: "Latest launch log", systemImage: "doc.text.magnifyingglass", help: "Open the most recent launch log for troubleshooting") {
                    runCommand(script: "run.command", arguments: ["--logs"])
                }

                secondaryButton(title: "Check for Updates", subtitle: "GitHub Releases", systemImage: "arrow.down.circle", help: "Compare your Cosmos version to the latest published release") {
                    checkForUpdates()
                }

                if updateAvailable {
                    secondaryButton(
                        title: "Install Update",
                        subtitle: "Download Cosmos.dmg",
                        systemImage: "arrow.down.to.line",
                        help: "Download the latest release and install Cosmos.app to /Applications"
                    ) {
                        installUpdate()
                    }
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
                runCommand(script: "run.command", arguments: ["--reset-bottle", "--force"], intent: .setup)
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("No curated game profiles are bundled with this build.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Button("Check for Updates") {
                        checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunning)
                }
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
        CosmosFilterChip(
            label: filter.label,
            isSelected: curatedProfileFilter == filter
        ) {
            curatedProfileFilter = filter
            if let id = selectedGameProfileID,
               !filteredGameProfiles.contains(where: { $0.id == id }) {
                selectedGameProfileID = nil
            }
        }
        .disabled(isRunning)
        .accessibilityLabel("\(filter.label) filter")
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
                CosmosCompatBadge(status: profile.statusLabel)
            }

            if profile.isBlocked {
                CosmosNoticeBanner(
                    tint: .red,
                    systemImage: "exclamationmark.octagon.fill",
                    title: "Blocked on macOS",
                    message: profile.blockedLaunchMessage
                )
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
                        environment: repairEnvironment(),
                        intent: .diagnose
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
                        environment: repairEnvironment(),
                        intent: .diagnose
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
                    title: "Find EXE",
                    subtitle: "Detect main binary",
                    systemImage: "magnifyingglass",
                    script: "import_game.command",
                    arguments: ["find-exe"],
                    needsPath: true,
                    pathPrompt: "Install folder (drive_c/GOG Games/Title or host path)"
                )
                storeActionButton(
                    title: "Register EXE",
                    subtitle: "Already installed",
                    systemImage: "app.badge.checkmark.fill",
                    script: "import_game.command",
                    arguments: ["add-exe"],
                    needsPath: true,
                    pathPrompt: "Game .exe path or install folder"
                )
                storeActionButton(
                    title: "GOG Game",
                    subtitle: "Setup, slug, or folder",
                    systemImage: "opticaldisc.fill",
                    script: "import_game.command",
                    arguments: ["add-gog"],
                    needsStoreTitle: true,
                    pathPrompt: "GOG setup.exe, list-gog slug, or install folder"
                )
                storeActionButton(
                    title: "List GOG Games",
                    subtitle: "Detected in prefix",
                    systemImage: "list.bullet.rectangle",
                    script: "import_game.command",
                    arguments: ["list-gog"]
                )
                storeActionButton(
                    title: "Sync GOG Games",
                    subtitle: "Register + build launchers",
                    systemImage: "arrow.triangle.2.circlepath",
                    script: "import_game.command",
                    arguments: ["sync-gog", "--build"]
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

            HStack(spacing: 10) {
                Text("After importing, run Build Launchers to create Dock icons from the dashboard.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Build Launchers") {
                    buildLaunchers()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRunning)
            }
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
                    message: arguments.contains("add-gog")
                        ? "GOG offline installer (.exe) opens Terminal. For an already-installed game, enter a list-gog slug or drive_c/... path — registration runs in the console below."
                        : "Provide the file or folder path and a display name for the Cosmos launcher.",
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
                    submitLabel: arguments.contains("add-gog") ? "Import" : "Run in Terminal",
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

        let lowerPath = path.lowercased()
        let gogRegisterOnly = request.baseArguments.contains("add-gog")
            && (!lowerPath.hasSuffix(".exe") || path.hasPrefix("drive_c/"))
        if gogRegisterOnly || !request.forceTerminal {
            runCommand(script: request.script, arguments: args, environment: bottleEnvironment())
        } else {
            runInTerminal(script: request.script, arguments: args, environment: bottleEnvironment())
        }
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

                    if let profile = selectedGameProfile, profile.store == "gog", let slug = activeGogSlug {
                        Button {
                            runCommand(
                                script: "profile.command",
                                arguments: ["for-gog-slug", slug, "apply"],
                                environment: bottleEnvironment()
                            )
                        } label: {
                            Label("Apply GOG Profile", systemImage: "doc.text.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning)
                    } else if selectedGameProfile != nil {
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
            } else if let slug = activeGogSlug, let profile = selectedGameProfile ?? GameProfileStore.find(gogSlug: slug) {
                detailRow(title: "GOG slug", value: slug)
                if profile.store == "gog" {
                    CosmosCompatBadge(status: profile.statusLabel)
                }
                Button {
                    runCommand(
                        script: "profile.command",
                        arguments: ["for-gog-slug", slug, "apply"],
                        environment: bottleEnvironment()
                    )
                } label: {
                    Label("Apply GOG Profile", systemImage: "doc.text.fill")
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)
                if !profile.steamAppID.isEmpty {
                    Text("Steam App ID \(profile.steamAppID) — use a Steam launcher profile for CosmosDB lookup.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Select a saved launcher or curated YAML profile (Steam App ID or GOG slug) to look up or apply compatibility settings.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .onChange(of: activeSteamAppID) { _ in refreshCompatBadge() }
        .onChange(of: selectedGameProfileID) { _ in refreshCompatBadge() }
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
                    runCommand(
                        script: "bottle.command",
                        arguments: ["launch", bottle.name, "--steam"],
                        environment: dashboardLaunchEnvironment(),
                        intent: .gameLaunch
                    )
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

    private func selectedProfileCompactBar(_ profile: SavedProfile) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(profile.launchMethodLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let badge = sidebarCompatBadge(for: profile) {
                CosmosCompatBadge(status: badge.status, compact: true)
            }
            Spacer(minLength: 8)
            Button("Show Details") {
                dashboardSection = .launch
            }
            .buttonStyle(.bordered)
            Button("Launch") {
                launchProfile(profile)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!profile.canLaunchFromDashboard || !wineRuntime.canStartWineLaunch || isRunning)
        }
        .cosmosCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected launcher \(profile.name)")
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
                detailRow(title: "Launch method", value: profile.launchMethodLabel)
                if !profile.path.isEmpty {
                    Divider()
                    detailRow(title: "Executable", value: profile.path)
                }
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
        if wineRuntime.needsRosetta, !wineRuntime.rosettaReady {
            return "Install Rosetta 2 first"
        }
        guard let selectedProfile else { return "Select a profile first" }
        return selectedProfileCanLaunch
            ? selectedProfile.launchMethodLabel
            : "Configure executable or Steam App ID"
    }

    private var selectedProfileLaunchHelp: String {
        if wineRuntime.needsRosetta, !wineRuntime.rosettaReady {
            return "Install Rosetta 2 before launching Wine games on Apple Silicon"
        }
        if selectedProfileCanLaunch {
            return "Launch the selected profile (\(selectedProfile?.launchMethodLabel.lowercased() ?? ""))"
        }
        return "Select a profile with a launch path or Steam App ID in the sidebar"
    }

    private var selectedProfileCanLaunch: Bool {
        selectedProfile?.canLaunchFromDashboard == true
    }

    // MARK: - Console

    private var consoleSection: some View {
        Group {
            if isSetupComplete {
                consoleOutputPanel
            } else {
                DisclosureGroup(isExpanded: $consoleExpanded) {
                    consoleOutputPanel
                        .onAppear { consoleHasNewOutput = false }
                } label: {
                    HStack(spacing: 8) {
                        Label("Technical output", systemImage: "terminal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.cosmosPrimary)
                        if consoleHasNewOutput && !consoleExpanded {
                            Text("Updated")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .onChange(of: consoleExpanded) { expanded in
                    if expanded { consoleHasNewOutput = false }
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
                CosmosConsolePanel(minHeight: isSetupComplete ? 220 : 140) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(output)
                                .font(CosmosTypography.monoBody)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .foregroundStyle(Color.cosmosConsoleText)
                            Color.clear
                                .frame(height: 1)
                                .id(consoleBottomID)
                        }
                        .padding(16)
                    }
                }
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
        VStack(alignment: .leading, spacing: CosmosSpacing.sectionInner) {
            CosmosNoticeBanner(
                tint: .green,
                systemImage: "party.popper.fill",
                title: "Setup complete",
                message: setupCompleteBannerMessage,
                onDismiss: { showSetupCompleteBanner = false }
            )
            if !installedCuratedProfiles.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        applyInstalledCuratedProfiles()
                    } label: {
                        Label(
                            "Apply Curated Profiles (\(installedCuratedProfiles.count))",
                            systemImage: "arrow.down.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                    .help("Export overrides and run safe profile fixes for games in your library")
                }
            }
        }
    }

    private var setupCompleteBannerMessage: String {
        var message = "Launch Steam or pick a saved profile in the sidebar. Game launchers are in /Applications/Cosmos Apps."
        if !installedCuratedProfiles.isEmpty {
            message += " \(installedCuratedProfiles.count) installed title\(installedCuratedProfiles.count == 1 ? "" : "s") have curated Cosmos presets — apply them for known-good backends and fixes."
        }
        return message
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
                label: hasGameLaunchers ? launcherSummaryText : "No launchers yet",
                icon: "gamecontroller.fill",
                color: hasGameLaunchers ? Color.cosmosPrimary.opacity(0.8) : Color.secondary
            )
            if pendingNewSteamGames > 0, isSetupComplete {
                Button {
                    syncSteamLibrary(announce: true)
                } label: {
                    statusRow(
                        label: "\(pendingNewSteamGames) new Steam game\(pendingNewSteamGames == 1 ? "" : "s") — tap to sync",
                        icon: "arrow.triangle.2.circlepath",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .help("Build launchers for newly installed Steam games")
            } else if pendingRemovedSteamGames > 0, isSetupComplete {
                Button {
                    syncSteamLibrary(announce: true)
                } label: {
                    statusRow(
                        label: "\(pendingRemovedSteamGames) uninstalled — tap to clean up",
                        icon: "trash.circle",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .help("Remove launcher configs for uninstalled Steam games")
            } else if pendingBrokenSteamInstalls > 0, isSetupComplete {
                Button {
                    runCommand(script: "run.command", arguments: ["--verify-steam"], environment: bottleEnvironment())
                } label: {
                    statusRow(
                        label: "\(pendingBrokenSteamInstalls) broken install\(pendingBrokenSteamInstalls == 1 ? "" : "s") — tap to verify",
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .help("Verify Wine Steam install folders and game executables")
            } else if pendingUnregisteredGogGames > 0, isSetupComplete {
                Button {
                    syncGogLibrary(build: false, announce: true)
                } label: {
                    statusRow(
                        label: "\(pendingUnregisteredGogGames) GOG game\(pendingUnregisteredGogGames == 1 ? "" : "s") — tap to register",
                        icon: "opticaldisc.fill",
                        color: .blue
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .help("Register detected GOG installs as launcher configs")
            }
            statusRow(
                label: bottles.isEmpty
                    ? "No bottles yet"
                    : "\(bottles.count) bottle\(bottles.count == 1 ? "" : "s")",
                icon: "cylinder.split.1x2.fill",
                color: bottles.isEmpty ? Color.secondary : Color.cosmosPrimary.opacity(0.8)
            )
        }
        .font(.subheadline)
        .accessibilityElement(children: .contain)
    }

    private func statusRow(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(label)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
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
            .background(Color.cosmosTileFill, in: RoundedRectangle(cornerRadius: CosmosSpacing.buttonRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CosmosSpacing.buttonRadius)
                    .strokeBorder(
                        destructive ? Color.red.opacity(0.25) : Color.cosmosCardBorder,
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
        cosmosInstalled = SavedProfileStore.cosmosAppsIsInstalled()
        cosmosAppCount = SavedProfileStore.countCosmosApps()
        steamSettings = SteamSettingsStore.load()
        reloadGraphicsSettings()
        wineRuntime = WineRuntimeStore.load(wineVersion: steamSettings.wineVersion)
        profiles = SavedProfileStore.load()
        profilePreferences = ProfilePreferencesStore.prune(validProfileIDs: Set(profiles.map(\.id)))
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
        refreshSteamHealth()
        checkGogLibraryForUnregistered()
        appState.updateSetupComplete(isSetupComplete)

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

    /// Pass the selected bottle into CLI tools that honor COSMOS_BOTTLE / WINEPREFIX.
    private func bottleEnvironment() -> [String: String] {
        guard let bottle = selectedBottle else { return [:] }
        return [
            "COSMOS_BOTTLE": bottle.name,
            "WINEPREFIX": bottle.prefixURL.path,
        ]
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
    // confirmations — which the piped Process runner cannot provide. Commands are
    // wrapped with scripts/terminal_wrap.sh so exit status is written back for the app.
    private func runInTerminal(
        script: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        intent: CommandIntent = .general
    ) {
        guard let scriptURL = resolveScript(script) else {
            let message = "Script not found or not executable: \(script)"
            output = message
            showBanner(kind: .failure, message: message)
            return
        }
        guard let wrapURL = resolveScript("scripts/terminal_wrap.sh") else {
            let message = "Terminal wrapper not found: scripts/terminal_wrap.sh"
            output = message
            showBanner(kind: .failure, message: message)
            return
        }

        let displayed = ([script] + arguments).joined(separator: " ")
        let jobID = TerminalJobTracker.makeJobID()
        pendingTerminalJobID = jobID
        TerminalJobTracker.saveTrackedJob(id: jobID, label: displayed)
        do {
            try TerminalJobTracker.prepareJobsDirectory()
            TerminalJobTracker.cleanup(jobID: jobID)
        } catch {
            let message = "Could not prepare Terminal job directory: \(error.localizedDescription)"
            output = message
            showBanner(kind: .failure, message: message)
            return
        }

        var innerParts: [String] = []
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            innerParts.append("export \(key)=\(ShellArgumentParser.shellQuote(value))")
        }
        innerParts.append(([scriptURL.path] + arguments).map(ShellArgumentParser.shellQuote).joined(separator: " "))
        let innerCommand = innerParts.joined(separator: "; ")
        let shellCommand = TerminalJobTracker.wrappedShellCommand(
            jobID: jobID,
            wrapScriptPath: wrapURL.path,
            innerCommand: innerCommand,
            label: displayed
        )

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
            output = """
            Opened Terminal to run: \(displayed)

            Complete any password or confirmation prompts in the Terminal window. \
            Cosmos will report the exit status when the command finishes.
            """
            showBanner(
                kind: .info,
                message: "Running in Terminal — exit status will appear here when finished.",
                actions: [
                    CommandBannerAction(title: "Check Status", systemImage: "list.bullet.rectangle") {
                        runCommand(script: "run.command", arguments: ["--status"])
                    },
                    CommandBannerAction(title: "Open Logs", systemImage: "doc.text.magnifyingglass") {
                        openLatestLogs()
                    },
                ]
            )
            watchTerminalJob(jobID: jobID, displayedCommand: displayed, intent: intent)
        } catch {
            pendingTerminalJobID = nil
            TerminalJobTracker.clearTrackedJob()
            let message = "Could not open Terminal: \(error.localizedDescription)"
            output = message
            showBanner(kind: .failure, message: message)
        }
    }

    private func watchTerminalJob(jobID: String, displayedCommand: String, intent: CommandIntent) {
        TerminalJobTracker.cancelPoll(jobID: jobID)
        TerminalJobTracker.poll(jobID: jobID) { exitCode in
            deliverTerminalJobResult(
                jobID: jobID,
                displayedCommand: displayedCommand,
                exitCode: exitCode,
                intent: intent,
                autoContinueSetup: true
            )
        }
    }

    private func resumeTerminalJobs() {
        guard pendingTerminalJobID == nil else { return }

        if let tracked = TerminalJobTracker.loadTrackedJob() {
            if let exitCode = TerminalJobTracker.readExitCode(jobID: tracked.id) {
                deliverTerminalJobResult(
                    jobID: tracked.id,
                    displayedCommand: tracked.label,
                    exitCode: exitCode,
                    intent: .setup,
                    autoContinueSetup: true
                )
                return
            }
            pendingTerminalJobID = tracked.id
            watchTerminalJob(jobID: tracked.id, displayedCommand: tracked.label, intent: .setup)
            return
        }

        for completed in TerminalJobTracker.completedJobsAwaitingDelivery() {
            deliverTerminalJobResult(
                jobID: completed.id,
                displayedCommand: completed.label,
                exitCode: completed.exitCode,
                intent: .setup,
                autoContinueSetup: false
            )
        }
    }

    private func deliverTerminalJobResult(
        jobID: String,
        displayedCommand: String,
        exitCode: Int?,
        intent: CommandIntent,
        autoContinueSetup: Bool
    ) {
        if let pendingTerminalJobID, pendingTerminalJobID != jobID {
            return
        }
        guard TerminalJobTracker.claimDelivery(jobID: jobID) else { return }
        pendingTerminalJobID = nil
        TerminalJobTracker.cancelPoll(jobID: jobID)
        defer {
            TerminalJobTracker.cleanup(jobID: jobID)
            TerminalJobTracker.clearTrackedJob()
        }

        guard let exitCode else {
            output += "\n\nTimed out waiting for Terminal command: \(displayedCommand)"
            showBanner(
                kind: .info,
                message: "Still running in Terminal — refresh status (⌘R) when finished.",
                actions: failureRecoveryActions(includeLogs: intent == .setup)
            )
            return
        }

        let succeeded = exitCode == 0
        output += succeeded
            ? "\n\nTerminal command finished successfully: \(displayedCommand)"
            : "\n\nTerminal command exited with status \(exitCode): \(displayedCommand)"
        refreshStatus()
        if succeeded {
            var actions: [CommandBannerAction] = []
            if autoContinueSetup, intent == .setup, !isSetupComplete {
                actions.append(
                    CommandBannerAction(title: "Continue Setup", systemImage: "arrow.right.circle") {
                        performNextSetupStep()
                    }
                )
            }
            showBanner(kind: .success, message: successMessage(for: intent), actions: actions)
        } else {
            consoleExpanded = true
            let failureMessage = CommandOutputParser.failureMessage(
                exitCode: Int32(exitCode),
                intent: intent,
                output: output
            )
            showBanner(
                kind: .failure,
                message: failureMessage,
                actions: failureRecoveryActions(includeLogs: intent == .setup)
            )
        }
    }

    private func checkForUpdatesSilently() {
        guard let scriptURL = resolveScript("run.command") else { return }
        DispatchQueue.global(qos: .utility).async {
            let status = UpdateChecker.check(runScript: scriptURL)
            DispatchQueue.main.async {
                applyUpdateCheck(status, verbose: false)
            }
        }
    }

    private func checkForUpdates() {
        guard let scriptURL = resolveScript("run.command") else {
            showBanner(kind: .failure, message: "Script not found: run.command")
            return
        }

        beginCommandOutput()
        output = "Running: run.command --check-update\n\n"
        isRunning = true

        DispatchQueue.global(qos: .userInitiated).async {
            let status = UpdateChecker.check(runScript: scriptURL)
            DispatchQueue.main.async {
                isRunning = false
                if let status {
                    output += "app_version=\(status.appVersion)\n"
                    output += "runtime_version=\(status.runtimeVersion)\n"
                    if let latest = status.latestRelease {
                        output += "latest_release=\(latest)\n"
                    }
                    output += "status=\(status.state.rawValue)\n"
                } else {
                    output += "Update check failed.\n"
                }
                applyUpdateCheck(status, verbose: true)
            }
        }
    }

    private func applyUpdateCheck(_ status: UpdateChecker.Status?, verbose: Bool) {
        guard let status else {
            if verbose {
                showBanner(kind: .failure, message: "Update check failed.")
            }
            return
        }

        updateAvailable = status.updateAvailable
        guard status.updateAvailable else {
            if verbose {
                showBanner(kind: .success, message: "Cosmos is up to date (\(status.appVersion)).")
            }
            return
        }

        let latest = status.latestRelease ?? "newer"
        let message = "Cosmos \(latest) is available (you are on \(status.appVersion))."
        if verbose {
            output += "\nUpdate available."
        }
        showBanner(
            kind: .info,
            message: message,
            actions: [
                CommandBannerAction(title: "Install Update", systemImage: "arrow.down.to.line") {
                    installUpdate()
                },
            ]
        )
    }

    private func installUpdate() {
        runCommand(script: "run.command", arguments: ["--install-update"], intent: .setup)
    }

    private func showBanner(
        kind: CommandBannerKind,
        message: String,
        actions: [CommandBannerAction] = []
    ) {
        commandBannerQueue.enqueue(
            CommandBanner(kind: kind, message: message, actions: actions)
        )
    }

    private func dismissCommandBanner() {
        commandBannerQueue.dismissCurrent()
    }

    private func successMessage(for intent: CommandIntent) -> String {
        switch intent {
        case .gameLaunch:
            return "Launch finished. If the game or Steam did not appear, open Logs or run Diagnose."
        case .diagnose:
            return CommandOutputParser.applySuggestedSummary(from: output)
                ?? CommandOutputParser.diagnoseSummary(from: output)
                ?? "Diagnosis complete — see output below."
        case .setup:
            return "Setup step finished successfully."
        case .general:
            return "Command finished successfully."
        }
    }

    private func openLatestLogs() {
        runCommand(script: "run.command", arguments: ["--logs"])
    }

    private func failureRecoveryActions(includeLogs: Bool, includeRepair: Bool = false) -> [CommandBannerAction] {
        var actions: [CommandBannerAction] = []
        if includeRepair {
            actions.append(
                CommandBannerAction(title: "Apply Suggested", systemImage: "wand.and.stars") {
                    runCommand(
                        script: "repair.command",
                        arguments: ["apply-suggested"],
                        environment: repairEnvironment()
                    )
                }
            )
            actions.append(
                CommandBannerAction(title: "Diagnose", systemImage: "stethoscope") {
                    runCommand(
                        script: "repair.command",
                        arguments: ["diagnose"],
                        environment: repairEnvironment(),
                        intent: .diagnose
                    )
                }
            )
        }
        if includeLogs {
            actions.append(
                CommandBannerAction(title: "Open Logs", systemImage: "doc.text.magnifyingglass") {
                    openLatestLogs()
                }
            )
        }
        return actions
    }

    private func dashboardLaunchEnvironment(extra: [String: String] = [:]) -> [String: String] {
        var env = bottleEnvironment()
        // Foreground launch from the dashboard so exit codes and errors surface in-app.
        env["COSMOS_DETACH"] = "0"
        for (key, value) in extra {
            env[key] = value
        }
        return env
    }

    private func beginCommandOutput() {
        commandBannerQueue.clearTransient()
        consoleExpanded = true
    }

    private func runCommand(
        script: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        intent: CommandIntent = .general,
        chain: Bool = false
    ) {
        guard let scriptURL = resolveScript(script) else {
            let message = "Script not found or not executable: \(script)"
            output = message
            showBanner(kind: .failure, message: message)
            return
        }

        let displayedCommand = ([script] + arguments).joined(separator: " ")
        if chain {
            output += "\nRunning: \(displayedCommand)\n\n"
        } else {
            beginCommandOutput()
            output = "Running: \(displayedCommand)\n\n"
        }
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
            guard !data.isEmpty else { return }
            let text = CommandOutputParser.decode(data)
            guard !text.isEmpty else { return }

            DispatchQueue.main.async {
                output += text
                let trimmed = CommandOutputParser.trimPreservingErrors(output)
                if trimmed.trimmed {
                    output = trimmed.text
                    outputWasTrimmed = true
                }
            }
        }

        task.terminationHandler = { process in
            pipe.fileHandleForReading.readabilityHandler = nil
            // Drain anything written between the last readability callback and exit
            // so a script's final lines are not truncated from the output pane.
            let tail = pipe.fileHandleForReading.readDataToEndOfFile()
            let tailText = CommandOutputParser.decode(tail)
            DispatchQueue.main.async {
                if !tailText.isEmpty {
                    output += tailText
                }
                isRunning = false
                let exitCode = process.terminationStatus
                let succeeded = exitCode == 0
                output += succeeded ? "\nDone." : "\nExited with status \(exitCode)."
                if succeeded {
                    if script == "detect_steam_games.command",
                       arguments.contains("--sync") {
                        let syncResult = SteamLibraryMonitor.SyncResult(
                            status: SteamLibraryMonitor.parseSyncStatus(from: output) ?? "current",
                            newCount: SteamLibraryMonitor.parseSyncNewCount(from: output) ?? 0,
                            removedCount: SteamLibraryMonitor.parseSyncRemovedCount(from: output) ?? 0,
                            exitCode: 0,
                            output: output
                        )
                        applySteamLibrarySyncResult(syncResult, announce: true, seedOnly: false)
                    } else {
                        if script == "detect_steam_games.command" {
                            pendingNewSteamGames = 0
                            pendingRemovedSteamGames = 0
                        }
                        if intent == .diagnose,
                           let summary = CommandOutputParser.diagnoseSummary(from: output),
                           (CommandOutputParser.suggestedFixCount(from: output) ?? 0) > 0 {
                            showBanner(
                                kind: .info,
                                message: summary,
                                actions: failureRecoveryActions(includeLogs: true, includeRepair: true)
                            )
                        } else if !chain {
                            showBanner(kind: .success, message: successMessage(for: intent))
                        }
                    }
                } else {
                    let failureMessage = CommandOutputParser.failureMessage(
                        exitCode: exitCode,
                        intent: intent,
                        output: output
                    )
                    let needsLogs = intent == .setup || intent == .gameLaunch
                    let needsRepair = intent == .gameLaunch
                    if !chain {
                        var actions = failureRecoveryActions(
                            includeLogs: needsLogs,
                            includeRepair: needsRepair
                        )
                        if script == "detect_steam_games.command",
                           arguments.contains(where: { $0 == "--sync" || $0 == "--install" }) {
                            actions.append(contentsOf: steamSyncTerminalActions())
                        }
                        consoleExpanded = true
                        showBanner(
                            kind: .failure,
                            message: failureMessage,
                            actions: actions
                        )
                    }
                }
                refreshStatus()
                if shouldRefreshSteamAfterCommand(script: script, arguments: arguments) {
                    refreshSteamHealth()
                    checkSteamLibraryForNewGames(autoSync: false, force: true)
                    if script == "run.command", arguments.contains("--verify-steam") {
                        lastWarnedBrokenSteamInstalls = pendingBrokenSteamInstalls
                    }
                }
            }
        }

        do {
            try task.run()
        } catch {
            isRunning = false
            let message = "Failed to run command: \(error.localizedDescription)"
            output = message
            showBanner(kind: .failure, message: message)
            refreshStatus()
        }
    }

    private func shouldRefreshSteamAfterCommand(script: String, arguments: [String]) -> Bool {
        switch script {
        case "run.command":
            return arguments.contains("--verify-steam") || arguments.contains("--install-steamwebhelper")
        case "detect_steam_games.command":
            return arguments.contains(where: { $0 == "--verify" || $0 == "--sync" || $0 == "--install" })
        case "repair.command":
            return arguments.contains(where: {
                $0 == "install_steamwebhelper_wrapper" || $0 == "fix_steam_cloud_paths"
            })
        default:
            return false
        }
    }

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
        .environmentObject(CosmosAppState.shared)
}
#endif
