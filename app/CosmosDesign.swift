import SwiftUI

// MARK: - Design tokens

enum CosmosSpacing {
    static let section: CGFloat = 28
    static let contentPadding: CGFloat = 28
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 14
    static let tileRadius: CGFloat = 12
    static let gridGap: CGFloat = 12
    static let sectionInner: CGFloat = 12
    static let tilePadding: CGFloat = 12
    static let gridColumnMin: CGFloat = 168
    static let compactGridColumnMin: CGFloat = 150
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
        case .library: return "Launcher library, profiles, and repairs"
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

struct CommandBannerAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let action: () -> Void
}

struct CommandBanner: Identifiable {
    let id = UUID()
    let kind: CommandBannerKind
    let message: String
    var actions: [CommandBannerAction] = []
}

// MARK: - Interaction styling

/// Press feedback for custom dashboard buttons.
struct CosmosButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Subtle brighten-on-hover for pointer feedback on macOS.
struct HoverBrighten: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .brightness(isHovering && !reduceMotion ? 0.06 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

extension View {
    func hoverBrighten() -> some View { modifier(HoverBrighten()) }
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
                prominent
                    ? Color.cosmosPrimary.opacity(0.08)
                    : Color.cosmosCardFill,
                in: RoundedRectangle(cornerRadius: CosmosSpacing.cardRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CosmosSpacing.cardRadius)
                    .strokeBorder(
                        prominent ? Color.cosmosPrimary.opacity(0.22) : Color.cosmosCardBorder,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.cosmosPrimary.opacity(prominent ? 0.08 : 0.04),
                radius: prominent ? 10 : 6,
                y: 2
            )
    }
}

extension View {
    func cosmosCard(prominent: Bool = false) -> some View {
        modifier(CosmosCard(prominent: prominent))
    }
}

/// Shared selectable tile surface for profile, bottle, and grid cards.
struct CosmosSelectableSurface: ViewModifier {
    let isSelected: Bool
    var minHeight: CGFloat = 72

    func body(content: Content) -> some View {
        content
            .padding(CosmosSpacing.tilePadding)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
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
    }
}

extension View {
    func cosmosSelectableSurface(isSelected: Bool, minHeight: CGFloat = 72) -> some View {
        modifier(CosmosSelectableSurface(isSelected: isSelected, minHeight: minHeight))
    }
}

// MARK: - Reusable views

/// Tinted notice banner shared by command feedback, setup completion, and inline warnings.
struct CosmosNoticeBanner: View {
    let tint: Color
    let systemImage: String
    let title: String?
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: CosmosSpacing.sectionInner) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title)
                        .font(.headline)
                }
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(title == nil ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss notification")
            }
        }
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: CosmosSpacing.buttonRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CosmosSpacing.buttonRadius)
                .strokeBorder(tint.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

struct CommandBannerView: View {
    let banner: CommandBanner
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CosmosSpacing.sectionInner) {
            CosmosNoticeBanner(
                tint: banner.kind.tint,
                systemImage: banner.kind.icon,
                title: nil,
                message: banner.message,
                onDismiss: onDismiss
            )
            if !banner.actions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(banner.actions) { item in
                        Button {
                            item.action()
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

/// Section header + optional caption + body, with optional card wrapper.
struct CosmosSection<Content: View>: View {
    let title: String
    let systemImage: String
    var caption: String? = nil
    var inCard: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: CosmosSpacing.sectionInner) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.cosmosPrimary)
            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if inCard {
                    content().cosmosCard()
                } else {
                    content()
                }
            }
        }
    }
}

/// Uppercase label for nested groups inside a section (e.g. Dependencies, Fixes).
struct CosmosSubsectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.cosmosPrimary.opacity(0.75))
            .textCase(.uppercase)
    }
}

/// Compact action tile for repair recipes, store import, and similar grids.
struct CosmosActionTile: View {
    let title: String
    let subtitle: String
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
            } else {
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CosmosSpacing.tilePadding - 2)
        .background(Color.cosmosTileFill, in: RoundedRectangle(cornerRadius: CosmosSpacing.tileRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CosmosSpacing.tileRadius)
                .strokeBorder(Color.cosmosCardBorder, lineWidth: 1)
        )
        .hoverBrighten()
    }
}

