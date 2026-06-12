import AppKit
import SwiftUI

// MARK: - Models

enum GameLibraryViewMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grid: return "Grid"
        case .list: return "List"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

enum GameLibraryStore: String, Equatable {
    case steam
    case gog
    case other

    var label: String {
        switch self {
        case .steam: return "Steam"
        case .gog: return "GOG"
        case .other: return "Manual"
        }
    }

    var systemImage: String {
        switch self {
        case .steam: return "play.rectangle.fill"
        case .gog: return "opticaldisc.fill"
        case .other: return "folder.fill"
        }
    }
}

extension SavedProfile {
    var libraryStore: GameLibraryStore {
        if let slug = gogSlug, !slug.isEmpty { return .gog }
        if let appid = steamAppID, !appid.isEmpty { return .steam }
        return .other
    }
}

enum GameLibraryBlankSlateKind: Equatable {
    case setupIncomplete
    case newSteamGames(Int)
    case unregisteredGog(Int)
    case emptyReady
    case searchEmpty(String)

    static func resolve(
        totalProfiles: Int,
        filteredCount: Int,
        searchQuery: String,
        isSetupComplete: Bool,
        isSteamReady: Bool,
        pendingNewSteamGames: Int,
        pendingUnregisteredGogGames: Int
    ) -> GameLibraryBlankSlateKind? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty, filteredCount == 0 {
            return .searchEmpty(query)
        }
        guard totalProfiles == 0 else { return nil }
        if !isSteamReady || !isSetupComplete {
            return .setupIncomplete
        }
        if pendingNewSteamGames > 0 {
            return .newSteamGames(pendingNewSteamGames)
        }
        if pendingUnregisteredGogGames > 0 {
            return .unregisteredGog(pendingUnregisteredGogGames)
        }
        return .emptyReady
    }
}

enum GameLibraryFilter {
    static func matches(_ profile: SavedProfile, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return profile.name.localizedCaseInsensitiveContains(trimmed)
            || profile.path.localizedCaseInsensitiveContains(trimmed)
            || (profile.steamAppID?.localizedCaseInsensitiveContains(trimmed) ?? false)
            || (profile.gogSlug?.localizedCaseInsensitiveContains(trimmed) ?? false)
    }

