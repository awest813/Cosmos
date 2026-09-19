import SwiftUI

/// Stable visual fallback that works offline and makes a text-only library scannable.
struct CosmosGameIdentity: View {
    let name: String
    var size: CGFloat = 64

    private var initials: String {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(CosmosGradients.primaryButton, in: RoundedRectangle(cornerRadius: size * 0.24))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.24)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct CosmosGameLaunchPanel: View {
    let profile: SavedProfile
    let compatibility: String?
    let environmentName: String
    let canLaunch: Bool
    let isBusy: Bool
    let isFavorite: Bool
    let onPlay: () -> Void
    let onFavorite: () -> Void

    private var statusMessage: String {
        if !profile.canLaunchFromDashboard { return "Add an executable path or Steam App ID to configure this game." }
        if !canLaunch { return "Finish setting up the Windows environment to play this game." }
        switch compatibility?.lowercased() {
        case "blocked", "broken": return "Known compatibility issues. Review the warning before launching."
        case nil: return "Compatibility has not been confirmed for this game."
        default: return "Compatibility is guidance; results can vary by Mac and game version."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                CosmosGameIdentity(name: profile.name, size: 76)
                VStack(alignment: .leading, spacing: 7) {
                    Text(profile.libraryStore.label.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(profile.name)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Label(environmentName, systemImage: "cylinder.split.1x2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions }
                VStack(alignment: .leading, spacing: 12) { actions }
            }
            Text(isBusy ? "Another operation is in progress. You can keep browsing your library." : statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cosmosCard(prominent: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected game: \(profile.name)")
    }

    @ViewBuilder private var actions: some View {
        Button(action: onPlay) {
            Label("Play", systemImage: "play.fill")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 5)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.cosmosBrandIndigo)
        .disabled(!canLaunch || isBusy)
        .accessibilityLabel("Play \(profile.name)")
        .help("Play selected game (⌘Return)")
        Button(action: onFavorite) {
            Label(isFavorite ? "Favorited" : "Favorite", systemImage: isFavorite ? "star.fill" : "star")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("\(isFavorite ? "Remove" : "Add") \(profile.name) \(isFavorite ? "from" : "to") favorites")
        CosmosCompatBadge(status: compatibility ?? "Unknown")
    }
}

struct CosmosOperationProgress: View {
    let title: String
    let inTerminal: Bool
    let output: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(inTerminal ? "Complete any prompts in Terminal. Cosmos will report the result here." : "Working in the background. You can keep browsing your games.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            DisclosureGroup("Recent activity") {
                ScrollView {
                    Text(String(output.suffix(4000)))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 110)
            }
            .font(.caption)
        }
        .cosmosCard()
        .accessibilityElement(children: .contain)
    }
}