/// Compatibility status pill — sidebar rows, curated cards, and the Compatibility tab.
struct CosmosCompatBadge: View {
    let status: String
    var compact: Bool = false

    var body: some View {
        Text(status.capitalized)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 4)
            .background(Self.color(for: status).opacity(0.15), in: Capsule())
            .foregroundStyle(Self.color(for: status))
            .lineLimit(1)
            .accessibilityLabel("Compatibility \(status)")
    }

    static func color(for status: String) -> Color {
        switch status.lowercased() {
        case "platinum", "gold": return .green
        case "silver", "playable": return Color.cosmosPrimary
        case "bronze": return .orange
        case "broken", "blocked": return .red
        default: return .secondary
        }
    }
}

/// Sidebar list filter for saved game profiles (favorites / recent / full catalog).
enum SidebarProfileFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case recent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        }
    }
}

/// Filter chips for the curated YAML profile grid (Phase B library visibility).
enum CuratedProfileFilter: String, CaseIterable, Identifiable {
    case all
    case coOp = "co-op"
    case online
    case blocked
    case dxmt
    case d3dmetal
    case recommended

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .coOp: return "Co-op"
        case .online: return "Online"
        case .blocked: return "Blocked"
        case .dxmt: return "DXMT"
        case .d3dmetal: return "D3D Metal"
        case .recommended: return "Recommended"
        }
    }

    func matches(_ profile: GameProfile) -> Bool {
        switch self {
        case .all:
            return true
        case .coOp:
            return profile.tags.contains("co-op")
                || profile.notes.localizedCaseInsensitiveContains("co-op")
                || profile.multiplayerNotes.localizedCaseInsensitiveContains("co-op")
        case .online:
            return profile.tags.contains("online")
        case .blocked:
            return profile.status == "blocked"
        case .dxmt:
            return profile.recommendedBackend == "dxmt"
        case .d3dmetal:
            return profile.recommendedBackend == "d3dmetal"
        case .recommended:
            return profile.recommendedBackend == "recommended"
        }
    }
}

/// Pill filter chip for curated profile grids and similar toggles.
struct CosmosFilterChip: View {
    let label: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        Capsule().fill(CosmosGradients.primaryButton)
                    } else {
                        Capsule().fill(Color.cosmosTileFill)
                    }
                }
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color.cosmosCardBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(CosmosButtonStyle())
        .hoverBrighten()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Horizontal tab bar for post-setup dashboard sections (replaces plain segmented control).
struct CosmosDashboardTabBar: View {
    @Binding var selection: DashboardSection

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DashboardSection.allCases) { section in
                let isSelected = selection == section
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selection = section
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.systemImage)
                            .font(.caption.weight(.semibold))
                        Text(section.rawValue)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: CosmosSpacing.buttonRadius)
                        if isSelected {
                            shape.fill(CosmosGradients.primaryButton)
                        } else {
                            shape.fill(Color.cosmosTileFill)
                        }
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: CosmosSpacing.buttonRadius)
                            .strokeBorder(
                                isSelected ? Color.clear : Color.cosmosCardBorder,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(CosmosButtonStyle())
                .hoverBrighten()
                .accessibilityLabel("\(section.rawValue). \(section.subtitle)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dashboard section")
    }
}

/// Branded search field for the sidebar profile list.
struct CosmosSearchField: View {
    let placeholder: String
    @Binding var text: String
    var disabled: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.cosmosPrimary.opacity(0.65))
                .font(.caption.weight(.semibold))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.cosmosTileFill, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.cosmosCardBorder, lineWidth: 1)
        )
        .disabled(disabled)
    }
}

/// Terminal-style log output panel.
struct CosmosConsolePanel<Content: View>: View {
    var minHeight: CGFloat = 140
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(minHeight: minHeight)
            .background(Color.cosmosConsoleBackground, in: RoundedRectangle(cornerRadius: CosmosSpacing.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CosmosSpacing.cardRadius)
                    .strokeBorder(Color.cosmosBright.opacity(0.15), lineWidth: 1)
            )
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
            .background(
                tint.opacity(0.14),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
            .foregroundStyle(tint)
            .help(label)
    }
}
