import Foundation
import AppKit
import SwiftUI

extension ContentView {
    // MARK: - Game library (saved launchers)

    var gameLibrarySection: some View {
        GameLibrarySection(
            profiles: profiles,
            searchText: $librarySearchText,
            viewMode: $libraryViewMode,
            sourceFilter: $librarySourceFilter,
            selectedProfileID: $selectedProfileID,
            pendingNewSteamGames: pendingNewSteamGames,
            pendingUnregisteredGogGames: pendingUnregisteredGogGames,
            isSetupComplete: isSetupComplete,
            isSteamReady: isSteamReady,
            isRunning: isRunning || pendingTerminalJobID != nil,
            compatBadge: sidebarCompatBadge(for:),
            isFavorite: { ProfilePreferencesStore.isFavorite(profileID: $0.id, in: profilePreferences) },
            canLaunch: { $0.canLaunchFromDashboard && wineRuntime.canStartWineLaunch },
            profileExtras: { profileContextMenuExtras(for: $0, inLibrary: true) },
            onToggleFavorite: { profilePreferences = ProfilePreferencesStore.toggleFavorite(profileID: $0.id) },
            onReveal: { revealInFinder($0.fileURL) },
            onLaunch: launchProfile,
            onSyncSteam: { syncSteamLibrary(announce: true) },
            onSyncGog: { syncGogLibrary(build: false, announce: true) },
            onRegisterGogBuild: { syncGogLibrary(build: true, announce: true) },
            onSyncAll: { syncAllLibrarySources() },
            onBuildLaunchers: { buildLaunchers() },
            onDetectGames: {
                runCommand(
                    script: "detect_steam_games.command",
                    arguments: ["--list"],
                    environment: bottleEnvironment()
                )
            },
            onLaunchSteam: launchSteamFromDashboard,
            onContinueSetup: {
                menuContinueSetup()
            },
            onListGog: { listGogGames() },
            onVerifySteam: { verifySteamInstall() },
            onOpenImport: { openImportTools() },
            onAddProfile: { openAddGameProfile() }
        )
        .id(CosmosScrollAnchor.gameLibrary)
    }

    func syncAllLibrarySources(preferSteamOnly: Bool = false) {
        let needsSteam = pendingNewSteamGames > 0
        let needsGog = pendingUnregisteredGogGames > 0

        if preferSteamOnly || (!needsSteam && !needsGog) {
            syncSteamLibrary(announce: true)
            return
        }
        if needsSteam, needsGog {
            librarySyncFollowUp = { syncGogLibrary(build: false, announce: true) }
            syncSteamLibrary(announce: true)
            return
        }
        if needsSteam {
            syncSteamLibrary(announce: true)
        } else if needsGog {
            syncGogLibrary(build: false, announce: true)
        }
    }

    func runLibrarySyncFollowUpIfNeeded() {
        guard let followUp = librarySyncFollowUp else { return }
        librarySyncFollowUp = nil
        followUp()
    }

    // MARK: - Curated profiles (YAML)

    var curatedProfilesSection: some View {
        CosmosSection(
            title: "Recommended Game Settings",
            systemImage: "doc.text.fill",
            caption: "Choose settings and fixes for your game, or add your own preset."
        ) {
            DisclosureGroup("What does applying a preset change?") {
                Text("Presets are YAML files. Applying one writes game-specific overrides and may install dependencies with winetricks or run included fixes. Review the selected preset before applying it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer(minLength: 0)
                Button {
                    showAddGameProfileSheet = true
                } label: {
                    Label("Add Game Preset", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)
                .help("Create a personal YAML profile from a Steam App ID or GOG slug")
            }

            if gameProfiles.isEmpty {
                CosmosEmptyState(
                    systemImage: "doc.text",
                    title: "No game presets yet",
                    message: "Add your own game preset, or check for updates to get recommended settings and fixes.",
                    isRunning: isRunning,
                    actions: [
                        (title: "Add Game Preset", prominent: true, action: { showAddGameProfileSheet = true }),
                        (title: "Check for Updates", prominent: false, action: { checkForUpdates() }),
                    ]
                )
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
                        CosmosEmptyState(
                            systemImage: "line.3.horizontal.decrease.circle",
                            title: "No profiles match",
                            message: "Choose All or another filter to browse recommended game settings.",
                            isRunning: isRunning,
                            actions: [(title: "Show All", prominent: true, action: { curatedProfileFilter = .all })]
                        )
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
        .id(CosmosScrollAnchor.gameProfiles)
    }

    func curatedProfileFilterChip(_ filter: CuratedProfileFilter) -> some View {
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

    func curatedProfileCard(_ profile: GameProfile) -> some View {
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
                    if profile.isUserAuthored {
                        Text("Mine")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cosmosPrimary.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.cosmosPrimary)
                    }
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .curatedProfileContextMenu(
            profile: profile,
            isRunning: isRunning,
            onApply: { applyCuratedGameProfile(profile) },
            onShowCompatibility: { compatLookupForGameProfile(profile) },
            onFindLauncher: findSavedLauncher(for: profile).map { launcher in
                { showSavedLauncherInLibrary(launcher) }
            }
        )
    }

    func curatedProfileAccessibilityLabel(_ profile: GameProfile, isSelected: Bool) -> String {
        var parts = [profile.name, profile.statusLabel, profile.recommendedBackend]
        if !profile.multiplayerTagLabel.isEmpty {
            parts.append(profile.multiplayerTagLabel)
        }
        if isSelected {
            parts.append("selected")
        }
        return parts.joined(separator: ", ")
    }

    func curatedProfileControls(_ profile: GameProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(profile.name)
                    .font(.headline)
                Spacer()
                CosmosCompatBadge(status: profile.statusLabel)
            }

            if profile.isBlocked {
                CosmosNoticeBanner(
                    tint: Color.cosmosDanger,
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
                            .foregroundStyle(profile.status == "blocked" ? Color.cosmosDanger : .primary)
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
}
