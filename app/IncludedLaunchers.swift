import SwiftUI

/// Separate Apple Silicon launchers that ship beside Cosmos.
/// Their apps stay in `third_party/`. This screen only points at them.
struct IncludedLauncher: Identifiable, Equatable {
    let id: String
    let name: String
    let licenseLine: String
    let summary: String
    /// Folder under the Cosmos checkout, such as `third_party/highball`.
    let sourceFolder: String
    let guideRelativePath: String
    let guideBundleName: String
    let guideFallback: String
    let buildScript: String
    let buildConfirmTitle: String
    let buildConfirmMessage: String
    let systemImage: String
}

struct IncludedLauncherAvailability: Equatable {
    var hasSource = false
    var canBuild = false

    static let unavailable = IncludedLauncherAvailability()
}

enum IncludedLaunchers {
    static let title = "Highball and Vermut"
    static let caption = "These apps stay separate from Cosmos. Open a guide, show the folder, or build one on this Mac."
    static let missingSource = "This copy of Cosmos does not include the source folder. Open the guide to see where it lives in the project."

    static let highball = IncludedLauncher(
        id: "highball",
        name: "Highball",
        licenseLine: "Included source · GPL-3.0",
        summary: "A separate Apple Silicon launcher. It has a game compatibility list and pinned Wine engines. Apple's DirectX 12 files are not in the folder.",
        sourceFolder: "third_party/highball",
        guideRelativePath: "docs/HIGHBALL.md",
        guideBundleName: "HIGHBALL.md",
        guideFallback: "Highball guide not found. See docs/HIGHBALL.md in the Cosmos project.",
        buildScript: "scripts/build_highball.command",
        buildConfirmTitle: "Build Highball on this Mac?",
        buildConfirmMessage: "This compiles the included Highball source. It needs macOS 14 or later and the Swift tools. The first build can take several minutes.",
        systemImage: "list.bullet.rectangle.fill"
    )

    static let vermut = IncludedLauncher(
        id: "vermut",
        name: "Vermut",
        licenseLine: "Included source · MIT",
        summary: "A separate launcher for Steam, Epic, and GOG. It keeps its own Windows environments and graphics choices. The disk image is not in the folder.",
        sourceFolder: "third_party/vermut",
        guideRelativePath: "docs/VERMUT.md",
        guideBundleName: "VERMUT.md",
        guideFallback: "Vermut guide not found. See docs/VERMUT.md in the Cosmos project.",
        buildScript: "scripts/build_vermut.command",
        buildConfirmTitle: "Build Vermut on this Mac?",
        buildConfirmMessage: "This compiles the included Vermut 1.2.0 source. It needs macOS 14 or later and the Swift tools. The first build can take several minutes.",
        systemImage: "bag.fill"
    )

    static let all: [IncludedLauncher] = [highball, vermut]
}

/// The launcher cards, shared by the Tools section and the folded Launch row.
struct IncludedLaunchersCards: View {
    var isRunning: Bool
    var availability: [String: IncludedLauncherAvailability]
    var onGuide: (IncludedLauncher) -> Void
    var onReveal: (IncludedLauncher) -> Void
    var onBuild: (IncludedLauncher) -> Void

    @State private var pendingBuild: IncludedLauncher?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(IncludedLaunchers.all) { launcher in
                card(launcher, availability: availability[launcher.id] ?? .unavailable)
            }
        }
        .confirmationDialog(
            pendingBuild?.buildConfirmTitle ?? "Build this launcher?",
            isPresented: Binding(
                get: { pendingBuild != nil },
                set: { if !$0 { pendingBuild = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Build") {
                if let pendingBuild {
                    onBuild(pendingBuild)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(pendingBuild?.buildConfirmMessage ?? "")
        }
    }

    private func card(_ launcher: IncludedLauncher, availability: IncludedLauncherAvailability) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(launcher.name, systemImage: launcher.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.cosmosPrimary)
                Spacer(minLength: 8)
                Text(launcher.licenseLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(launcher.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !availability.hasSource {
                Text(IncludedLaunchers.missingSource)
                    .font(.caption)
                    .foregroundStyle(Color.cosmosWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions(launcher, availability: availability) }
                VStack(alignment: .leading, spacing: 8) { actions(launcher, availability: availability) }
            }
        }
        .cosmosCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("included-launcher-\(launcher.id)")
    }

    @ViewBuilder
    private func actions(_ launcher: IncludedLauncher, availability: IncludedLauncherAvailability) -> some View {
        Button {
            onGuide(launcher)
        } label: {
            Label("Guide", systemImage: "book")
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
        .help("Open the \(launcher.name) notes")

        if availability.hasSource {
            Button {
                onReveal(launcher)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(isRunning)
            .help("Reveal the included \(launcher.name) source")
        }

        if availability.canBuild {
            Button {
                pendingBuild = launcher
            } label: {
                Label("Build", systemImage: "hammer")
            }
            .buttonStyle(.bordered)
            .disabled(isRunning)
            .help("Compile \(launcher.name) on this Mac. Needs macOS 14 or later.")
        }
    }
}
