import Foundation
import AppKit
import SwiftUI

extension ContentView {
    // MARK: - Setup tools (first-time, advanced options)

    var setupToolsGrid: some View {
        CosmosSection(title: "Optional tools", systemImage: "wrench.and.screwdriver") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: CosmosSpacing.gridColumnMin), spacing: CosmosSpacing.gridGap)],
                spacing: CosmosSpacing.gridGap
            ) {
                gameDiscoveryButtons
                CosmosSecondaryActionButton(title: "Profiles Folder", subtitle: "Open in Finder", systemImage: "folder.fill", isRunning: isRunning, help: "Reveal saved game profiles in Finder") {
                    runCommand(script: "run.command", arguments: ["--profiles"])
                }
                CosmosSecondaryActionButton(title: "Open Logs", subtitle: "Latest launch log", systemImage: "doc.text.magnifyingglass", isRunning: isRunning, help: "Open the most recent launch log for troubleshooting") {
                    runCommand(script: "run.command", arguments: ["--logs"])
                }
            }
        }
    }

    // MARK: - Maintenance grid (post-setup Tools tab)

    var maintenanceGrid: some View {
        CosmosSection(title: "Maintenance", systemImage: "wrench.and.screwdriver.fill") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: CosmosSpacing.gridColumnMin), spacing: CosmosSpacing.gridGap)],
                spacing: CosmosSpacing.gridGap
            ) {
                gameDiscoveryButtons

                if !installedCuratedProfiles.isEmpty {
                    CosmosSecondaryActionButton(
                        title: "Apply Curated Profiles",
                        subtitle: "\(installedCuratedProfiles.count) installed title\(installedCuratedProfiles.count == 1 ? "" : "s")",
                        systemImage: "arrow.down.circle.fill",
                        isRunning: isRunning,
                        help: "Batch-apply shipped YAML presets (overrides, deps, fixes) for detected games"
                    ) {
                        applyInstalledCuratedProfiles()
                    }
                }

                CosmosSecondaryActionButton(title: "Profiles Folder", subtitle: "Open in Finder", systemImage: "folder.fill", isRunning: isRunning, help: "Reveal saved game profiles in Finder") {
                    runCommand(script: "run.command", arguments: ["--profiles"])
                }

                CosmosSecondaryActionButton(title: "Open Logs", subtitle: "Latest launch log", systemImage: "doc.text.magnifyingglass", isRunning: isRunning, help: "Open the most recent launch log for troubleshooting") {
                    runCommand(script: "run.command", arguments: ["--logs"])
                }

                CosmosSecondaryActionButton(title: "Check for Updates", subtitle: "GitHub Releases", systemImage: "arrow.down.circle", isRunning: isRunning, help: "Compare your Cosmos version to the latest published release") {
                    checkForUpdates()
                }

                if updateAvailable {
                    CosmosSecondaryActionButton(
                        title: "Install Update",
                        subtitle: "Download macOS DMG",
                        systemImage: "arrow.down.to.line",
                        isRunning: isRunning,
                        help: "Download the latest release and install Cosmos.app to /Applications"
                    ) {
                        installUpdate()
                    }
                }

                CosmosSecondaryActionButton(title: "Reset Bottle", subtitle: "Delete prefix", systemImage: "arrow.counterclockwise", destructive: true, isRunning: isRunning, help: "Delete the default Wine prefix (Steam and games inside it)") {
                    showResetConfirmation = true
                }

                CosmosSecondaryActionButton(title: "Uninstall", subtitle: "Remove everything · Terminal", systemImage: "trash.fill", destructive: true, isRunning: isRunning, help: "Opens Terminal to remove Cosmos Apps, the prefix, and downloaded runtimes") {
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

    // MARK: - Repair

    var repairSection: some View {
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

            if dependencyRecipes.isEmpty && fixRecipes.isEmpty {
                CosmosEmptyState(
                    systemImage: "bandage",
                    title: "No repair recipes loaded",
                    message: "Recipes ship with Cosmos and load from the repair bundle. Check for updates or run Diagnose Logs if this section stays empty.",
                    isRunning: isRunning,
                    actions: [(title: "Check for Updates", prominent: false, action: { checkForUpdates() })]
                )
            }
        }
        .id(CosmosScrollAnchor.repair)
    }

    func recipeButtonGrid(_ recipes: [RepairRecipe], prefix: String) -> some View {
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
                    CosmosActionTile(title: recipe.displayTitle, subtitle: recipe.displaySubtitle)
                }
                .buttonStyle(CosmosButtonStyle())
                .disabled(isRunning)
                .help(recipe.description)
            }
        }
    }

    // MARK: - Store expansion (0.6)

    var storeExpansionSection: some View {
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
                    title: "Install Classic Game",
                    subtitle: "Installer → folder → game EXE",
                    systemImage: "shippingbox.fill",
                    script: "scripts/install_program.command",
                    arguments: ["install"],
                    needsStoreTitle: true,
                    pathPrompt: "Install a classic Windows game from EXE"
                )
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
                Button {
                    syncGogLibrary(build: true, announce: true)
                } label: {
                    CosmosActionTile(
                        title: "Sync GOG Games",
                        subtitle: "Register + build launchers",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .buttonStyle(CosmosButtonStyle())
                .disabled(isRunning)
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
                Text("After importing, choose Create Dock Shortcuts to make your games available from the Dock.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Create Dock Shortcuts") {
                    buildLaunchers()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRunning)
            }
        }
        .id(CosmosScrollAnchor.storeImport)
    }

    func storeActionButton(
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
                        : script == "scripts/install_program.command"
                        ? "Choose the installer EXE and enter the game title, such as SimCity 3000 Unlimited. Terminal guides you through choosing an installation folder, running setup, selecting the installed game EXE, and opening it. Uses a dedicated environment and WineD3D."
                        : "Provide the file or folder path and a display name for the Cosmos launcher.",
                    fields: [
                        .init(
                            id: .path,
                            label: script == "scripts/install_program.command" ? "Installer EXE" : "Path",
                            placeholder: arguments.contains("add-gog") || script == "scripts/install_program.command"
                                ? "/Users/you/Downloads/setup_game.exe"
                                : "/Users/you/Downloads/MyGame",
                            allowsFilePicker: true
                        ),
                        .init(id: .displayName, label: "Display name", placeholder: "Display name for launcher"),
                    ],
                    submitLabel: arguments.contains("add-gog") ? "Import" : (script == "scripts/install_program.command" ? "Install in Terminal" : "Run in Terminal"),
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
        .disabled(isRunning || pendingTerminalJobID != nil)
    }

    func submitStoreImport(
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

    func repairEnvironment() -> [String: String] {
        var env = bottleEnvironment()
        if let appid = activeSteamAppID, !appid.isEmpty {
            env["COSMOS_PROFILE_APPID"] = appid
            env["STEAM_APPID"] = appid
        }
        return env
    }

    // MARK: - CosmosDB

    var compatibilitySection: some View {
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
                            Label("Apply Game Preset", systemImage: "doc.text.fill")
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
                CosmosEmptyState(
                    systemImage: "chart.bar.doc.horizontal",
                    title: "No game selected",
                    message: "Select a saved launcher from the sidebar or a recommended game preset to look up compatibility, apply settings, or file a local report.",
                    tint: .secondary
                )
            }
        }
        .onChange(of: activeSteamAppID) { _ in refreshCompatBadge() }
        .onChange(of: selectedGameProfileID) { _ in refreshCompatBadge() }
        .id(CosmosScrollAnchor.compatibility)
    }

    static let cosmosStatusOptions = [
        "platinum", "gold", "silver", "playable", "bronze", "broken", "blocked",
    ]
}