    static func filter(_ profiles: [SavedProfile], query: String) -> [SavedProfile] {
        profiles
            .filter { matches($0, query: query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Toolbar

struct GameLibraryToolbar: View {
    @Binding var searchText: String
    @Binding var viewMode: GameLibraryViewMode
    let pendingNewSteamGames: Int
    let pendingUnregisteredGogGames: Int
    let isRunning: Bool
    var onSyncSteam: () -> Void
    var onSyncGog: () -> Void
    var onRegisterGogBuild: () -> Void
    var onSyncAll: () -> Void

    private var pendingTotal: Int {
        pendingNewSteamGames + pendingUnregisteredGogGames
    }

    var body: some View {
        HStack(spacing: 12) {
            CosmosSearchField(placeholder: "Search library", text: $searchText, disabled: isRunning)
                .frame(maxWidth: 320)
                .accessibilityLabel("Search game library")

            Picker("View", selection: $viewMode) {
                ForEach(GameLibraryViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 120)
            .disabled(isRunning)
            .accessibilityLabel("Library view mode")

            Spacer(minLength: 0)

            if pendingTotal > 0 {
                StatusChip(
                    label: "\(pendingTotal) pending",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .orange
                )
            }

            syncMenu
        }
    }

    @ViewBuilder
    private var syncMenu: some View {
        if pendingNewSteamGames > 0, pendingUnregisteredGogGames > 0 {
            Menu {
                Button(action: onSyncSteam) {
                    Label(
                        "Sync \(pendingNewSteamGames) Steam game\(pendingNewSteamGames == 1 ? "" : "s")",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                Button(action: onSyncGog) {
                    Label(
                        "Register \(pendingUnregisteredGogGames) GOG game\(pendingUnregisteredGogGames == 1 ? "" : "s")",
                        systemImage: "opticaldisc.fill"
                    )
                }
                Button(action: onRegisterGogBuild) {
                    Label("Register GOG + Build", systemImage: "hammer.fill")
                }
                Divider()
                Button(action: onSyncAll) {
                    Label("Sync all (Steam, then GOG)", systemImage: "arrow.triangle.2.circlepath.circle")
                }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(isRunning)
            .help("Sync Steam and register GOG games")
        } else if pendingNewSteamGames > 0 {
            Button {
                onSyncSteam()
            } label: {
                Label("Sync Steam", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
        } else if pendingUnregisteredGogGames > 0 {
            Button {
                onSyncGog()
            } label: {
                Label("Register GOG", systemImage: "opticaldisc.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
        } else {
            Button {
                onSyncSteam()
            } label: {
                Label("Sync Library", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .disabled(isRunning)
            .help("Check for newly installed Steam games and build launchers")
        }
    }
}

// MARK: - Blank slates

struct GameLibraryBlankSlate: View {
    let kind: GameLibraryBlankSlateKind
    var isRunning: Bool = false
    var onSyncSteam: () -> Void = {}
    var onSyncGog: () -> Void = {}
    var onRegisterGogBuild: () -> Void = {}
    var onBuildLaunchers: () -> Void = {}
    var onLaunchSteam: () -> Void = {}
    var onContinueSetup: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 44))
                .foregroundStyle(iconTint)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                ForEach(Array(primaryActions.enumerated()), id: \.offset) { _, action in
                    slateActionButton(action)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .cosmosCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(message)")
    }

    private struct SlateAction {
        let title: String
        let prominent: Bool
        let handler: () -> Void
    }

    @ViewBuilder
    private func slateActionButton(_ action: SlateAction) -> some View {
        if action.prominent {
            Button(action.title, action: action.handler)
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
        } else {
            Button(action.title, action: action.handler)
                .buttonStyle(.bordered)
                .disabled(isRunning)
        }
    }

    private var iconName: String {
        switch kind {
        case .setupIncomplete: return "wand.and.stars"
        case .newSteamGames: return "arrow.triangle.2.circlepath"
        case .unregisteredGog: return "opticaldisc.fill"
        case .emptyReady: return "gamecontroller.fill"
        case .searchEmpty: return "magnifyingglass"
        }
    }

    private var iconTint: Color {
        switch kind {
        case .setupIncomplete: return Color.cosmosPrimary
        case .newSteamGames: return .orange
        case .unregisteredGog: return .blue
        case .emptyReady: return Color.cosmosPrimary
        case .searchEmpty: return .secondary
        }
    }

    private var title: String {
        switch kind {
        case .setupIncomplete:
            return "Finish setup first"
        case .newSteamGames(let count):
            return "\(count) new Steam game\(count == 1 ? "" : "s")"
        case .unregisteredGog(let count):
            return "\(count) GOG install\(count == 1 ? "" : "s") ready"
        case .emptyReady:
            return "Your library is empty"
        case .searchEmpty:
            return "No matches"
        }
    }

    private var message: String {
        switch kind {
        case .setupIncomplete:
            return "Complete the setup checklist, then build launchers to populate your game library."
        case .newSteamGames:
            return "New Steam installs were detected. Sync to create launcher configs and Dock apps."
        case .unregisteredGog:
            return "GOG games are on disk but not registered as Cosmos launchers yet."
        case .emptyReady:
            return "Install a Windows game in Steam or import a GOG folder, then detect or sync to fill this view."
        case .searchEmpty(let query):
            return "No saved launcher matches “\(query)”."
        }
    }

    private var primaryActions: [SlateAction] {
        switch kind {
        case .setupIncomplete:
            return [SlateAction(title: "Continue Setup", prominent: true, handler: onContinueSetup)]
        case .newSteamGames:
            return [
                SlateAction(title: "Sync Launchers", prominent: true, handler: onSyncSteam),
                SlateAction(title: "Build All", prominent: false, handler: onBuildLaunchers),
            ]
        case .unregisteredGog:
            return [
                SlateAction(title: "Register All", prominent: true, handler: onSyncGog),
                SlateAction(title: "Register + Build", prominent: false, handler: onRegisterGogBuild),
            ]
        case .emptyReady:
            return [
                SlateAction(title: "Launch Steam", prominent: true, handler: onLaunchSteam),
                SlateAction(title: "Build Launchers", prominent: false, handler: onBuildLaunchers),
            ]
        case .searchEmpty:
            return []
        }
    }
}

struct GameLibraryPendingBanner: View {
    enum Kind: Equatable {
        case steam(Int)
        case gog(Int)
    }

    let kind: Kind
    var isRunning: Bool = false
    var onAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                Text(kind.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(kind.actionTitle, action: onAction)
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
        }
        .padding(14)
        .background(kind.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: CosmosSpacing.buttonRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CosmosSpacing.buttonRadius)
                .strokeBorder(kind.tint.opacity(0.2), lineWidth: 1)
        )
    }
}

private extension GameLibraryPendingBanner.Kind {
    var systemImage: String {
        switch self {
        case .steam: return "arrow.triangle.2.circlepath"
        case .gog: return "opticaldisc.fill"
        }
    }

    var tint: Color {
        switch self {
        case .steam: return .orange
        case .gog: return .blue
        }
    }

    var title: String {
        switch self {
        case .steam(let count):
            return "\(count) new Steam game\(count == 1 ? "" : "s")"
        case .gog(let count):
            return "\(count) unregistered GOG game\(count == 1 ? "" : "s")"
        }
    }

    var message: String {
        switch self {
        case .steam:
            return "Sync to add launchers for newly installed titles."
        case .gog:
            return "Register detected GOG installs as launcher configs."
        }
    }

    var actionTitle: String {
        switch self {
        case .steam: return "Sync"
        case .gog: return "Register"
        }
    }
}

// MARK: - Grid / list items

struct GameLibraryTile: View {
    let profile: SavedProfile
    let isSelected: Bool
    let compatStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: profile.libraryStore.systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.cosmosPrimary)
                Spacer()
                if let compatStatus {
                    CosmosCompatBadge(status: compatStatus, compact: true)
                }
            }
            Text(profile.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(profile.librarySubtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .cosmosSelectableSurface(isSelected: isSelected, minHeight: 118)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.libraryAccessibilityLabel(compatStatus: compatStatus))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct GameLibraryListRow: View {
    let profile: SavedProfile
    let isSelected: Bool
    let compatStatus: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.libraryStore.systemImage)
                .font(.title3)
                .foregroundStyle(Color.cosmosPrimary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(profile.librarySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(profile.libraryStore.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            if let compatStatus {
                CosmosCompatBadge(status: compatStatus, compact: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isSelected ? Color.cosmosPrimary.opacity(0.12) : Color.cosmosTileFill,
            in: RoundedRectangle(cornerRadius: CosmosSpacing.tileRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CosmosSpacing.tileRadius)
                .strokeBorder(
                    isSelected ? Color.cosmosBright.opacity(0.55) : Color.cosmosCardBorder,
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .hoverBrighten()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.libraryAccessibilityLabel(compatStatus: compatStatus))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension SavedProfile {
    var librarySubtitle: String {
        switch libraryStore {
        case .steam:
            if let appid = steamAppID, !appid.isEmpty { return "Steam · App ID \(appid)" }
            return "Steam"
        case .gog:
            if let slug = gogSlug, !slug.isEmpty { return "GOG · \(slug)" }
            return "GOG"
        case .other:
            return launchMethodLabel
        }
    }

    func libraryAccessibilityLabel(compatStatus: String?) -> String {
        var parts = [name, libraryStore.label, librarySubtitle]
        if let compatStatus { parts.append("compatibility \(compatStatus)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Section container

struct GameLibrarySection: View {
    let profiles: [SavedProfile]
    @Binding var searchText: String
    @Binding var viewMode: GameLibraryViewMode
    @Binding var selectedProfileID: String?
    let pendingNewSteamGames: Int
    let pendingUnregisteredGogGames: Int
    let isSetupComplete: Bool
    let isSteamReady: Bool
    let isRunning: Bool
    var compatBadge: (SavedProfile) -> ResolvedBadge?
    var isFavorite: (SavedProfile) -> Bool
    var canLaunch: (SavedProfile) -> Bool
    var onToggleFavorite: (SavedProfile) -> Void
    var onReveal: (SavedProfile) -> Void
    var onLaunch: (SavedProfile) -> Void
    var onSyncSteam: () -> Void
    var onSyncGog: () -> Void
    var onRegisterGogBuild: () -> Void
    var onSyncAll: () -> Void
    var onBuildLaunchers: () -> Void
    var onLaunchSteam: () -> Void
    var onContinueSetup: () -> Void

    private var filteredProfiles: [SavedProfile] {
        GameLibraryFilter.filter(profiles, query: searchText)
    }

    private var blankSlate: GameLibraryBlankSlateKind? {
        GameLibraryBlankSlateKind.resolve(
            totalProfiles: profiles.count,
            filteredCount: filteredProfiles.count,
            searchQuery: searchText,
            isSetupComplete: isSetupComplete,
            isSteamReady: isSteamReady,
            pendingNewSteamGames: pendingNewSteamGames,
            pendingUnregisteredGogGames: pendingUnregisteredGogGames
        )
    }

    var body: some View {
        CosmosSection(
            title: "Game Library",
            systemImage: "square.grid.2x2.fill",
            caption: "Browse saved launchers — double-click or use Launch on the sidebar to play."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                GameLibraryToolbar(
                    searchText: $searchText,
                    viewMode: $viewMode,
                    pendingNewSteamGames: pendingNewSteamGames,
                    pendingUnregisteredGogGames: pendingUnregisteredGogGames,
                    isRunning: isRunning,
                    onSyncSteam: onSyncSteam,
                    onSyncGog: onSyncGog,
                    onRegisterGogBuild: onRegisterGogBuild,
                    onSyncAll: onSyncAll
                )

                if let blankSlate {
                    GameLibraryBlankSlate(
                        kind: blankSlate,
                        isRunning: isRunning,
                        onSyncSteam: onSyncSteam,
                        onSyncGog: onSyncGog,
                        onRegisterGogBuild: onRegisterGogBuild,
                        onBuildLaunchers: onBuildLaunchers,
                        onLaunchSteam: onLaunchSteam,
                        onContinueSetup: onContinueSetup
                    )
                } else {
                    pendingBanners
                    libraryContent
                }
            }
        }
    }

    @ViewBuilder
    private var pendingBanners: some View {
        if pendingNewSteamGames > 0 {
            GameLibraryPendingBanner(kind: .steam(pendingNewSteamGames), isRunning: isRunning, onAction: onSyncSteam)
        }
        if pendingUnregisteredGogGames > 0 {
            GameLibraryPendingBanner(kind: .gog(pendingUnregisteredGogGames), isRunning: isRunning, onAction: onSyncGog)
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch viewMode {
        case .grid:
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: CosmosSpacing.gridColumnMin), spacing: CosmosSpacing.gridGap)],
                spacing: CosmosSpacing.gridGap
            ) {
                ForEach(filteredProfiles) { profile in
                    libraryTileButton(profile)
                }
            }
        case .list:
            VStack(spacing: CosmosSpacing.gridGap) {
                ForEach(filteredProfiles) { profile in
                    libraryListButton(profile)
                }
            }
        }
    }

    private func libraryTileButton(_ profile: SavedProfile) -> some View {
        let isSelected = profile.id == selectedProfileID
        let badge = compatBadge(profile)?.status
        return Button {
            selectedProfileID = profile.id
        } label: {
            GameLibraryTile(profile: profile, isSelected: isSelected, compatStatus: badge)
        }
        .buttonStyle(CosmosButtonStyle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            selectedProfileID = profile.id
            onLaunch(profile)
        })
        .profileContextMenu(
            profile: profile,
            isFavorite: isFavorite(profile),
            canLaunch: canLaunch(profile),
            isRunning: isRunning,
            onLaunch: {
                selectedProfileID = profile.id
                onLaunch(profile)
            },
            onToggleFavorite: { onToggleFavorite(profile) },
            onReveal: { onReveal(profile) },
            onCopyPath: profile.path.isEmpty ? nil : {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(profile.path, forType: .string)
            }
        )
        .disabled(isRunning)
        .help("Double-click to launch")
    }

    private func libraryListButton(_ profile: SavedProfile) -> some View {
        let isSelected = profile.id == selectedProfileID
        let badge = compatBadge(profile)?.status
        return Button {
            selectedProfileID = profile.id
        } label: {
            GameLibraryListRow(profile: profile, isSelected: isSelected, compatStatus: badge)
        }
        .buttonStyle(CosmosButtonStyle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            selectedProfileID = profile.id
            onLaunch(profile)
        })
        .profileContextMenu(
            profile: profile,
            isFavorite: isFavorite(profile),
            canLaunch: canLaunch(profile),
            isRunning: isRunning,
            onLaunch: {
                selectedProfileID = profile.id
                onLaunch(profile)
            },
            onToggleFavorite: { onToggleFavorite(profile) },
            onReveal: { onReveal(profile) },
            onCopyPath: profile.path.isEmpty ? nil : {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(profile.path, forType: .string)
            }
        )
        .disabled(isRunning)
        .help("Double-click to launch")
    }
}
