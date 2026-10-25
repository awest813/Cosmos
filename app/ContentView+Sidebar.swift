import Foundation
import AppKit
import SwiftUI

extension ContentView {
    // MARK: - Sidebar

    var sidebarContent: some View {
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
                    Section("Saved Launchers") {
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

    var profileSectionTitle: String {
        "Saved Launchers (\(catalogProfiles.count))"
    }

    var sidebarProfileFilterChips: some View {
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

    var sidebarEmptyProfilesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No profiles yet", systemImage: "tray")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text(isSteamReady ? "Choose Find Installed Games to add Steam games to Cosmos." : "Complete setup on the Launch tab, then add your first game.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    var sidebarEmptySearchRow: some View {
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

    var sidebarEmptyFilterRow: some View {
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

    var sidebarFilterEmptyCaption: String {
        switch sidebarProfileFilter {
        case .all:
            return "No saved game profiles."
        case .favorites:
            return "Star a game in the sidebar to pin it here."
        case .recent:
            return "Launch a game to see it in Recent."
        }
    }

    var profileSearchField: some View {
        CosmosSearchField(placeholder: "Search games", text: $profileSearchText)
    }

    func profileRow(_ profile: SavedProfile) -> some View {
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
                        .foregroundStyle(Color.cosmosWarning)
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
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard profile.canLaunchFromDashboard,
                      wineRuntime.canStartWineLaunch,
                      !isRunning else { return }
                selectedProfileID = profile.id
                focusDashboardSection(.launch)
                launchProfile(profile)
            }
        )
        .help(profile.canLaunchFromDashboard ? "Double-click to launch" : "Select to view launch options")
        .profileContextMenu(
            profile: profile,
            isFavorite: ProfilePreferencesStore.isFavorite(profileID: profile.id, in: profilePreferences),
            canLaunch: profile.canLaunchFromDashboard && wineRuntime.canStartWineLaunch,
            isRunning: isRunning,
            extras: profileContextMenuExtras(for: profile),
            onLaunch: {
                selectedProfileID = profile.id
                launchProfile(profile)
            },
            onToggleFavorite: {
                profilePreferences = ProfilePreferencesStore.toggleFavorite(profileID: profile.id)
            },
            onReveal: { revealInFinder(profile.fileURL) },
            onCopyPath: {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(profile.path, forType: .string)
            }
        )
    }
}
