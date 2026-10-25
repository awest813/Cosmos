import Foundation
import AppKit
import SwiftUI

extension ContentView {
    // MARK: - Detail

    var detailContent: some View {
        ScrollViewReader { proxy in
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
                    if isRunning || pendingTerminalJobID != nil {
                        CosmosOperationProgress(title: activeOperationTitle, inTerminal: pendingTerminalJobID != nil, output: output)
                    }
                    steamHealthNoticesSection
                    heroSection
                    CosmosStorageNotice()
                    dashboardSectionPicker
                    if isSteamReady {
                        if !isSetupComplete {
                            almostDoneSection
                        }
                        dashboardSectionContent
                        // Post-setup: collapsed checklist reference (EmptyView once complete).
                        setupAssistantSection
                    } else if dashboardSection != .launch {
                        dashboardSectionContent
                    } else {
                        // New user: lead with the guided setup card and its primary action.
                        setupAssistantSection
                        setupLaunchHintSection
                        if showAdvancedSetupOptions {
                            steamWineSettingsSection
                            performanceGraphicsSection
                            setupToolsGrid
                        } else {
                            newUserMaintenanceSection
                        }
                        includedLaunchersDisclosure
                    }
                    consoleSection
                }
                .padding(CosmosSpacing.contentPadding)
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .cosmosContentBackground()
            .onChange(of: dashboardSection) { _ in
                schedulePendingScroll(using: proxy)
            }
            .onChange(of: pendingScrollNonce) { nonce in
                guard nonce != 0 else { return }
                schedulePendingScroll(using: proxy)
            }
        }
        .onChange(of: output) { _ in
            if !consoleExpanded {
                consoleHasNewOutput = true
            }
        }
    }

    /// Tools and Bottles stay behind Advanced. Ports stays on the main bar:
    /// that is the Sikarugir screen, one Windows program as a Mac app.
    var advancedTabsVisible: Bool {
        showAdvancedTabs || dashboardSection == .tools || dashboardSection == .bottles
    }

    var visibleDashboardSections: [DashboardSection] {
        var sections: [DashboardSection] = [.launch, .library, .ports]
        if advancedTabsVisible {
            sections += [.bottles, .tools]
        }
        return sections
    }

    /// Navigation is available before Steam setup; ports do not depend on Steam.
    var dashboardSectionPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CosmosDashboardTabBar(selection: $dashboardSection, sections: visibleDashboardSections)
                advancedTabsToggle
            }

            HStack(spacing: 8) {
                Text(dashboardSection.subtitle)
                Text("·")
                Text(advancedTabsVisible ? "⌘1–5 to switch" : "Advanced shows Bottles and Tools")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Small chip that reveals or hides Bottles and Tools.
    var advancedTabsToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                if advancedTabsVisible {
                    showAdvancedTabs = false
                    // Don't strand the user on a tab that is about to hide.
                    if dashboardSection == .tools || dashboardSection == .bottles {
                        dashboardSection = .launch
                    }
                } else {
                    showAdvancedTabs = true
                }
            }
        } label: {
            Label(advancedTabsVisible ? "Hide Advanced" : "Advanced",
                  systemImage: advancedTabsVisible ? "chevron.up" : "chevron.down")
                .font(.subheadline.weight(.medium))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(advancedTabsVisible ? "Hide Bottles and Tools" : "Show Bottles and Tools")
        .accessibilityLabel(advancedTabsVisible ? "Hide Advanced" : "Advanced")
        .accessibilityValue(advancedTabsVisible ? "Expanded" : "Collapsed")
        .accessibilityHint("Shows or hides Bottles and Tools")
    }

    @ViewBuilder
    var dashboardSectionContent: some View {
        switch dashboardSection {
        case .launch:
            wineRuntimeSection
            if let selectedProfile {
                selectedGameExperience(selectedProfile)
                DisclosureGroup("Game Details & Recommended Settings") {
                    selectedProfileSection(selectedProfile)
                        .padding(.top, CosmosSpacing.sectionInner)
                }
            }
            launchSection
            DisclosureGroup(isExpanded: $showLaunchSettings) {
                VStack(alignment: .leading, spacing: CosmosSpacing.section) {
                    steamWineSettingsSection
                    performanceGraphicsSection
                }
                .padding(.top, CosmosSpacing.sectionInner)
            } label: {
                Label("Steam & Graphics Settings", systemImage: "slider.horizontal.3")
                    .font(.headline)
            }
            includedLaunchersDisclosure
        case .library:
            if let selectedProfile { selectedGameExperience(selectedProfile) }
            gameLibrarySection
            DisclosureGroup(isExpanded: $showGameTools) {
                VStack(alignment: .leading, spacing: CosmosSpacing.section) {
                    curatedProfilesSection
                    compatibilitySection
                    repairSection
                }
                .padding(.top, CosmosSpacing.sectionInner)
            } label: {
                Label("Game Settings & Troubleshooting", systemImage: "wrench.and.screwdriver")
                    .font(.headline)
            }
        case .tools:
            includedLaunchersSection
            maintenanceGrid
            storeExpansionSection
        case .bottles:
            bottlesSection
        case .ports:
            PortsDashboard(
                ports: ports,
                bottleNames: bottles.map(\.name),
                isRunning: isRunning || pendingTerminalJobID != nil,
                unavailableReason: PortHostSupport.unavailableReason(
                    architecture: wineRuntime.chipArchitecture,
                    version: ProcessInfo.processInfo.operatingSystemVersion
                ),
                onOpenDownloads: { showDownloads = true },
                onInstall: { storeImportRequest = .classicGame() },
                onResumeInstall: { storeImportRequest = .classicGame(resuming: true) },
                pendingInstallations: pendingGameInstallations,
                onContinueInstallation: { installation, retry in
                    storeImportRequest = .classicGame(resuming: !retry, installation: installation)
                },
                requiresRosetta: wineRuntime.needsRosetta && !wineRuntime.rosettaReady,
                onUpdate: { port, draft, completion in
                    runCommand(
                        script: "port.command", arguments: draft.commandArguments(updating: port.id),
                        onCompletion: { succeeded, message in completion(succeeded ? nil : message) }
                    )
                },
                onOpenLogs: { port in
                    runCommand(
                        script: "run.command", arguments: ["--logs"],
                        environment: ["COSMOS_BOTTLE": port.bottle]
                    )
                },
                onDiagnose: { port in
                    runCommand(script: "repair.command", arguments: ["diagnose"], environment: portCommandEnvironment(port), intent: .diagnose)
                },
                onStopEnvironment: { port in
                    runCommand(script: "repair.command", arguments: ["apply-fix", "kill_wine"], environment: portCommandEnvironment(port))
                },
                onCloneEnvironment: { port in
                    storeImportRequest = .cloneEnvironment(source: port.bottle)
                },
                onCreate: { draft, completion in
                    runCommand(
                        script: "port.command", arguments: draft.commandArguments,
                        onCompletion: { succeeded, message in completion(succeeded ? nil : message) }
                    )
                },
                onLaunch: { port in
                    guard ensureRosettaForWineLaunch() else { return }
                    runCommand(
                        script: "port.command",
                        arguments: ["launch", port.id],
                        intent: .gameLaunch
                    )
                },
                onBuild: { port in
                    runCommand(script: "port.command", arguments: ["build", port.id])
                },
                onDelete: { port in
                    runCommand(script: "port.command", arguments: ["delete", port.id, "--force"])
                }
            )
        }
    }

    var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heroTitle)
                .font(CosmosTypography.heroTitle)
                .foregroundStyle(CosmosGradients.heroTitle)
            Text(heroSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    func portCommandEnvironment(_ port: WinePort) -> [String: String] {
        var environment = ["COSMOS_BOTTLE": port.bottle, "COSMOS_PROGRAM_ARCH": port.programArch, "COSMOS_SKIP_STEAM": "1"]
        if port.bottle.isEmpty {
            environment["WINE_VERSION"] = steamSettings.wineVersion
        } else {
            let config = BottleStore.bottlesDirectoryURL.appendingPathComponent(port.bottle).appendingPathComponent("bottle.conf")
            environment["WINE_VERSION"] = BottleStore.parseConf(config)["WINE_VERSION"] ?? "11.8"
        }
        return environment
    }

    var heroTitle: String {
        if !isSteamReady && dashboardSection == .launch { return "Welcome to Cosmos" }
        switch dashboardSection {
        case .launch: return "Ready to play"
        case .library: return "Your Games"
        case .tools: return "Tools & Imports"
        case .bottles: return "Windows Environments"
        case .ports: return "Mac Apps from Windows Programs"
        }
    }

    /// Wine prefix + Steam are ready; unlocks the dashboard tabs.
    var isSteamReady: Bool {
        setupRosettaReady
            && cosmosInstalled
            && steamSettings.isPrefixInitialized
            && steamSettings.isSteamInstalled
    }

    /// Saved profiles or Dock launchers exist.
    var hasGameLaunchers: Bool {
        !profiles.isEmpty || cosmosAppCount > 0
    }

    var isSetupComplete: Bool {
        isSteamReady && hasGameLaunchers
    }

    /// Rosetta is step 1 on Apple Silicon; Intel hosts skip it.
    var setupIncludesRosetta: Bool {
        wineRuntime.needsRosetta
    }

    var setupRosettaReady: Bool {
        !setupIncludesRosetta || wineRuntime.rosettaReady
    }

    var setupStepTotal: Int {
        setupIncludesRosetta ? 5 : 4
    }

    var setupProgress: Double {
        CosmosSetupProgress.fraction(
            needsRosetta: setupIncludesRosetta,
            rosettaReady: wineRuntime.rosettaReady,
            cosmosInstalled: cosmosInstalled,
            prefixReady: steamSettings.isPrefixInitialized,
            steamInstalled: steamSettings.isSteamInstalled,
            hasGames: hasGameLaunchers
        )
    }

    var setupStepNumber: Int {
        if setupIncludesRosetta && !wineRuntime.rosettaReady { return 1 }
        if !cosmosInstalled { return setupIncludesRosetta ? 2 : 1 }
        if !steamSettings.isPrefixInitialized { return setupIncludesRosetta ? 3 : 2 }
        if !steamSettings.isSteamInstalled { return setupIncludesRosetta ? 4 : 3 }
        if !hasGameLaunchers { return setupStepTotal }
        return setupStepTotal
    }

    /// Saved profiles that match a shipped curated YAML preset.
    var installedCuratedProfiles: [GameProfile] {
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

    var setupPrimaryTitle: String {
        if setupIncludesRosetta && !wineRuntime.rosettaReady { return "Install Rosetta 2" }
        if !cosmosInstalled { return "Set Up Game Launchers" }
        if !steamSettings.isPrefixInitialized { return "Prepare Steam Environment" }
        if !steamSettings.isSteamInstalled { return "Install Steam" }
        if !hasGameLaunchers { return "Find Installed Games" }
        return "Refresh Status"
    }

    var setupPrimarySubtitle: String {
        let estimateSuffix: (String) -> String = { base in
            guard let estimate = setupPrimaryTimeEstimate else { return base }
            return "\(base) · \(estimate)"
        }
        if setupIncludesRosetta && !wineRuntime.rosettaReady {
            return estimateSuffix("Required before x86_64 Wine can run on Apple Silicon · opens Terminal")
        }
        if !cosmosInstalled {
            return estimateSuffix("Installs launchers into /Applications/Cosmos Apps · opens Terminal")
        }
        if !steamSettings.isPrefixInitialized {
            return estimateSuffix("Downloads Wine, creates the prefix, and installs Steam")
        }
        if !steamSettings.isSteamInstalled {
            let base = steamSettings.silentInstallEnabled
                ? "Installs Steam automatically (wizard fallback if needed)"
                : "Opens the graphical Steam installer wizard in Terminal"
            return estimateSuffix(base)
        }
        if !hasGameLaunchers {
            return estimateSuffix("Detect installed games and create Dock-friendly .app launchers")
        }
        return "Update the checklist and sidebar"
    }

    var setupPrimaryTimeEstimate: String? {
        if setupIncludesRosetta && !wineRuntime.rosettaReady { return "about 1 min" }
        if !cosmosInstalled { return "about 1 min" }
        if !steamSettings.isPrefixInitialized { return "about 5 min · Wine download" }
        if !steamSettings.isSteamInstalled { return "about 3 min" }
        if !hasGameLaunchers { return "about 1 min" }
        return nil
    }

    var setupPrimarySystemImage: String {
        if setupIncludesRosetta && !wineRuntime.rosettaReady { return "cpu" }
        if !cosmosInstalled { return "arrow.down.circle.fill" }
        if !steamSettings.isPrefixInitialized { return "externaldrive.fill.badge.checkmark" }
        if !steamSettings.isSteamInstalled { return "shippingbox.fill" }
        if !hasGameLaunchers { return "square.grid.2x2.fill" }
        return "arrow.clockwise"
    }

    var heroSubtitle: String {
        if dashboardSection == .ports {
            return "Wrap a Windows program as a Mac app on Apple Silicon. Steam setup is optional."
        }
        if isSteamReady {
            switch dashboardSection {
            case .launch: return "Pick a game and play. Your settings are ready when you need them."
            case .library: return "Your collection, ready to explore."
            case .tools: return "Add games, check your setup, or open Highball and Vermut."
            case .bottles: return "Keep games with different requirements in separate Windows environments."
            case .ports: return "Wrap a Windows program so it opens like a Mac app on Apple Silicon."
            }
        }
        if !isSetupComplete, selectedProfile == nil, selectedBottle == nil {
            return "Follow the setup guide below — one button per step. First-time setup takes about 10–15 minutes."
        }
        if let selectedProfile {
            if selectedProfileCanLaunch {
                return "Launch via \(selectedProfile.launchMethodLabel.lowercased())."
            }
            return "This profile has no launch path — edit its config file or pick another profile."
        }
        if selectedBottle != nil {
            return "Selected — adjust the graphics mode and launch Steam from the controls below."
        }
        if !cosmosInstalled {
            return "Set up game launchers, then prepare Steam and find your games."
        }
        if !steamSettings.isPrefixInitialized {
            return "Set up Steam — this downloads what's needed and prepares your game environment. Then install Steam."
        }
        if !steamSettings.isSteamInstalled {
            return steamSettings.silentInstallEnabled
                ? "Run Install Steam to finish the unattended install, then detect games."
                : "Run Install Steam to complete the installer wizard, then detect games."
        }
        if !hasGameLaunchers {
            return "Steam is ready — install a Windows game, then choose Find Installed Games."
        }
        return "Manage Cosmos, launch Steam, and jump into saved game profiles from one place."
    }

    var setupAssistantSection: some View {
        Group {
            if isSetupComplete {
                EmptyView()
            } else if isSteamReady {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        setupChecklistSteps
                        setupAssistantUtilityButtons
                    }
                } label: {
                    Label("Setup checklist", systemImage: "checklist")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.cosmosPrimary)
                }
                .font(.subheadline)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("First-time setup")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.cosmosPrimary)
                        Text("About 10–15 minutes the first time — downloads take most of it. Some steps open Terminal to ask for your password; finish any prompts there, then press Refresh here.")
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

                    CosmosProminentActionButton(
                        title: setupPrimaryTitle,
                        subtitle: setupPrimarySubtitle,
                        systemImage: setupPrimarySystemImage,
                        isRunning: isRunning,
                        help: "Run the next recommended setup step (⌘⇧L)"
                    ) {
                        performNextSetupStep()
                    }

                    Text("Shortcut: ⌘⇧L continues setup · ⌘R refreshes status")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    CosmosNoticeBanner(
                        tint: Color.cosmosWarning,
                        systemImage: "terminal.fill",
                        title: "Terminal steps",
                        message: "Most setup steps open Terminal to ask for your Mac password. If a step fails, use Open Logs below before retrying — then press Refresh (⌘R)."
                    )

                    setupCompatibilityLookupSection
                    setupChecklistSteps
                    setupAssistantUtilityButtons
                }
                .cosmosCard(prominent: true)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("First-time setup guide, step \(setupStepNumber) of \(setupStepTotal)")
            }
        }
    }

    var setupChecklistSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            if wineRuntime.needsRosetta {
                setupStep(
                    done: wineRuntime.rosettaReady,
                    title: "Install Rosetta 2",
                    detail: wineRuntime.rosettaReady
                        ? "x86_64 Wine can run on Apple Silicon"
                        : "Required before Wine can launch on Apple Silicon",
                    estimate: "about 1 min"
                )
            }
            setupStep(
                done: cosmosInstalled,
                title: "Set up game launchers",
                detail: cosmosInstalled
                    ? "Launchers are in /Applications/Cosmos Apps"
                    : "Creates the launcher folder and shortcuts",
                estimate: "about 1 min"
            )
            setupStep(
                done: steamSettings.isPrefixInitialized,
                title: "Prepare Steam environment",
                detail: steamSettings.isPrefixInitialized
                    ? "Environment ready"
                    : "Downloads Wine and sets a graphics mode (default is fine)",
                estimate: "about 5 min"
            )
            setupStep(
                done: steamSettings.isSteamInstalled,
                title: "Install Steam",
                detail: steamSettings.isSteamInstalled
                    ? "Steam is installed"
                    : (steamSettings.silentInstallEnabled
                        ? "Unattended install (wizard fallback if needed)"
                        : "Complete the graphical Steam installer wizard"),
                estimate: "about 3 min"
            )
            setupStep(
                done: hasGameLaunchers,
                title: "Build game launchers",
                detail: hasGameLaunchers
                    ? launcherSummaryText
                    : "After you install a Windows game in Steam",
                estimate: "about 1 min"
            )
        }
    }

    var setupAssistantUtilityButtons: some View {
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

    func setupStep(done: Bool, title: String, detail: String, estimate: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.cosmosSuccess : Color.secondary)
                .font(.body.weight(.semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    if !done, let estimate {
                        Text(estimate)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.cosmosPrimary.opacity(0.75))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cosmosPrimary.opacity(0.08), in: Capsule())
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(done ? "done" : "not done"). \(detail)")
    }

    var setupLaunchHintSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("While setup runs", systemImage: "play.circle")
            Text("Quick Launch and the full dashboard unlock once Steam is installed. Use the setup guide above for the next step.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Steam is ready but launchers are not — keep focus on the last setup step.
    var almostDoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CosmosNoticeBanner(
                tint: Color.cosmosBright,
                systemImage: "gamecontroller.fill",
                title: "Almost there",
                message: "Steam is ready. Open Steam and install a Windows game. Then choose Find Installed Games to add it to Cosmos and create a Dock shortcut."
            )
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { firstGameActions }
                VStack(alignment: .leading, spacing: 10) { firstGameActions }
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    var firstGameActions: some View {
        Button("Open Steam to Install a Game", action: launchSteamFromDashboard)
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
        Button("Find Installed Games", action: buildLaunchers)
            .buttonStyle(.bordered)
            .disabled(isRunning)
            .help("Add installed Steam games to Cosmos and create Dock shortcuts")
    }

    var launcherSummaryText: String {
        var parts: [String] = []
        if !profiles.isEmpty {
            parts.append("\(profiles.count) profile\(profiles.count == 1 ? "" : "s")")
        }
        if cosmosAppCount > 0 {
            parts.append("\(cosmosAppCount) Dock app\(cosmosAppCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Launchers ready" : parts.joined(separator: " · ")
    }

    var newUserMaintenanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $showAdvancedSetupOptions) {
                setupToolsGrid
            } label: {
                Label("More options", systemImage: "ellipsis.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.cosmosPrimary)
            }
            Text("Optional: find games, open the profiles folder, or check logs. The defaults work for most games.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    func performNextSetupStep() {
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
    func buildLaunchers() {
        runCommand(
            script: "detect_steam_games.command",
            arguments: ["--install"],
            environment: steamLibraryEnvironment(),
            intent: .setup
        )
    }

    func steamDetectionEnvironment() -> [String: String] {
        var env = bottleEnvironment()
        env["COSMOS_STEAM_SNAPSHOT"] = SteamLibraryMonitor.snapshotURL(bottleName: selectedBottle?.name).path
        return env
    }

    func steamLibraryEnvironment(seedOnly: Bool = false) -> [String: String] {
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

    func refreshSteamHealth() {
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

    var isPrefixReady: Bool {
        steamSettings.isPrefixInitialized || selectedBottle != nil
    }

    func checkGogLibraryForUnregistered() {
        guard isPrefixReady, !isRunning, pendingTerminalJobID == nil else { return }
        guard let importScript = resolveScript("import_game.command") else { return }
        let env = bottleEnvironment()
        let configsDir = SavedProfileStore.configsDirectory()
        DispatchQueue.global(qos: .utility).async {
            let result = GogLibraryMonitor.listGames(importScript: importScript, environment: env)
            DispatchQueue.main.async {
                switch result {
                case .success(let games):
                    gogDetectionWarning = nil
                    let missing = GogLibraryMonitor.unregistered(games: games, configsDirectory: configsDir)
                    pendingUnregisteredGogGames = missing.count
                    pendingLowConfidenceGogGames = GogLibraryMonitor.lowConfidenceInstalls(in: games).count
                default:
                    gogDetectionWarning = gogDetectionFailureMessage(result)
                    pendingUnregisteredGogGames = 0
                    pendingLowConfidenceGogGames = 0
                }
            }
        }
    }

    func gogDetectionFailureMessage(_ result: GameListResult<GogLibraryMonitor.DetectedGame>) -> String {
        switch result {
        case .timedOut:
            return "GOG library detection timed out."
        case .failed:
            return "GOG library detection failed."
        case .parseFailed:
            return "GOG library detection returned invalid data."
        case .scriptUnavailable:
            return "GOG detection script is not available."
        case .success:
            return ""
        }
    }

    func syncGogLibrary(build: Bool, announce: Bool) {
        guard !isRunning, pendingTerminalJobID == nil else { return }
        guard let importScript = resolveScript("import_game.command") else { return }
        consoleExpanded = true
        activeOperationTitle = "Adding GOG games…"
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

    func applyGogLibrarySyncResult(
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

    func checkSteamLibraryForNewGames(autoSync: Bool, force: Bool = false) {
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
            let result = SteamLibraryMonitor.listInstalledGames(detectScript: detectScript, environment: env)
            DispatchQueue.main.async {
                steamLibraryCheckInFlight = false
                lastSteamLibraryCheck = Date()
                guard case .success(let games) = result else {
                    if force || !autoSync {
                        showSteamDetectionFailureBanner(result)
                    }
                    return
                }

                pendingBrokenSteamInstalls = SteamLibraryMonitor.brokenInstalls(in: games).count

                let snapshotExists = FileManager.default.fileExists(atPath: snapshotURL.path)
                let snapshot = SteamLibraryMonitor.loadSnapshotAppIDs(bottleName: bottleName)
                let wineGames = games.filter(SteamLibraryMonitor.isWineManaged)
                let currentIDs = Set(wineGames.map(\.appID))
                let syncableNew = SteamLibraryMonitor.syncEligibleNewGames(comparedTo: snapshot, current: games)
                pendingRemovedSteamGames = snapshotExists ? snapshot.subtracting(currentIDs).count : 0

                if !snapshotExists {
                    pendingNewSteamGames = 0
                    if autoSync && isSetupComplete {
                        syncSteamLibrary(announce: false, seedOnly: true)
                    }
                    return
                }

                pendingNewSteamGames = syncableNew.count

                if autoSync && isSetupComplete {
                    if syncableNew.count > 0 || pendingRemovedSteamGames > 0 {
                        syncSteamLibrary(announce: false)
                    }
                    announceBrokenSteamInstallsIfNeeded()
                    return
                }

                if syncableNew.count > 0 {
                    showNewSteamGamesBanner(count: syncableNew.count)
                } else if pendingRemovedSteamGames > 0 {
                    showSteamCleanupBanner(count: pendingRemovedSteamGames)
                } else {
                    announceBrokenSteamInstallsIfNeeded()
                }
            }
        }
    }

    func showSteamDetectionFailureBanner(_ result: GameListResult<SteamLibraryMonitor.DetectedGame>) {
        let message: String
        switch result {
        case .timedOut:
            message = "Steam library detection timed out."
        case .failed:
            message = "Steam library detection failed."
        case .parseFailed:
            message = "Steam library detection returned invalid data."
        case .scriptUnavailable:
            message = "Steam detection script is not available."
        case .success:
            return
        }
        showBanner(
            kind: .failure,
            message: message,
            actions: [
                CommandBannerAction(title: "Retry", systemImage: "arrow.clockwise") {
                    checkSteamLibraryForNewGames(autoSync: false, force: true)
                },
                CommandBannerAction(title: "Detect in Console", systemImage: "terminal.fill") {
                    runCommand(
                        script: "detect_steam_games.command",
                        arguments: ["--list"],
                        environment: steamDetectionEnvironment()
                    )
                },
            ]
        )
    }

    func syncSteamLibrary(announce: Bool, seedOnly: Bool = false) {
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
        activeOperationTitle = "Updating your Steam library…"
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

    func applySteamLibrarySyncResult(
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

    func showSteamSyncFailureBanner(ifAnnounced announce: Bool) {
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

    func showSteamCleanupBanner(count: Int) {
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

    func steamSyncTerminalActions() -> [CommandBannerAction] {
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

    func showNewSteamGamesBanner(count: Int) {
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

    func announceBrokenSteamInstallsIfNeeded() {
        guard pendingBrokenSteamInstalls > 0,
              pendingBrokenSteamInstalls > lastWarnedBrokenSteamInstalls else { return }
        lastWarnedBrokenSteamInstalls = pendingBrokenSteamInstalls
        showBrokenSteamInstallsBanner(count: pendingBrokenSteamInstalls)
    }

    func showBrokenSteamInstallsBanner(count: Int) {
        showBanner(
            kind: .failure,
            message: "\(count) Wine Steam install\(count == 1 ? "" : "s") missing a folder or game .exe. Reinstall in Steam, then verify.",
            actions: [
                CommandBannerAction(title: "Verify Library", systemImage: "checkmark.shield.fill") {
                    runCommand(script: "run.command", arguments: ["--verify-steam"], environment: steamDetectionEnvironment())
                },
                CommandBannerAction(title: "Launch Steam", systemImage: "play.fill") {
                    launchSteamFromDashboard()
                },
            ]
        )
    }

    @ViewBuilder
    var steamHealthNoticesSection: some View {
        if isSteamReady || isPrefixReady {
            VStack(alignment: .leading, spacing: 10) {
                if isSteamReady, steamHealth.needsMingwForWrapper || steamHealth.needsWrapperInstall {
                    VStack(alignment: .leading, spacing: 8) {
                        CosmosNoticeBanner(
                            tint: Color.cosmosWarning,
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
                if isSteamReady, steamHealth.hasBrokenInstalls || pendingBrokenSteamInstalls > 0 {
                    let broken = max(steamHealth.gamesBroken, pendingBrokenSteamInstalls)
                    VStack(alignment: .leading, spacing: 8) {
                        CosmosNoticeBanner(
                            tint: Color.cosmosWarning,
                            systemImage: "exclamationmark.triangle.fill",
                            title: "Steam installs need attention",
                            message: "\(broken) Wine Steam game\(broken == 1 ? "" : "s") have a missing install folder or game .exe. Reinstall in Steam or verify the library."
                        )
                        HStack(spacing: 10) {
                            Button("Verify Library") {
                                runCommand(
                                    script: "run.command",
                                    arguments: ["--verify-steam"],
                                    environment: steamDetectionEnvironment()
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRunning)
                            Button("Launch Steam") {
                                launchSteamFromDashboard()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                        }
                        .font(.subheadline)
                    }
                }
                if isSteamReady, steamHealth.hasDualInstallWarning {
                    let ids = steamHealth.dualInstallAppIDs.prefix(6).joined(separator: ", ")
                    VStack(alignment: .leading, spacing: 8) {
                        CosmosNoticeBanner(
                            tint: Color.cosmosWarning,
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
                if isSteamReady, steamHealth.hasCloudWarning {
                    VStack(alignment: .leading, spacing: 8) {
                        CosmosNoticeBanner(
                            tint: Color.cosmosWarning,
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
                if isPrefixReady, let warning = gogDetectionWarning, !warning.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        CosmosNoticeBanner(
                            tint: Color.cosmosWarning,
                            systemImage: "exclamationmark.triangle.fill",
                            title: "GOG detection issue",
                            message: warning
                        )
                        HStack(spacing: 10) {
                            Button("Retry") {
                                checkGogLibraryForUnregistered()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRunning)
                            Button("Detect in Console") {
                                runCommand(
                                    script: "import_game.command",
                                    arguments: ["list-gog"],
                                    environment: bottleEnvironment()
                                )
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                        }
                        .font(.subheadline)
                    }
                }
                if isPrefixReady, pendingLowConfidenceGogGames > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        CosmosNoticeBanner(
                            tint: Color.cosmosWarning,
                            systemImage: "questionmark.circle.fill",
                            title: "GOG exe detection uncertain",
                            message: "\(pendingLowConfidenceGogGames) GOG install\(pendingLowConfidenceGogGames == 1 ? "" : "s") used scored .exe guessing instead of goggame metadata. Verify before launching."
                        )
                        HStack(spacing: 10) {
                            Button("List GOG Games") {
                                runCommand(script: "import_game.command", arguments: ["list-gog"], environment: bottleEnvironment())
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRunning)
                            Button("Register All") {
                                syncGogLibrary(build: false, announce: true)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                        }
                        .font(.subheadline)
                    }
                }
                if isPrefixReady, pendingUnregisteredGogGames > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        CosmosNoticeBanner(
                            tint: Color.cosmosInfo,
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

    var setupCompatibilityLookupSection: some View {
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
                    .accessibilityLabel("Steam App ID for compatibility lookup")
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
}
