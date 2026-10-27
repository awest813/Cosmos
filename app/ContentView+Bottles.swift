import Foundation
import AppKit
import SwiftUI

extension ContentView {
    // MARK: - Bottles

    var bottlesSection: some View {
        CosmosSection(
            title: "Bottles",
            systemImage: "cylinder.split.1x2.fill",
            caption: "Separate Windows setups, each with its own graphics mode, Windows version, and sync settings."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        newBottleName = ""
                        newBottleBackend = "recommended"
                        newBottleWindows = "win10"
                        newBottleRetina = false
                        newBottleArch = "wow64"
                        showNewBottleSheet = true
                    } label: {
                        Label("New Bottle", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunning)
                    .help("Create a new isolated Wine bottle")
                }

                if bottles.isEmpty {
                    CosmosEmptyState(
                        systemImage: "cylinder.split.1x2.fill",
                        title: "No bottles yet",
                        message: "Each bottle is an isolated Wine prefix with its own graphics backend, Windows version, and Retina settings.",
                        isRunning: isRunning,
                        actions: [(title: "Create Bottle", prominent: true, action: {
                            newBottleName = ""
                            newBottleBackend = "recommended"
                            newBottleWindows = "win10"
                            newBottleRetina = false
                        newBottleArch = "wow64"
                            showNewBottleSheet = true
                        })]
                    )
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: CosmosSpacing.gridColumnMin), spacing: CosmosSpacing.gridGap)],
                        spacing: CosmosSpacing.gridGap
                    ) {
                        ForEach(bottles) { bottle in
                            bottleCard(bottle)
                        }
                    }
                }

                if let bottle = selectedBottle {
                    bottleControls(bottle)
                }
            }
        }
        .id(CosmosScrollAnchor.bottles)
        .sheet(isPresented: $showNewBottleSheet) { newBottleSheet }
        .confirmationDialog("Reset this bottle?", isPresented: $showBottleResetConfirmation, titleVisibility: .visible) {
            Button("Reset Prefix", role: .destructive) {
                if let bottle = selectedBottle {
                    runCommand(script: "bottle.command", arguments: ["reset", bottle.name, "--force"])
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save your game first. Cosmos stops this environment, then deletes its Windows files and games. Settings and logs stay. Linked Mac folders and port definitions stay; reinstall games before using those ports. Clone the environment first if you need a backup.")
        }
        .confirmationDialog("Delete this bottle?", isPresented: $showBottleDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Bottle", role: .destructive) {
                if let bottle = selectedBottle {
                    runCommand(script: "bottle.command", arguments: ["delete", bottle.name, "--force"])
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save your game first. Cosmos stops this environment, then removes its Windows files, settings and logs. Linked Mac folders and port definitions stay. Edit or remove affected ports afterward. Clone first if you need a backup; deletion cannot be undone.")
        }
    }

    func bottleCard(_ bottle: Bottle) -> some View {
        let isSelected = bottle.id == selectedBottleID
        return BottleCard(
            bottle: bottle,
            isSelected: isSelected,
            isRunning: isRunning,
            onToggleSelection: {
                selectedBottleID = isSelected ? nil : bottle.id
            },
            onSelect: {
                selectedBottleID = bottle.id
            },
            onLaunchSteam: {
                selectedBottleID = bottle.id
                runCommand(
                    script: "bottle.command",
                    arguments: ["launch", bottle.name, "--steam"],
                    environment: dashboardLaunchEnvironment(),
                    intent: .gameLaunch
                )
            },
            onOpenLogs: {
                selectedBottleID = bottle.id
                runCommand(script: "bottle.command", arguments: ["logs", bottle.name])
            },
            onRevealPrefix: { revealInFinder(bottle.prefixURL) },
            onRevealConfig: { revealInFinder(bottle.configURL) },
            onReset: {
                selectedBottleID = bottle.id
                showBottleResetConfirmation = true
            },
            onDelete: {
                selectedBottleID = bottle.id
                showBottleDeleteConfirmation = true
            }
        )
    }

    func bottleControls(_ bottle: Bottle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bottle.name)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 8) {
                        BottleStatusChip(kind: bottle.statusKind)
                        Text(bottle.cardDetailLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    selectedBottleID = nil
                } label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Deselect bottle")
                .accessibilityLabel("Close bottle settings")
            }

            Divider()
            Button {
                storeImportRequest = .cloneEnvironment(source: bottle.name)
            } label: {
                Label("Clone Environment…", systemImage: "square.on.square")
            }
            .buttonStyle(.bordered)
            .disabled(isRunning)
            .help("Copy this environment to a new name before changing or resetting it. External linked folders are not copied.")
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Graphics backend")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                        .textCase(.uppercase)
                    Picker("Backend", selection: backendBinding(for: bottle)) {
                        ForEach(BottleStore.backendOptions, id: \.self) { backend in
                            Text(SettingLabels.backendDisplayName(backend)).tag(backend)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200, alignment: .leading)
                    .disabled(isRunning)
                    .accessibilityLabel("Graphics backend")
                    .accessibilityValue(SettingLabels.backendDisplayName(bottle.backend))
                    if let caption = SettingLabels.backendCaption(bottle.backend) {
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
                    Picker("Windows", selection: windowsBinding(for: bottle)) {
                        Text("Wine default").tag("")
                        ForEach(BottleStore.windowsOptions, id: \.self) { version in
                            Text(SettingLabels.windowsDisplayName(version)).tag(version)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 160, alignment: .leading)
                    .disabled(isRunning)
                    .accessibilityLabel("Windows version")
                    .accessibilityValue(bottle.windowsDisplay)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Programs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                        .textCase(.uppercase)
                    Picker("Programs", selection: prefixArchBinding(for: bottle)) {
                        ForEach(SettingLabels.prefixArchOptions, id: \.self) { arch in
                            Text(SettingLabels.prefixArchDisplayName(arch)).tag(arch)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200, alignment: .leading)
                    .disabled(isRunning)
                    .accessibilityLabel("Program layout")
                    .accessibilityValue(SettingLabels.prefixArchDisplayName(bottle.prefixArch))
                    Text(SettingLabels.prefixArchCaption(bottle.prefixArch))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    ForEach(GraphicsSettings.syncModeOptions, id: \.self) { mode in
                        Text(GraphicsSettings.syncModeTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isRunning)
                .accessibilityLabel("Thread sync mode")
                .accessibilityValue(GraphicsSettings.syncModeTitle(bottle.syncMode))
                Text(GraphicsSettings.syncModeLabel(for: bottle.syncMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 24) {
                detailRow(title: "Wine", value: bottle.wineVersion)
                detailRow(title: "Status", value: bottle.statusText)
            }

            detailRow(title: "Prefix", value: bottle.prefixURL.path)

            HStack(spacing: 12) {
                Button {
                    revealInFinder(bottle.configURL)
                } label: {
                    Label("Reveal bottle.conf", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.subheadline)

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

    func bottleActionButton(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        destructive: Bool = false,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let tint: Color = destructive ? Color.cosmosDanger : Color.cosmosPrimary
        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(tint.opacity(prominent ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: CosmosSpacing.buttonRadius))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .help(help ?? title)
    }

    var newBottleSheet: some View {
        VStack(alignment: .leading, spacing: CosmosSpacing.cardPadding) {
            Text(useRedesignedWorkspace ? "New Environment" : "New Bottle")
                .font(.title2.weight(.bold))
                .foregroundStyle(CosmosGradients.heroTitle)

            Text("Creates an isolated Wine prefix you can tune independently from the default bottle.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                TextField("Name", text: $newBottleName)
                    .textFieldStyle(.roundedBorder)
                    .focused($newBottleNameFocused)
                    .disabled(isRunning)
                Picker("Backend", selection: $newBottleBackend) {
                    ForEach(BottleStore.backendOptions, id: \.self) { backend in
                        Text(SettingLabels.backendDisplayName(backend)).tag(backend)
                    }
                }
                .disabled(isRunning)
                Picker("Windows version", selection: $newBottleWindows) {
                    ForEach(BottleStore.windowsOptions, id: \.self) { version in
                        Text(SettingLabels.windowsDisplayName(version)).tag(version)
                    }
                }
                .disabled(isRunning)
                Picker("Programs", selection: $newBottleArch) {
                    ForEach(SettingLabels.prefixArchOptions, id: \.self) { arch in
                        Text(SettingLabels.prefixArchDisplayName(arch)).tag(arch)
                    }
                }
                .disabled(isRunning)
                Text(SettingLabels.prefixArchCaption(newBottleArch))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Enable Retina mode", isOn: $newBottleRetina)
                    .disabled(isRunning)
            }
            .formStyle(.grouped)

            if !newBottleName.isEmpty && !BottleStore.isValidName(newBottleName) {
                CosmosNoticeBanner(
                    tint: Color.cosmosDanger,
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Invalid name",
                    message: "Use letters, digits, '.', '_' or '-' (not starting with '.', '_' or '-')."
                )
            }

            HStack {
                Spacer()
                Button("Cancel") { showNewBottleSheet = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isRunning)
                Button("Create") { createBottle() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cosmosPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!BottleStore.isValidName(newBottleName) || isRunning)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Color.cosmosContentBackground)
        .onAppear { newBottleNameFocused = true }
    }

    func backendBinding(for bottle: Bottle) -> Binding<String> {
        Binding(
            get: { selectedBottle?.backend ?? bottle.backend },
            set: { newValue in
                guard newValue != bottle.backend else { return }
                runCommand(script: "bottle.command", arguments: ["set", bottle.name, "COSMOS_BACKEND", newValue])
            }
        )
    }

    func windowsBinding(for bottle: Bottle) -> Binding<String> {
        Binding(
            get: { selectedBottle?.windowsVersion ?? bottle.windowsVersion },
            set: { newValue in
                guard newValue != bottle.windowsVersion else { return }
                runCommand(script: "bottle.command", arguments: ["set", bottle.name, "WINDOWS_VERSION", newValue])
            }
        )
    }

    func prefixArchBinding(for bottle: Bottle) -> Binding<String> {
        Binding(
            get: { selectedBottle?.prefixArch ?? bottle.prefixArch },
            set: { newValue in
                guard newValue != bottle.prefixArch else { return }
                runCommand(script: "bottle.command", arguments: ["set", bottle.name, "COSMOS_PREFIX_ARCH", newValue])
            }
        )
    }

    func retinaBinding(for bottle: Bottle) -> Binding<Bool> {
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

    func bottleSyncBinding(for bottle: Bottle) -> Binding<String> {
        Binding(
            get: { selectedBottle?.syncMode ?? bottle.syncMode },
            set: { newValue in
                guard newValue != bottle.syncMode else { return }
                runCommand(script: "bottle.command", arguments: ["set", bottle.name, "COSMOS_SYNC_MODE", newValue])
            }
        )
    }

    func createBottle() {
        let name = newBottleName.trimmingCharacters(in: .whitespaces)
        guard BottleStore.isValidName(name) else { return }
        showNewBottleSheet = false
        let args = [
            "create", name,
            "--backend", newBottleBackend,
            "--windows", newBottleWindows,
            "--arch", newBottleArch,
            "--retina", newBottleRetina ? "1" : "0",
        ]
        if useRedesignedWorkspace { workspaceEnvironmentID = .named(name) }
        else { selectedBottleID = name }
        runCommand(script: "bottle.command", arguments: args)
    }

    func selectedProfileCompactBar(_ profile: SavedProfile) -> some View {
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
            Button("Show on Launch Tab") {
                showSelectedProfileOnLaunch()
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

    func selectedProfileSection(_ profile: SavedProfile) -> some View {
        let curated = profile.steamAppID.flatMap { GameProfileStore.find(steamAppID: $0) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Selected Launcher", systemImage: "gamecontroller.fill")
                Spacer()
                if let badge = sidebarCompatBadge(for: profile) {
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

            HStack(spacing: 12) {
                Button("Copy Test Details") {
                    let backend = selectedBottle?.backend ?? steamSettings.backend
                    let report = """
                    Cosmos game test — NOT YET TESTED
                    Game: \(profile.name)
                    Steam App ID: \(profile.steamAppID ?? "Not applicable")
                    Environment: \(selectedBottle?.name ?? "Default")
                    Backend requested: \(backend)
                    Wine: \(wineRuntime.wineVersion)
                    Host: \(wineRuntime.platformDisplayName)
                    macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
                    Launch method: \(profile.launchMethodLabel)
                    Executable: \(profile.path.isEmpty ? "Steam-managed; verify game architecture separately" : profile.path)
                    Spock configured path: \(selectedBottle?.settings["SPOCK_D3D9_PATH"] ?? graphicsSettings.spockD3D9Path)
                    DLL architecture / module loading: verify with the preflight tool and launch logs
                    Render backend observed in logs: not recorded
                    Cold launch / menu / gameplay / save-load / exit-relaunch: not recorded
                    Resolution / preset / average FPS / 1% low / glitches: not recorded
                    """
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    showBanner(kind: .info, message: "Test details copied. Add observations after playing; this is not a compatibility result.")
                }
                Button("Game Testing Guide") {
                    openRepositoryDoc(relativePath: "docs/REAL_GAME_TESTING.md", bundleName: "REAL_GAME_TESTING.md", fallbackMessage: "See docs/REAL_GAME_TESTING.md in the Cosmos repository.")
                }
            }
            .buttonStyle(.bordered)

            if let curated, curated.isBlocked {
                CosmosNoticeBanner(
                    tint: Color.cosmosDanger,
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
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Button("Apply") {
                        runCommand(
                            script: "profile.command",
                            arguments: ["apply", yaml.commandRelativePath],
                            environment: bottleEnvironment()
                        )
                    }
                    .disabled(isRunning)
                    .help("Apply the curated preset for \(yaml.name)")
                    .accessibilityLabel("Apply curated preset for \(yaml.name)")
                }
            }
        }
    }

    var selectedProfileLaunchSubtitle: String {
        if wineRuntime.needsRosetta, !wineRuntime.rosettaReady {
            return "Install Rosetta 2 first"
        }
        guard let selectedProfile else { return "Select a profile first" }
        return selectedProfileCanLaunch
            ? selectedProfile.launchMethodLabel
            : "Configure executable or Steam App ID"
    }

    var selectedProfileLaunchHelp: String {
        if wineRuntime.needsRosetta, !wineRuntime.rosettaReady {
            return "Install Rosetta 2 before launching Wine games on Apple Silicon"
        }
        if selectedProfileCanLaunch {
            return "Launch the selected profile (\(selectedProfile?.launchMethodLabel.lowercased() ?? ""))"
        }
        return "Select a profile with a launch path or Steam App ID in the sidebar"
    }

    var selectedProfileCanLaunch: Bool {
        selectedProfile?.canLaunchFromDashboard == true
    }
}
