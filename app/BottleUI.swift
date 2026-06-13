import SwiftUI

// MARK: - Display helpers

enum BottleStatusKind: Equatable {
    case notCreated
    case initialized
    case steamReady

    var label: String {
        switch self {
        case .notCreated: return "Not created"
        case .initialized: return "Prefix ready"
        case .steamReady: return "Steam ready"
        }
    }

    var systemImage: String {
        switch self {
        case .notCreated: return "circle.dashed"
        case .initialized: return "checkmark.circle"
        case .steamReady: return "shippingbox.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notCreated: return .secondary
        case .initialized: return .orange
        case .steamReady: return .green
        }
    }
}

extension Bottle {
    var configURL: URL {
        prefixURL.deletingLastPathComponent().appendingPathComponent("bottle.conf")
    }

    var statusKind: BottleStatusKind {
        guard isInitialized else { return .notCreated }
        return steamInstalled ? .steamReady : .initialized
    }

    var backendDisplayName: String {
        SettingLabels.backendDisplayName(backend)
    }

    /// Secondary line on bottle cards — Windows version, sync mode, optional Retina flag.
    var cardDetailLine: String {
        var parts: [String] = [windowsDisplay]
        if syncMode != "off" {
            parts.append(syncMode)
        }
        if retinaEnabled {
            parts.append("Retina")
        }
        return parts.joined(separator: " · ")
    }

    func cardAccessibilityLabel(isSelected: Bool) -> String {
        var parts = [name, backendDisplayName, statusKind.label, cardDetailLine]
        if isSelected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Card

struct BottleStatusChip: View {
    let kind: BottleStatusKind

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.systemImage)
                .font(.caption2.weight(.semibold))
            Text(kind.label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(kind.tint)
        .accessibilityLabel("Status: \(kind.label)")
    }
}

struct BottleCard: View {
    let bottle: Bottle
    let isSelected: Bool
    let isRunning: Bool
    var onToggleSelection: () -> Void
    var onSelect: () -> Void
    var onLaunchSteam: () -> Void
    var onOpenLogs: () -> Void
    var onRevealPrefix: () -> Void
    var onRevealConfig: () -> Void
    var onReset: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(action: onToggleSelection) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "cylinder.split.1x2.fill")
                        .font(.title2)
                        .foregroundStyle(Color.cosmosPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bottle.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(bottle.backendDisplayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.cosmosBright)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    BottleStatusChip(kind: bottle.statusKind)
                }

                Text(bottle.cardDetailLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .cosmosSelectableSurface(isSelected: isSelected, minHeight: 118)
        }
        .buttonStyle(CosmosButtonStyle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onLaunchSteam()
        })
        .disabled(isRunning)
        .opacity(isRunning ? 0.55 : 1)
        .help(isRunning ? "Unavailable while a command is running" : "Double-click to launch Steam in this bottle")
        .accessibilityLabel(bottle.cardAccessibilityLabel(isSelected: isSelected))
        .accessibilityHint(isRunning
            ? "Unavailable while a command is running"
            : "Double-click to launch Steam in this bottle")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .bottleContextMenu(
            bottle: bottle,
            isSelected: isSelected,
            isRunning: isRunning,
            onSelect: onSelect,
            onLaunchSteam: onLaunchSteam,
            onOpenLogs: onOpenLogs,
            onRevealPrefix: onRevealPrefix,
            onRevealConfig: onRevealConfig,
            onReset: onReset,
            onDelete: onDelete
        )
    }
}
