import Foundation
import SwiftUI

struct ContentView: View {
    private let fileManager = FileManager.default
    private let repositoryRootURL = Self.findRepositoryRoot()
    private let profileDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cosmos/Profiles", isDirectory: true)
    private let cosmosAppsURL = URL(fileURLWithPath: "/Applications/Cosmos Apps", isDirectory: true)
    private let steamExecutableURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".wine-steam-11/drive_c/Program Files (x86)/Steam/steam.exe")
    private let consoleBottomID = "console-bottom"

    @State private var output = "Welcome to Cosmos\n\nSelect a saved profile or use the quick actions to manage your setup."
    @State private var profiles: [SavedProfile] = []
    @State private var selectedProfileID: String?
    @State private var cosmosInstalled = false
    @State private var steamInstalled = false
    @State private var isRunning = false
    @State private var showResetConfirmation = false
    @State private var showUninstallConfirmation = false

    @State private var gameProfiles: [GameProfile] = []
    @State private var selectedGameProfileID: String?
    @State private var dependencyRecipes: [RepairRecipe] = []
    @State private var fixRecipes: [RepairRecipe] = []
    @State private var cosmosReportStatus = "playable"
    @State private var cosmosReportNote = ""

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

    private var selectedBottle: Bottle? {
        bottles.first { $0.id == selectedBottleID }
    }

    private var selectedGameProfile: GameProfile? {
        gameProfiles.first { $0.id == selectedGameProfileID }
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
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(alignment: .center, spacing: 0) {
            // Logo header
            VStack(spacing: 10) {
                CosmosLogoMark(size: 64)
                Text("Cosmos")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.cosmosPrimary)
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

            // Profile list
            List(selection: $selectedProfileID) {
                Section("Saved Profiles") {
                    if profiles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("No profiles yet", systemImage: "tray")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                            Text("Run Detect Games after installing Steam to discover titles.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("No saved game profiles. Run Detect Games after installing Steam.")
                    } else {
                        ForEach(profiles) { profile in
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

    private func profileRow(_ profile: SavedProfile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(profile.name)
                .font(.headline)
            Text(profile.args.isEmpty ? profile.path : profile.args)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name). \(profile.path.isEmpty ? "No executable path set" : profile.path)")
        .accessibilityAddTraits(profile.id == selectedProfileID ? .isSelected : [])
    }

    // MARK: - Detail

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                heroSection
                launchSection
                managementGrid
                curatedProfilesSection
                repairSection
                compatibilitySection
                bottlesSection
                if let selectedProfile {
                    selectedProfileSection(selectedProfile)
                }
                consoleSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
        return "Launcher Dashboard"
    }

    private var heroSubtitle: String {
        if let selectedProfile {
            return selectedProfileHasExecutablePath
                ? "Ready to launch this saved profile through the Wine-based shell flow."
                : "This profile has no executable path — edit its config file or pick another profile."
        }
        if let selectedBottle {
            return "Bottle selected — adjust backend and launch Steam from the controls below."
        }
        if !cosmosInstalled {
            return "Install Cosmos first, then launch Steam and detect games to populate profiles."
        }
        return "Manage Cosmos, launch Steam, and jump into saved game profiles from one place."
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
            runCommand(
                script: "run.command",
                arguments: ["--game", selectedProfile.path] + shellArguments(from: selectedProfile.args)
            )
        }
    }

    private var launchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Quick Launch", systemImage: "bolt.fill")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    quickLaunchButtons
                }
                VStack(spacing: 14) {
                    quickLaunchButtons
                }
            }
        }
    }

    // MARK: - Management grid

    private var managementGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Setup & Maintenance", systemImage: "wrench.and.screwdriver.fill")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 12)], spacing: 12) {
                secondaryButton(title: "Install Cosmos", subtitle: "Wine & deps · Terminal", systemImage: "arrow.down.circle.fill", help: "Opens Terminal to install Wine and dependencies (may ask for your password)") {
                    runInTerminal(script: "install_cosmos.command")
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
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Curated Game Profiles", systemImage: "doc.text.fill")

            Text("Known-good YAML recipes (roadmap 0.4). Apply writes overrides and runs winetricks/fixes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if gameProfiles.isEmpty {
                Text("No profiles found in profiles/. Rebuild the app bundle or run from the repository checkout.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ForEach(gameProfiles) { profile in
                        curatedProfileCard(profile)
                    }
                }
            }

            if let profile = selectedGameProfile {
                curatedProfileControls(profile)
            }
        }
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
                    Text(profile.statusLabel)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cosmosPrimary.opacity(0.12), in: Capsule())
                }
                if !profile.steamAppID.isEmpty {
                    Text("App ID \(profile.steamAppID)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                isSelected ? Color.cosmosPrimary.opacity(0.10) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.cosmosPrimary.opacity(0.5) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(CosmosButtonStyle())
        .disabled(isRunning)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cosmosPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Repair

    private var repairSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Repair & Dependencies", systemImage: "bandage.fill")

            Text("Winetricks installs may take several minutes. Requires brew install winetricks.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !dependencyRecipes.isEmpty {
                Text("Dependencies")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.cosmosPrimary.opacity(0.8))
                recipeButtonGrid(dependencyRecipes, prefix: "install-dep")
            }

            if !fixRecipes.isEmpty {
                Text("Fixes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.cosmosPrimary.opacity(0.8))
                    .padding(.top, 4)
                recipeButtonGrid(fixRecipes, prefix: "apply-fix")
            }
        }
    }

    private func recipeButtonGrid(_ recipes: [RepairRecipe], prefix: String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(recipes) { recipe in
                Button {
                    runCommand(
                        script: "repair.command",
                        arguments: [prefix, recipe.id],
                        environment: bottleEnvironment()
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.id)
                            .font(.caption.weight(.semibold))
                        Text(recipe.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .help(recipe.description)
            }
        }
    }

    // MARK: - CosmosDB

    private var compatibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Compatibility", systemImage: "chart.bar.doc.horizontal")

            Text("ProtonDB hints are Linux-focused. Local reports capture macOS results.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let appid = activeSteamAppID {
                detailRow(title: "Steam App ID", value: appid)

                HStack(spacing: 12) {
                    Button {
                        runCommand(script: "cosmosdb.command", arguments: ["lookup", appid])
                    } label: {
                        Label("ProtonDB Lookup", systemImage: "globe")
                    }
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cosmosPrimary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
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
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background(
                (isSelected ? Color.cosmosPrimary.opacity(0.10) : Color.primary.opacity(0.04)),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? Color.cosmosPrimary.opacity(0.55) : Color.cosmosPrimary.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .hoverBrighten()
        }
        .buttonStyle(CosmosButtonStyle())
        .disabled(isRunning)
        .accessibilityLabel("\(bottle.name), \(bottle.backend), \(bottle.statusText)")
        .accessibilityHint(isSelected ? "Double-tap to deselect" : "Double-tap to select and show controls")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func bottleControls(_ bottle: Bottle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(bottle.name)
                    .font(.title3.weight(.semibold))
                Spacer()
                Picker("Backend", selection: backendBinding(for: bottle)) {
                    ForEach(BottleStore.backendOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
                .disabled(isRunning)
            }

            HStack(alignment: .top, spacing: 24) {
                detailRow(title: "Wine", value: bottle.wineVersion)
                detailRow(title: "Windows", value: bottle.windowsVersion)
                detailRow(title: "Retina", value: bottle.retinaEnabled ? "On" : "Off")
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cosmosPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.cosmosPrimary.opacity(0.15), lineWidth: 1)
        )
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
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Selected Launcher", systemImage: "gamecontroller.fill")

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
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cosmosPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.cosmosPrimary.opacity(0.15), lineWidth: 1)
            )

            if let appid = profile.steamAppID, !appid.isEmpty,
               let yaml = GameProfileStore.find(steamAppID: appid) {
                HStack {
                    Text("Curated preset available: \(yaml.name)")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                sectionHeader("Launcher Output", systemImage: "terminal.fill")
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
                    output = ""
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

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(output)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .foregroundStyle(Color(red: 0.85, green: 0.80, blue: 1.0))
                        // Anchor the auto-scroll to the end of the output so the
                        // newest lines stay visible while a command streams.
                        Color.clear
                            .frame(height: 1)
                            .id(consoleBottomID)
                    }
                    .padding(16)
                }
                .frame(minHeight: 220)
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

    // MARK: - Reusable components

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow(
                label: cosmosInstalled ? "Cosmos installed" : "Cosmos required",
                icon: cosmosInstalled ? "checkmark.circle.fill" : "arrow.down.circle",
                color: cosmosInstalled ? Color.green : Color.orange
            )
            statusRow(
                label: steamInstalled ? "Steam ready" : "Steam not installed",
                icon: steamInstalled ? "shippingbox.fill" : "shippingbox",
                color: steamInstalled ? Color.cosmosBright : Color.secondary
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
        Label(label, systemImage: icon)
            .foregroundStyle(color)
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
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
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
        cosmosInstalled = fileManager.fileExists(atPath: cosmosAppsURL.path)
        steamInstalled = fileManager.fileExists(atPath: steamExecutableURL.path)
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

        if let message {
            output = message + "\n\n" + output
        }
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

    // Pure helper for splitting the profile args field; edge cases can be unit-tested independently of the launcher and this only targets trusted local profile text.
    private func shellArguments(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        // This splitter only handles simple quoted groups; backslashes stay literal, unclosed quotes stay literal, and trailing whitespace is ignored.
        enum QuoteState {
            case none
            case single
            case double
        }

        let whitespaceCharacters = CharacterSet.whitespacesAndNewlines
        var state: QuoteState = .none
        var current = ""
        var result: [String] = []

        for character in text {
            switch character {
            case "'" where state == .none:
                state = .single
            case "'" where state == .single:
                state = .none
            case "\"" where state == .none:
                state = .double
            case "\"" where state == .double:
                state = .none
            default:
                if state == .none, character.unicodeScalars.allSatisfy({ whitespaceCharacters.contains($0) }) {
                    if !current.isEmpty {
                        result.append(current)
                        current = ""
                    }
                } else {
                    current.append(character)
                }
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
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
    private func runInTerminal(script: String, arguments: [String] = []) {
        guard let scriptURL = resolveScript(script) else {
            output = "Script not found or not executable: \(script)"
            return
        }

        let shellCommand = ([scriptURL.path] + arguments)
            .map(Self.shellQuote)
            .joined(separator: " ")

        let appleScript = """
        tell application "Terminal"
            activate
            do script "\(Self.appleScriptEscape(shellCommand))"
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
            then press Refresh here to update the status.
            """
        } catch {
            output = "Failed to open Terminal: \(error.localizedDescription)"
        }
    }

    // Wrap a value in single quotes for safe use as one shell word.
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // Escape a value for embedding inside an AppleScript double-quoted string.
    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runCommand(script: String, arguments: [String] = [], environment: [String: String] = [:]) {
        guard let scriptURL = resolveScript(script) else {
            output = "Script not found or not executable: \(script)"
            return
        }

        let displayedCommand = ([script] + arguments).joined(separator: " ")
        output = "Running: \(displayedCommand)\n\n"
        isRunning = true

        let task = Process()
        task.executableURL = scriptURL
        task.arguments = arguments
        task.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        var mergedEnvironment = ProcessInfo.processInfo.environment
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
                output += process.terminationStatus == 0 ? "\nDone." : "\nExited with status \(process.terminationStatus)."
                refreshStatus()
            }
        }

        do {
            try task.run()
        } catch {
            isRunning = false
            output = "Failed to run command: \(error.localizedDescription)"
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

// MARK: - Interaction styling

/// Press feedback for the dashboard's custom buttons, which would otherwise be
/// inert under `.buttonStyle(.plain)`.
private struct CosmosButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Subtle brighten-on-hover for pointer feedback on macOS.
private struct HoverBrighten: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .brightness(isHovering && !reduceMotion ? 0.06 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

private extension View {
    func hoverBrighten() -> some View { modifier(HoverBrighten()) }
}

extension Notification.Name {
    static let cosmosRefreshStatus = Notification.Name("com.cosmos.refreshStatus")
}

#if DEBUG
#Preview {
    ContentView()
}
#endif
