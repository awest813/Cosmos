import Foundation
import AppKit
import SwiftUI

extension ContentView {
    // MARK: - Console

    var consoleSection: some View {
        DisclosureGroup(isExpanded: $consoleExpanded) {
            consoleOutputPanel
                .onAppear { consoleHasNewOutput = false }
        } label: {
            HStack(spacing: 8) {
                Label("Activity & Logs", systemImage: "terminal")
                    .font(.subheadline.weight(.semibold))
                if consoleHasNewOutput && !consoleExpanded {
                    Text("Updated").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: consoleExpanded) { expanded in
            if expanded { consoleHasNewOutput = false }
        }
    }

    var consoleOutputPanel: some View {
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
                    openLatestLogs()
                } label: {
                    Label("Open Logs", systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isRunning)
                .help("Open the most recent launch log in Finder")
                .accessibilityLabel("Open logs")
                Button {
                    copyOutputToClipboard()
                } label: {
                    Label(didCopyOutput ? "Copied" : "Copy", systemImage: didCopyOutput ? "checkmark.circle" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(didCopyOutput ? Color.cosmosSuccess : .secondary)
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
                    message: "Earlier log lines were trimmed to keep the view responsive. Copy output or open Logs to view the full history in Finder."
                )
            }

            ScrollViewReader { proxy in
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Latest") {
                        // Scroll only from a user action, never from a layout or
                        // output-update callback. macOS can invalidate the proxy
                        // during those callbacks and trap.
                        proxy.scrollTo(consoleBottomID, anchor: .bottom)
                    }
                    .controlSize(.small)
                    .disabled(output.isEmpty)
                    .help("Jump to the latest activity")
                    CosmosConsolePanel(minHeight: isSetupComplete ? 220 : 140) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                CosmosGroupedConsoleOutput(
                                    output: output,
                                    isRunning: isRunning,
                                    font: CosmosTypography.monoBody,
                                    textColor: Color.cosmosConsoleText
                                )
                                .accessibilityLabel("Command output log")
                                .accessibilityValue(output.isEmpty ? "Empty" : output)
                                Color.clear.frame(height: 1).id(consoleBottomID)
                            }
                            .padding(16)
                        }
                        .frame(height: isSetupComplete ? 260 : 180)
                    }
                }
            }
        }
    }

    var setupCompleteBanner: some View {
        VStack(alignment: .leading, spacing: CosmosSpacing.sectionInner) {
            CosmosNoticeBanner(
                tint: Color.cosmosSuccess,
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

    var setupCompleteBannerMessage: String {
        var message = "Launch Steam or pick a saved profile in the sidebar. Game launchers are in /Applications/Cosmos Apps."
        if !installedCuratedProfiles.isEmpty {
            message += " \(installedCuratedProfiles.count) installed title\(installedCuratedProfiles.count == 1 ? "" : "s") have curated Cosmos presets — apply them for known-good backends and fixes."
        }
        return message
    }

    func openSetupHelp() {
        openRepositoryDoc(
            relativePath: "docs/STEAM_SETUP.md",
            bundleName: "STEAM_SETUP.md",
            fallbackMessage: "Setup guide not found. See docs/STEAM_SETUP.md in the Cosmos repository."
        )
    }

    func openMultiplayerHelp() {
        openRepositoryDoc(
            relativePath: "docs/MULTIPLAYER.md",
            bundleName: "MULTIPLAYER.md",
            fallbackMessage: "Multiplayer guide not found. See docs/MULTIPLAYER.md in the Cosmos repository."
        )
    }

    var includedLauncherAvailability: [String: IncludedLauncherAvailability] {
        Dictionary(uniqueKeysWithValues: IncludedLaunchers.all.map { launcher in
            let source = includedLauncherSourceURL(launcher)
            return (
                launcher.id,
                IncludedLauncherAvailability(
                    hasSource: source != nil,
                    canBuild: source != nil && resolveScript(launcher.buildScript) != nil
                )
            )
        })
    }

    func includedLauncherSourceURL(_ launcher: IncludedLauncher) -> URL? {
        guard let root = repositoryRootURL else { return nil }
        let url = root.appendingPathComponent(launcher.sourceFolder, isDirectory: true)
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return url
    }

    var includedLaunchersSection: some View {
        CosmosSection(
            title: IncludedLaunchers.title,
            systemImage: "square.stack.3d.up.fill",
            caption: IncludedLaunchers.caption
        ) {
            includedLauncherCards
        }
    }

    var includedLaunchersDisclosure: some View {
        DisclosureGroup(isExpanded: $showIncludedLaunchers) {
            VStack(alignment: .leading, spacing: 10) {
                Text(IncludedLaunchers.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                includedLauncherCards
            }
            .padding(.top, CosmosSpacing.sectionInner)
        } label: {
            Label(IncludedLaunchers.title, systemImage: "square.stack.3d.up.fill")
                .font(.headline)
        }
    }

    var includedLauncherCards: some View {
        IncludedLaunchersCards(
            isRunning: isRunning,
            availability: includedLauncherAvailability,
            onGuide: openIncludedLauncherGuide,
            onReveal: revealIncludedLauncher,
            onBuild: { launcher in
                runCommand(script: launcher.buildScript)
            }
        )
    }

    func openIncludedLauncherGuide(_ launcher: IncludedLauncher) {
        openRepositoryDoc(
            relativePath: launcher.guideRelativePath,
            bundleName: launcher.guideBundleName,
            fallbackMessage: launcher.guideFallback
        )
    }

    func revealIncludedLauncher(_ launcher: IncludedLauncher) {
        guard let url = includedLauncherSourceURL(launcher) else { return }
        revealInFinder(url)
    }

    func openRepositoryDoc(relativePath: String, bundleName: String, fallbackMessage: String) {
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

    func copyOutputToClipboard() {
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

    var steamPrefixStatusLabel: String {
        if steamSettings.isSteamInstalled { return "Steam ready" }
        if steamSettings.isPrefixInitialized { return "Prefix ready — install Steam" }
        return "Steam bottle not prepared"
    }

    var statusSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if wineRuntime.needsRosetta {
                statusRow(
                    label: wineRuntime.rosettaLabel,
                    icon: wineRuntime.rosettaReady ? "checkmark.circle.fill" : "cpu",
                    color: wineRuntime.rosettaReady ? Color.cosmosSuccess : Color.cosmosWarning
                )
            }
            statusRow(
                label: wineRuntime.wineLabel,
                icon: wineRuntime.wineInstalled ? "wineglass.fill" : "arrow.down.circle",
                color: wineRuntime.wineInstalled ? Color.cosmosBright : Color.secondary
            )
            statusRow(
                label: cosmosInstalled ? "Launchers configured" : "Launcher setup needed",
                icon: cosmosInstalled ? "checkmark.circle.fill" : "arrow.down.circle",
                color: cosmosInstalled ? Color.cosmosSuccess : Color.cosmosWarning
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
                        color: Color.cosmosWarning
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
                        color: Color.cosmosWarning
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
                        color: Color.cosmosWarning
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
                        color: Color.cosmosWarning
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

    func statusRow(label: String, icon: String, color: Color) -> some View {
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

    func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.cosmosPrimary)
    }

    func detailRow(title: String, value: String) -> some View {
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

    func refreshStatus(message: String? = nil) {
        SteamSettingsStore.ensureOnDisk()
        cosmosInstalled = SavedProfileStore.cosmosAppsIsInstalled()
        cosmosAppCount = SavedProfileStore.countCosmosApps()
        steamSettings = SteamSettingsStore.load()
        wineRuntime = WineRuntimeStore.load(wineVersion: steamSettings.wineVersion)
        profiles = SavedProfileStore.load()
        profilePreferences = ProfilePreferencesStore.prune(validProfileIDs: Set(profiles.map(\.id)))
        bottles = BottleStore.load()
        ports = WinePortStore.load()
        reloadGraphicsSettings()
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
        appState.updateSteamReady(isSteamReady)
        appState.updateCommandAvailability(
            canAccept: !isRunning,
            canLaunchSelected: selectedProfileCanLaunch && wineRuntime.canStartWineLaunch,
            hasSelected: selectedProfile != nil
        )

        if let message {
            output = message + "\n\n" + output
        }
    }

    func refreshCompatBadge() {
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
    func bottleEnvironment() -> [String: String] {
        var env: [String: String] = [
            "COSMOS_CONFIGS_DIR": CosmosPaths.resolvedConfigsDirectory().path,
        ]
        if let bottle = selectedBottle {
            env["COSMOS_BOTTLE"] = bottle.name
            env["WINEPREFIX"] = bottle.prefixURL.path
        } else {
            env["WINEPREFIX"] = steamSettings.prefixURL.path
        }
        if steamSettings.nativeSteamScanEnabled {
            env["COSMOS_STEAM_NATIVE_SCAN"] = "1"
        }
        return env
    }

    // Locate a helper script, preferring a copy bundled into the app's
    // Resources (installed Cosmos.app) and falling back to the repository
    // checkout (running from a development build).
    func resolveScript(_ script: String) -> URL? {
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
    func runInTerminal(
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
        activeOperationTitle = CosmosOperationLabel.title(script: script, arguments: arguments)
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

    func watchTerminalJob(jobID: String, displayedCommand: String, intent: CommandIntent) {
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

    func resumeTerminalJobs() {
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
            activeOperationTitle = "Waiting for Terminal…"
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

    func deliverTerminalJobResult(
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

    func checkForUpdatesSilently() {
        guard let scriptURL = resolveScript("run.command") else { return }
        DispatchQueue.global(qos: .utility).async {
            let status = UpdateChecker.check(runScript: scriptURL)
            DispatchQueue.main.async {
                applyUpdateCheck(status, verbose: false)
            }
        }
    }

    func checkForUpdates() {
        guard let scriptURL = resolveScript("run.command") else {
            showBanner(kind: .failure, message: "Script not found: run.command")
            return
        }

        beginCommandOutput()
        output = "Running: run.command --check-update\n\n"
        activeOperationTitle = "Checking for updates…"
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

    func applyUpdateCheck(_ status: UpdateChecker.Status?, verbose: Bool) {
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

    func installUpdate() {
        runCommand(script: "run.command", arguments: ["--install-update"], intent: .setup)
    }

    func showBanner(
        kind: CommandBannerKind,
        message: String,
        actions: [CommandBannerAction] = []
    ) {
        commandBannerQueue.enqueue(
            CommandBanner(kind: kind, message: message, actions: actions)
        )
    }

    func dismissCommandBanner() {
        commandBannerQueue.dismissCurrent()
    }

    func successMessage(for intent: CommandIntent) -> String {
        switch intent {
        case .gameLaunch:
            return "Launch request completed. If no game window appears, open Logs or run Diagnose."
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

    func openLatestLogs() {
        runCommand(script: "run.command", arguments: ["--logs"])
    }

    func failureRecoveryActions(includeLogs: Bool, includeRepair: Bool = false) -> [CommandBannerAction] {
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

    func dashboardLaunchEnvironment(extra: [String: String] = [:]) -> [String: String] {
        var env = bottleEnvironment()
        // Foreground launch from the dashboard so exit codes and errors surface in-app.
        env["COSMOS_DETACH"] = "0"
        for (key, value) in extra {
            env[key] = value
        }
        return env
    }

    func beginCommandOutput() {
        commandBannerQueue.clearTransient()
        if !showDownloads { consoleExpanded = true }
    }

    func runCommand(
        script: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        intent: CommandIntent = .general,
        chain: Bool = false,
        onSuccess: (() -> Void)? = nil,
        onCompletion: ((Bool, String) -> Void)? = nil
    ) {
        guard let scriptURL = resolveScript(script) else {
            let message = "Script not found or not executable: \(script)"
            output = message
            onCompletion?(false, message)
            showBanner(kind: .failure, message: message)
            return
        }

        let displayedCommand = ([script] + arguments).joined(separator: " ")
        activeOperationTitle = CosmosOperationLabel.title(script: script, arguments: arguments)
        if chain {
            output += "\nRunning: \(displayedCommand)\n\n"
        } else {
            beginCommandOutput()
            output = "Running: \(displayedCommand)\n\n"
        }
        isRunning = true

        var mergedEnvironment = ProcessInfo.processInfo.environment
        mergedEnvironment.removeValue(forKey: "COSMOS_BOTTLE")
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        CosmosCommandRunner.run(
            executable: scriptURL,
            arguments: arguments,
            directory: scriptURL.deletingLastPathComponent(),
            environment: mergedEnvironment,
            onOutput: { text in
                output += text
                let trimmed = CommandOutputParser.trimPreservingErrors(output)
                if trimmed.trimmed {
                    output = trimmed.text
                    outputWasTrimmed = true
                }
            },
            onCompletion: { result in
                isRunning = false
                let exitCode: Int32
                switch result {
                case .success(let status):
                    exitCode = status
                case .failure(let error):
                    let message = "Failed to start: \(error.localizedDescription)"
                    output += "\n" + message
                    onCompletion?(false, message)
                    showBanner(kind: .failure, message: message)
                    refreshStatus()
                    return
                }
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
                        runLibrarySyncFollowUpIfNeeded()
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
                        onSuccess?()
                    }
                } else {
                    librarySyncFollowUp = nil
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
                onCompletion?(succeeded, succeeded ? "Download complete." :
                    CommandOutputParser.failureMessage(exitCode: exitCode, intent: intent, output: output))
                refreshStatus()
                if shouldRefreshSteamAfterCommand(script: script, arguments: arguments) {
                    refreshSteamHealth()
                    checkSteamLibraryForNewGames(autoSync: false, force: true)
                    if script == "run.command", arguments.contains("--verify-steam") {
                        lastWarnedBrokenSteamInstalls = pendingBrokenSteamInstalls
                    }
                }
            }
        )
    }

    func shouldRefreshSteamAfterCommand(script: String, arguments: [String]) -> Bool {
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
