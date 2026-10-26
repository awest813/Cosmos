import Foundation
import AppKit
import SwiftUI

extension ContentView {
    // MARK: - Quick launch

    /// Launch a saved profile's game executable through the Wine shell flow.
    /// Shared by the Quick Launch button and the sidebar context menu.
    func launchProfile(_ profile: SavedProfile) {
        guard !isRunning, pendingTerminalJobID == nil else { return }
        guard profile.canLaunchFromDashboard else {
            showBanner(kind: .info, message: "\(profile.name) has no executable path or Steam App ID. Import the game again or update its launch configuration.")
            return
        }
        guard ensureRosettaForWineLaunch() else { return }
        if let appid = profile.steamAppID,
           let yaml = GameProfileStore.find(steamAppID: appid),
           yaml.isBlocked {
            pendingBlockedLaunch = profile
            return
        }
        launchProfileUnchecked(profile)
    }

    func launchProfileUnchecked(_ profile: SavedProfile) {
        guard !isRunning, pendingTerminalJobID == nil else { return }
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

    var launchSteamButtonTitle: String {
        wineRuntime.needsRosetta && !wineRuntime.rosettaReady ? "Install Rosetta 2" : "Launch Steam"
    }

    var launchSteamButtonSubtitle: String {
        if wineRuntime.needsRosetta && !wineRuntime.rosettaReady {
            return "Required before x86_64 Wine can run · opens Terminal"
        }
        return "Open Steam in the bottle"
    }

    var launchSteamButtonHelp: String {
        if wineRuntime.needsRosetta && !wineRuntime.rosettaReady {
            return "Install Rosetta 2 so Wine can run on Apple Silicon (may ask for your password)"
        }
        return "Start Steam in the default Wine prefix"
    }

    /// Rosetta install needs Terminal for sudo; game/Steam launch needs Rosetta on Apple Silicon.
    @discardableResult
    func ensureRosettaForWineLaunch() -> Bool {
        guard wineRuntime.needsRosetta, !wineRuntime.rosettaReady else { return true }
        runInTerminal(script: "run.command", arguments: ["--install-rosetta"])
        return false
    }

    func launchSteamFromDashboard() {
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

    func launchSelectedProfile() {
        guard let profile = selectedProfile else { return }
        launchProfile(profile)
    }

    func verifySteamInstall() {
        runCommand(
            script: "run.command",
            arguments: ["--verify-steam"],
            environment: steamDetectionEnvironment()
        )
    }

    func listGogGames() {
        openImportTools()
        runCommand(script: "import_game.command", arguments: ["list-gog"], environment: bottleEnvironment())
    }

    func focusDashboardSection(_ section: DashboardSection) {
        dashboardSection = section
        if useRedesignedWorkspace {
            if section == .bottles { workspaceDestination = .environments }
            else { workspaceUtilitySection = section }
        }
    }

    func focusBottlesSection() {
        focusDashboardSection(.bottles)
        pendingScrollToBottles = true
    }

    /// Bitmask so ScrollViewReader can react when pending scroll flags are set on an already-visible tab.
    var pendingScrollNonce: Int {
        var nonce = 0
        if pendingScrollToImport { nonce |= 1 }
        if pendingScrollToGameLibrary { nonce |= 2 }
        if pendingScrollToGameProfiles { nonce |= 4 }
        if pendingScrollToRepair { nonce |= 8 }
        if pendingScrollToCompatibility { nonce |= 16 }
        if pendingScrollToSteamSettings { nonce |= 32 }
        if pendingScrollToPerformanceGraphics { nonce |= 64 }
        if pendingScrollToBottles { nonce |= 128 }
        return nonce
    }

    func schedulePendingScroll(using proxy: ScrollViewProxy) {
        if pendingScrollToGameProfiles || pendingScrollToCompatibility || pendingScrollToRepair {
            showGameTools = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            consumePendingScrolls(using: proxy)
        }
    }

    func consumePendingScrolls(using proxy: ScrollViewProxy) {
        let target: String
        let clearRequest: () -> Void
        if dashboardSection == .tools, pendingScrollToImport {
            target = CosmosScrollAnchor.storeImport
            clearRequest = { pendingScrollToImport = false }
        } else if dashboardSection == .library, pendingScrollToGameLibrary {
            target = CosmosScrollAnchor.gameLibrary
            clearRequest = { pendingScrollToGameLibrary = false }
        } else if dashboardSection == .library, pendingScrollToGameProfiles {
            target = CosmosScrollAnchor.gameProfiles
            clearRequest = { pendingScrollToGameProfiles = false }
        } else if dashboardSection == .library, pendingScrollToRepair {
            target = CosmosScrollAnchor.repair
            clearRequest = { pendingScrollToRepair = false }
        } else if dashboardSection == .library, pendingScrollToCompatibility {
            target = CosmosScrollAnchor.compatibility
            clearRequest = { pendingScrollToCompatibility = false }
        } else if dashboardSection == .launch, pendingScrollToSteamSettings {
            target = CosmosScrollAnchor.steamSettings
            clearRequest = { pendingScrollToSteamSettings = false }
        } else if dashboardSection == .launch, pendingScrollToPerformanceGraphics {
            target = CosmosScrollAnchor.performanceGraphics
            clearRequest = { pendingScrollToPerformanceGraphics = false }
        } else if dashboardSection == .bottles, pendingScrollToBottles {
            target = CosmosScrollAnchor.bottles
            clearRequest = { pendingScrollToBottles = false }
        } else {
            return
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            proxy.scrollTo(target, anchor: .top)
        }
        DispatchQueue.main.async(execute: clearRequest)
    }

    func openSteamSettings() {
        if !isSteamReady { showAdvancedSetupOptions = true }
        showLaunchSettings = true
        focusDashboardSection(.launch)
        consoleExpanded = true
        pendingScrollToSteamSettings = true
    }

    func openPerformanceGraphicsSettings(expandAdvanced: Bool = false) {
        if !isSteamReady { showAdvancedSetupOptions = true }
        showLaunchSettings = true
        focusDashboardSection(.launch)
        consoleExpanded = true
        if expandAdvanced {
            showAdvancedGraphics = true
        }
        pendingScrollToPerformanceGraphics = true
    }

    func revealSteamConf() {
        SteamSettingsStore.ensureOnDisk()
        revealInFinder(SteamSettingsStore.confURL)
    }

    func focusGameLibrary(
        scrollToLibrary: Bool = false,
        scrollToProfiles: Bool = false,
        scrollToRepair: Bool = false,
        scrollToCompatibility: Bool = false
    ) {
        focusDashboardSection(.library)
        consoleExpanded = true
        if scrollToLibrary {
            pendingScrollToGameLibrary = true
        }
        if scrollToProfiles {
            pendingScrollToGameProfiles = true
        }
        if scrollToRepair {
            pendingScrollToRepair = true
        }
        if scrollToCompatibility {
            pendingScrollToCompatibility = true
        }
    }

    func focusToolsSection() {
        focusDashboardSection(.tools)
        consoleExpanded = true
    }

    func menuContinueSetup() {
        focusDashboardSection(.launch)
        consoleExpanded = true
        performNextSetupStep()
    }

    func openAddGameProfile() {
        focusGameLibrary(scrollToProfiles: true)
        showAddGameProfileSheet = true
    }

    func showSelectedProfileInLibrary() {
        guard selectedProfile != nil else { return }
        focusGameLibrary(scrollToLibrary: true)
    }

    func showSelectedProfileOnLaunch() {
        guard selectedProfile != nil else { return }
        focusDashboardSection(.launch)
    }

    func openImportTools() {
        focusToolsSection()
        pendingScrollToImport = true
    }

    func findSavedLauncher(for profile: GameProfile) -> SavedProfile? {
        if !profile.steamAppID.isEmpty,
           let match = profiles.first(where: { $0.steamAppID == profile.steamAppID }) {
            return match
        }
        if !profile.gogSlug.isEmpty,
           let match = profiles.first(where: { $0.gogSlug?.lowercased() == profile.gogSlug.lowercased() }) {
            return match
        }
        return profiles.first { $0.name.localizedCaseInsensitiveCompare(profile.name) == .orderedSame }
    }

    func showSavedLauncherInLibrary(_ profile: SavedProfile) {
        selectedProfileID = profile.id
        focusGameLibrary(scrollToLibrary: true)
    }

    func runDiagnose() {
        runCommand(
            script: "repair.command",
            arguments: ["diagnose"],
            environment: repairEnvironment(),
            intent: .diagnose
        )
    }

    func profileContextMenuExtras(for profile: SavedProfile, inLibrary: Bool = false) -> ProfileContextMenuExtras {
        ProfileContextMenuExtras(
            onShowInLibrary: inLibrary ? nil : {
                selectedProfileID = profile.id
                focusGameLibrary(scrollToLibrary: true)
            },
            onShowOnLaunch: {
                selectedProfileID = profile.id
                focusDashboardSection(.launch)
            },
            onApplyCurated: {
                focusGameLibrary(scrollToProfiles: true)
                if let appid = profile.steamAppID, !appid.isEmpty,
                   let curated = GameProfileStore.find(steamAppID: appid) {
                    applyCuratedGameProfile(curated)
                } else if let slug = profile.gogSlug, !slug.isEmpty {
                    runCommand(
                        script: "profile.command",
                        arguments: ["for-gog-slug", slug, "apply"],
                        environment: bottleEnvironment()
                    )
                }
            },
            onVerifyInstall: profile.libraryStore == .steam ? {
                focusGameLibrary(scrollToLibrary: true)
                verifySteamInstall()
            } : nil
        )
    }

    func applyCuratedGameProfile(_ profile: GameProfile) {
        let path = profile.fileURL.path
        let arguments: [String]
        if let relative = CosmosPaths.profileCommandPath(for: profile.fileURL) {
            arguments = ["apply", relative]
        } else {
            arguments = ["apply", path]
        }
        runCommand(
            script: "profile.command",
            arguments: arguments,
            environment: bottleEnvironment()
        )
    }

    func compatLookupForGameProfile(_ profile: GameProfile) {
        guard !profile.steamAppID.isEmpty else { return }
        selectedGameProfileID = profile.id
        setupCompatAppID = profile.steamAppID
        focusGameLibrary(scrollToCompatibility: true)
        runCommand(script: "cosmosdb.command", arguments: ["lookup", profile.steamAppID])
    }

    func applyInstalledCuratedProfiles() {
        runCommand(
            script: "profile.command",
            arguments: ["apply-installed"],
            environment: bottleEnvironment()
        )
    }

    func sidebarCompatBadge(for profile: SavedProfile) -> ResolvedBadge? {
        guard let appid = profile.steamAppID, !appid.isEmpty else { return nil }
        let resolved = CosmosBadgeStore.resolve(
            steamAppID: appid,
            curated: GameProfileStore.find(steamAppID: appid)
        )
        return resolved.isKnown ? resolved : nil
    }

    func sidebarProfileAccessibilityLabel(_ profile: SavedProfile, badge: ResolvedBadge?) -> String {
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

    func profileSubtitle(_ profile: SavedProfile) -> String {
        if !profile.args.isEmpty { return profile.args }
        if !profile.path.isEmpty { return profile.path }
        if let appid = profile.steamAppID, !appid.isEmpty {
            return "Steam App ID \(appid)"
        }
        return profile.launchMethodLabel
    }

    /// Reveal a file in Finder, selecting it in its enclosing folder.
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    var wineRuntimeSection: some View {
        Group {
            if wineRuntime.needsRosetta && !wineRuntime.rosettaReady {
                CosmosNoticeBanner(
                    tint: Color.cosmosWarning,
                    systemImage: "cpu",
                    title: "Rosetta 2 required",
                    message: "Cosmos downloads x86_64 Wine builds from Gcenx. Apple Silicon Macs need Rosetta 2 before Wine can run. Install Rosetta, then continue setup."
                )
            } else if !wineRuntime.wineInstalled {
                CosmosNoticeBanner(
                    tint: Color.cosmosPrimary,
                    systemImage: "wineglass",
                    title: "Wine not downloaded yet",
                    message: "Run Prepare Steam Environment to download Wine \(wineRuntime.wineVersion). \(wineRuntime.translationNote)"
                )
            }
        }
    }

    func selectedGameExperience(_ profile: SavedProfile) -> some View {
        CosmosGameLaunchPanel(
            profile: profile,
            compatibility: sidebarCompatBadge(for: profile)?.status,
            environmentName: selectedBottle?.name ?? "Default Windows environment",
            canLaunch: profile.canLaunchFromDashboard && wineRuntime.canStartWineLaunch,
            isBusy: isRunning || pendingTerminalJobID != nil,
            isFavorite: ProfilePreferencesStore.isFavorite(profileID: profile.id, in: profilePreferences),
            onPlay: { launchProfile(profile) },
            onFavorite: { profilePreferences = ProfilePreferencesStore.toggleFavorite(profileID: profile.id) }
        )
    }

    var launchSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .font(.title2)
                .foregroundStyle(Color.cosmosPrimary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Steam").font(.headline)
                Text("Install games and manage downloads in Steam.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(launchSteamButtonTitle, action: launchSteamFromDashboard)
                .buttonStyle(.bordered)
                .disabled(!wineRuntime.canStartWineLaunch || isRunning || pendingTerminalJobID != nil)
                .help(launchSteamButtonHelp)
        }
        .cosmosCard()
    }

    // MARK: - Steam Wine settings

    var steamWineSettingsSection: some View {
        CosmosSection(
            title: "Steam & Wine",
            systemImage: "gearshape.2.fill",
            caption: "Graphics mode, Windows version, and how Steam installs."
        ) {
            if let bottle = selectedBottle {
                CosmosNoticeBanner(
                    tint: Color.cosmosInfo,
                    systemImage: "cylinder.split.1x2.fill",
                    title: "Launches use bottle: \(bottle.name)",
                    message: "These settings apply to the default Steam setup. Adjust \(bottle.name) on the Bottles tab, or choose Use Default Bottle from the toolbar bottle chip."
                )
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Graphics backend")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                            .textCase(.uppercase)
                        Picker("Backend", selection: steamBackendBinding) {
                            ForEach(SteamSettingsStore.backendOptions, id: \.self) { backend in
                                Text(SettingLabels.backendDisplayName(backend)).tag(backend)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 240, alignment: .leading)
                        .disabled(isRunning)
                        .accessibilityLabel("Graphics backend")
                        .accessibilityValue(SettingLabels.backendDisplayName(steamSettings.backend))
                        if let caption = SettingLabels.backendCaption(steamSettings.backend) {
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Windows version")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                            .textCase(.uppercase)
                        Picker("Windows", selection: steamWindowsBinding) {
                            Text("Wine default").tag("")
                            ForEach(SteamSettingsStore.windowsOptions.filter { !$0.isEmpty }, id: \.self) {
                                Text(SettingLabels.windowsDisplayName($0)).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 200, alignment: .leading)
                        .disabled(isRunning)
                        .accessibilityLabel("Windows version")
                        .accessibilityValue(steamSettings.windowsDisplay)
                    }
                }

                if steamSettings.backend == "spockd3d9", !spockD3D9Validation.valid {
                    CosmosNoticeBanner(
                        tint: Color.cosmosWarning,
                        systemImage: "exclamationmark.triangle.fill",
                        title: "SpockD3D9 not ready",
                        message: graphicsSettings.spockD3D9Configured
                            ? (spockD3D9Validation.errorMessage.isEmpty
                                ? "Validate SPOCK_D3D9_PATH in Performance & Graphics before launching."
                                : spockD3D9Validation.errorMessage)
                            : "Build or set SPOCK_D3D9_PATH in Performance & Graphics — classic D3D9 games often need the 32-bit DLL (--arch x86)."
                    )
                } else if steamSettings.backend == "d3dmetal", !gptkValidation.valid {
                    CosmosNoticeBanner(
                        tint: Color.cosmosWarning,
                        systemImage: "exclamationmark.triangle.fill",
                        title: "GPTK not configured",
                        message: "Set and validate GPTK_PATH in Performance & Graphics for D3D12 titles."
                    )
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
                .accessibilityHint("Applies on the next Steam or game launch")

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

                HStack(spacing: 12) {
                    Button {
                        revealSteamConf()
                    } label: {
                        Label("Reveal steam.conf", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRunning)
                    .help("Open ~/Library/Application Support/Cosmos/steam.conf in Finder")
                }
                .font(.subheadline)
            }
            .cosmosCard()
        }
        .id(CosmosScrollAnchor.steamSettings)
    }

    // MARK: - Performance & graphics (Phase E)

    var performanceGraphicsSection: some View {
        CosmosSection(
            title: "Performance & Graphics",
            systemImage: "speedometer",
            caption: "The defaults work for most games. OpenGL and store logins are folded up below."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                DisclosureGroup(isExpanded: $showD3D9Guidance) {
                    D3D9EscalationLadder()
                        .padding(.top, 8)
                } label: {
                    Label("Direct3D 9 troubleshooting", systemImage: "9.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.cosmosPrimary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Thread sync")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                        .textCase(.uppercase)
                    Picker("Thread sync", selection: syncModeBinding) {
                        ForEach(GraphicsSettings.syncModeOptions, id: \.self) { mode in
                            Text(GraphicsSettings.syncModeTitle(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRunning)
                    .accessibilityLabel("Thread sync mode")
                    .accessibilityValue(GraphicsSettings.syncModeTitle(graphicsSettings.syncMode))
                    Text(graphicsSettings.syncModeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                spockD3d9SetupCard

                Divider()

                gptkSetupCard

                Divider()

                DisclosureGroup(isExpanded: $showOpenGLFix) {
                    moonshineGraphicsCard
                        .padding(.top, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("OpenGL 3.2", systemImage: "cube.transparent")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.cosmosPrimary)
                        Text("For games that cannot open a graphics window")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup(isExpanded: $showStoreLaunch) {
                    sojuLaunchCard
                        .padding(.top, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Battle.net, Epic, and GOG", systemImage: "bag")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.cosmosPrimary)
                        Text("Sign-in, Apple Silicon, and DirectX 12")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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
                            .accessibilityLabel("DXMT channel")
                            .accessibilityValue(graphicsSettings.dxmtChannel == "latest" ? "Latest LGPL" : "Pinned 0.80")
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
                            .accessibilityLabel("MoltenVK preset for DXVK")
                            .accessibilityValue(graphicsSettings.moltenvkPreset)
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
        .id(CosmosScrollAnchor.performanceGraphics)
    }

    var spockD3d9SetupCard: some View {
        GraphicsPathSetupCard(
            title: "D3D9 — SpockD3D9",
            caption: "Experimental DirectX 9 support. Classic games often need the 32-bit DLL, even on a 64-bit Mac. MoltenVK is also required. Test in a separate environment against WineD3D.",
            fieldLabel: "Spock DLL folder",
            path: spockD3D9PathBinding,
            isReady: spockD3D9Validation.valid,
            isInvalid: graphicsSettings.spockD3D9Configured && !spockD3D9Validation.valid,
            summaryText: spockD3D9Validation.valid ? spockD3D9Validation.summaryText : nil,
            errorText: spockD3D9Validation.valid ? nil : spockD3D9Validation.errorMessage,
            isRunning: isRunning,
            readyLabel: "DLLs validated",
            onBrowse: browseForSpockD3D9Path
        ) {
            Button { validateSpockD3D9Path() } label: {
                Label("Validate", systemImage: "checkmark.shield")
            }
            .buttonStyle(.bordered)
            .disabled(isRunning || !graphicsSettings.spockD3D9Configured)

            Button { buildSpockD3D9Dlls() } label: {
                Label("Build 32-bit + 64-bit DLLs", systemImage: "hammer.fill")
            }
            .buttonStyle(.bordered)
            .disabled(isRunning)

            Button { saveSpockD3D9PathAndApply() } label: {
                Label(selectedBottle.map { "Use for \($0.name)" } ?? "Use for Default Environment", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cosmosPrimary)
            .disabled(isRunning || !spockD3D9Validation.valid)

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
    }

    var gptkSetupCard: some View {
        GraphicsPathSetupCard(
            title: "D3D12 — Game Porting Toolkit",
            caption: "Apple's GPTK is not bundled. Download from developer.apple.com, then point Cosmos at the install folder for D3D12 titles.",
            fieldLabel: "GPTK_PATH",
            path: gptkPathBinding,
            isReady: gptkValidation.valid,
            isInvalid: graphicsSettings.gptkConfigured && !gptkValidation.valid,
            summaryText: gptkValidation.valid
                ? "Found \(gptkValidation.dllCount) DLL(s) in \(gptkValidation.dllDirectory)"
                : nil,
            errorText: gptkValidation.valid ? nil : gptkValidation.errorMessage,
            isRunning: isRunning,
            onBrowse: browseForGptkPath
        ) {
            Button { validateGptkPath() } label: {
                Label("Validate", systemImage: "checkmark.shield")
            }
            .buttonStyle(.bordered)
            .disabled(isRunning || !graphicsSettings.gptkConfigured)

            Button { saveGptkPathAndTest() } label: {
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
    }

    var moonshineGraphicsCard: some View {
        MoonshineGraphicsCard(
            preset: graphicsSettings.wineDebugPreset,
            status: openGLStatus,
            isRunning: isRunning,
            onPresetChange: { applyGraphicsSetting(key: "COSMOS_WINEDEBUG_PRESET", value: $0) },
            onCheck: { runOpenGLCommand("--opengl-status") },
            onApply: { runOpenGLCommand("--opengl-patch") },
            onUndo: { runOpenGLCommand("--opengl-revert") },
            onGuide: {
                openRepositoryDoc(
                    relativePath: "docs/MOONSHINE.md",
                    bundleName: "MOONSHINE.md",
                    fallbackMessage: "See docs/MOONSHINE.md in the Cosmos repository."
                )
            }
        )
    }

    func runOpenGLCommand(_ flag: String) {
        runCommand(script: "run.command", arguments: [flag]) { _, _ in
            openGLStatus = GraphicsSettingsStore.parseOpenGLStatus(output)
        }
    }

    var sojuLaunchCard: some View {
        SojuLaunchCard(
            rosettaAvx: graphicsSettings.rosettaAvx,
            wineWritecopy: graphicsSettings.wineWritecopy,
            status: sojuStatus,
            isRunning: isRunning,
            onAvxChange: { applyGraphicsSetting(key: "COSMOS_ROSETTA_AVX", value: $0) },
            onWritecopyChange: { applyGraphicsSetting(key: "COSMOS_WINE_WRITECOPY", value: $0) },
            onCheckLayout: { runSojuCommand("--gptk-layout-status") },
            onInstallLayout: { runSojuCommand("--gptk-layout") },
            onUndoLayout: { runSojuCommand("--gptk-layout-revert") },
            onSeedBattleNet: { runSojuCommand("--battlenet-seed") },
            onGuide: {
                openRepositoryDoc(
                    relativePath: "docs/SOJU.md",
                    bundleName: "SOJU.md",
                    fallbackMessage: "See docs/SOJU.md in the Cosmos repository."
                )
            }
        )
    }

    func runSojuCommand(_ flag: String) {
        runCommand(script: "run.command", arguments: [flag]) { _, _ in
            sojuStatus = GraphicsSettingsStore.parseSojuStatus(output)
        }
    }

    var syncModeBinding: Binding<String> {
        Binding(
            get: { graphicsSettings.syncMode },
            set: { applyGraphicsSetting(key: "COSMOS_SYNC_MODE", value: $0) }
        )
    }

    var dxmtChannelBinding: Binding<String> {
        Binding(
            get: { graphicsSettings.dxmtChannel },
            set: { applyGraphicsSetting(key: "COSMOS_DXMT_CHANNEL", value: $0) }
        )
    }

    var moltenvkPresetBinding: Binding<String> {
        Binding(
            get: { graphicsSettings.moltenvkPreset },
            set: { applyGraphicsSetting(key: "COSMOS_MVK_PRESET", value: $0) }
        )
    }

    var metalFXBinding: Binding<Bool> {
        Binding(
            get: { graphicsSettings.metalFXEnabled },
            set: { applyGraphicsSetting(key: "COSMOS_METALFX", value: $0 ? "1" : "0") }
        )
    }

    var spockD3D9PathBinding: Binding<String> {
        Binding(
            get: { graphicsSettings.spockD3D9Path },
            set: {
                graphicsSettings.spockD3D9Path = $0
                spockD3D9Validation = .empty
            }
        )
    }

    var gptkPathBinding: Binding<String> {
        Binding(
            get: { graphicsSettings.gptkPath },
            set: { graphicsSettings.gptkPath = $0 }
        )
    }

    func applyGraphicsSetting(key: String, value: String) {
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

    func reloadGraphicsSettings() {
        graphicsSettings = GraphicsSettingsStore.loadSteam()
        if let bottle = selectedBottle {
            graphicsSettings.spockD3D9Path = bottle.settings["SPOCK_D3D9_PATH"] ?? ""
        }
        if graphicsSettings.spockD3D9Path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let defaultPath = CosmosPaths.defaultSpockD3D9Directory.path
            if fileManager.fileExists(atPath: defaultPath) {
                graphicsSettings.spockD3D9Path = defaultPath
            }
        }
        if graphicsSettings.gptkConfigured {
            gptkValidation = GraphicsSettingsStore.validateGptkPath(
                graphicsSettings.gptkPath,
                repositoryRoot: repositoryRootURL
            )
        } else {
            gptkValidation = .empty
        }
        if graphicsSettings.spockD3D9Configured {
            spockD3D9Validation = GraphicsSettingsStore.validateSpockD3D9Path(
                graphicsSettings.spockD3D9Path,
                repositoryRoot: repositoryRootURL
            )
        } else {
            spockD3D9Validation = .empty
        }
    }

    func browseForSpockD3D9Path() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the folder containing SpockD3D9 PE d3d9.dll files"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        graphicsSettings.spockD3D9Path = url.path
        validateSpockD3D9Path()
    }

    func validateSpockD3D9Path() {
        let path = graphicsSettings.spockD3D9Path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            spockD3D9Validation = .empty
            return
        }
        spockD3D9Validation = GraphicsSettingsStore.validateSpockD3D9Path(path, repositoryRoot: repositoryRootURL)
    }

    func downloadComponent(_ component: CosmosDownload) {
        guard !isRunning, pendingTerminalJobID == nil else { return }
        lastDownload = component
        downloadResult = nil
        downloadFailed = false
        downloadInProgress = true
        runCommand(
            script: "run.command",
            arguments: component.arguments,
            onCompletion: { succeeded, message in
                downloadInProgress = false
                downloadOutput = output
                downloadFailed = !succeeded
                downloadResult = succeeded
                    ? "\(component.title) is available. Continue setup or choose it in Graphics settings."
                    : message
                if succeeded {
                    downloadedComponents.insert(component)
                    if component == .recommended {
                        downloadedComponents.formUnion([.wine, .dxmt])
                    } else if component == .dxvk {
                        downloadedComponents.insert(.moltenvk)
                    } else if component == .spock {
                        applyBuiltSpockD3D9Path()
                    }
                }
            }
        )
    }

    func buildSpockD3D9Dlls() {
        runCommand(
            script: "run.command",
            arguments: ["--build-spockd3d9", "--arch", "both"],
            environment: dashboardLaunchEnvironment(),
            onSuccess: { applyBuiltSpockD3D9Path() }
        )
    }

    func applyBuiltSpockD3D9Path() {
        let defaultPath = CosmosPaths.defaultSpockD3D9Directory.path
        graphicsSettings.spockD3D9Path = defaultPath
        validateSpockD3D9Path()
        if spockD3D9Validation.valid {
            showD3D9Guidance = false
        }
    }

    func saveSpockD3D9PathAndApply() {
        let path = graphicsSettings.spockD3D9Path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !isRunning, pendingTerminalJobID == nil else { return }
        validateSpockD3D9Path()
        guard spockD3D9Validation.valid else { return }
        if let bottle = selectedBottle {
            runCommand(
                script: "bottle.command",
                arguments: ["set", bottle.name, "SPOCK_D3D9_PATH", path],
                onSuccess: {
                    runCommand(
                        script: "bottle.command",
                        arguments: ["set", bottle.name, "COSMOS_BACKEND", "spockd3d9"]
                    )
                }
            )
        } else {
            do {
                try SteamSettingsStore.set(key: "SPOCK_D3D9_PATH", value: path)
                applySteamSetting(key: "COSMOS_BACKEND", value: "spockd3d9")
                reloadGraphicsSettings()
            } catch {
                showBanner(kind: .failure, message: "Could not save SpockD3D9 path: \(error.localizedDescription)")
            }
        }
    }

    func browseForGptkPath() {
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

    func validateGptkPath() {
        let path = graphicsSettings.gptkPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            gptkValidation = .empty
            return
        }
        gptkValidation = GraphicsSettingsStore.validateGptkPath(path, repositoryRoot: repositoryRootURL)
    }

    func saveGptkPathAndTest() {
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

    var steamBackendBinding: Binding<String> {
        Binding(
            get: { steamSettings.backend },
            set: { applySteamSetting(key: "COSMOS_BACKEND", value: $0) }
        )
    }

    var steamWindowsBinding: Binding<String> {
        Binding(
            get: { steamSettings.windowsVersion },
            set: { applySteamSetting(key: "WINDOWS_VERSION", value: $0) }
        )
    }

    var steamRetinaBinding: Binding<Bool> {
        Binding(
            get: { steamSettings.retinaEnabled },
            set: { applySteamSetting(key: "WINE_RETINA_MODE", value: $0 ? "1" : "0") }
        )
    }

    var steamDetachBinding: Binding<Bool> {
        Binding(
            get: { steamSettings.detachEnabled },
            set: { applySteamSetting(key: "COSMOS_DETACH", value: $0 ? "1" : "0") }
        )
    }

    var steamSilentBinding: Binding<Bool> {
        Binding(
            get: { steamSettings.silentInstallEnabled },
            set: { applySteamSetting(key: "COSMOS_STEAM_SILENT", value: $0 ? "1" : "0") }
        )
    }

    var steamNativeScanBinding: Binding<Bool> {
        Binding(
            get: { steamSettings.nativeSteamScanEnabled },
            set: {
                applySteamSetting(key: "COSMOS_STEAM_NATIVE_SCAN", value: $0 ? "1" : "0")
                refreshSteamHealth()
            }
        )
    }

    func applySteamSetting(key: String, value: String) {
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
    var gameDiscoveryButtons: some View {
        CosmosSecondaryActionButton(title: "Preview Detected Games", subtitle: "List Steam library", systemImage: "magnifyingglass", isRunning: isRunning, help: "Scan the Steam library and list installable titles in the output pane") {
            runCommand(script: "detect_steam_games.command", arguments: ["--list"], environment: steamDetectionEnvironment())
        }

        CosmosSecondaryActionButton(title: "Verify Detection", subtitle: "Check install folders", systemImage: "checkmark.shield.fill", isRunning: isRunning, help: "List games and verify each installdir exists on disk") {
            runCommand(script: "detect_steam_games.command", arguments: ["--verify"], environment: steamDetectionEnvironment())
        }

        CosmosSecondaryActionButton(title: "Create Dock Shortcuts", subtitle: "Find games and add shortcuts", systemImage: "square.grid.2x2.fill", isRunning: isRunning, help: "Detect games and install Spotlight launchers into Cosmos Apps") {
            buildLaunchers()
        }

        if pendingBrokenSteamInstalls > 0 {
            CosmosSecondaryActionButton(
                title: "Verify Broken Installs",
                subtitle: "\(pendingBrokenSteamInstalls) need attention",
                systemImage: "exclamationmark.triangle.fill",
                isRunning: isRunning,
                help: "List Wine Steam games with missing install folders or game executables"
            ) {
                runCommand(script: "run.command", arguments: ["--verify-steam"], environment: bottleEnvironment())
            }
        } else if pendingNewSteamGames > 0 {
            CosmosSecondaryActionButton(
                title: "Sync New Games",
                subtitle: "\(pendingNewSteamGames) detected",
                systemImage: "arrow.triangle.2.circlepath",
                isRunning: isRunning,
                help: "Build launchers for newly installed Steam games only"
            ) {
                syncSteamLibrary(announce: true)
            }
        } else {
            CosmosSecondaryActionButton(
                title: "Add New Steam Games",
                subtitle: "New installs only",
                systemImage: "arrow.triangle.2.circlepath",
                isRunning: isRunning,
                help: "Build launchers for newly installed Steam games since the last sync"
            ) {
                syncSteamLibrary(announce: true)
            }
        }

        if pendingUnregisteredGogGames > 0 {
            CosmosSecondaryActionButton(
                title: "Add GOG Games",
                subtitle: "\(pendingUnregisteredGogGames) unregistered",
                systemImage: "opticaldisc.fill",
                isRunning: isRunning,
                help: "Create launcher configs for detected GOG installs"
            ) {
                syncGogLibrary(build: false, announce: true)
            }
        }
    }
}
