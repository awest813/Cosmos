import SwiftUI

// MARK: - Design tokens

enum CosmosSpacing {
    static let section: CGFloat = 28
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 14
    static let gridGap: CGFloat = 12
}

// MARK: - Section navigation

/// Post-setup dashboard areas — reduces scroll fatigue by showing one focus area at a time.
enum DashboardSection: String, CaseIterable, Identifiable {
    case launch = "Launch"
    case library = "Games"
    case tools = "Tools"
    case bottles = "Bottles"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .launch: return "bolt.fill"
        case .library: return "gamecontroller.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .bottles: return "cylinder.split.1x2.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .launch: return "Quick launch and Steam settings"
        case .library: return "Profiles, compatibility, and repairs"
        case .tools: return "Maintenance, imports, and diagnostics"
        case .bottles: return "Isolated Wine prefixes"
        }
    }
}

// MARK: - Command feedback

enum CommandBannerKind {
    case success
    case failure
    case info

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        case .info: return Color.cosmosPrimary
        }
    }
}

struct CommandBanner: Identifiable {
    let id = UUID()
    let kind: CommandBannerKind
    let message: String
}

// MARK: - View modifiers

/// Standard Cosmos card surface used across settings panels and detail blocks.
struct CosmosCard: ViewModifier {
    var prominent: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(CosmosSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.cosmosPrimary.opacity(prominent ? 0.07 : 0.05),
                in: RoundedRectangle(cornerRadius: CosmosSpacing.cardRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CosmosSpacing.cardRadius)
                    .strokeBorder(Color.cosmosPrimary.opacity(0.15), lineWidth: 1)
            )
    }
}

extension View {
    func cosmosCard(prominent: Bool = false) -> some View {
        modifier(CosmosCard(prominent: prominent))
    }
}

// MARK: - Reusable views

struct CommandBannerView: View {
    let banner: CommandBanner
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: banner.kind.icon)
                .font(.title3)
                .foregroundStyle(banner.kind.tint)
            Text(banner.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss notification")
        }
        .padding(14)
        .background(banner.kind.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(banner.kind.tint.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Compact chip for toolbar status (active bottle, running task).
struct StatusChip: View {
    let label: String
    let systemImage: String
    var tint: Color = Color.cosmosPrimary

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
            .help(label)
    }
}
