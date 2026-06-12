import SwiftUI

/// Right-click menu for bottle cards on the Bottles tab.
struct BottleContextMenuItems: View {
    let bottle: Bottle
    let isSelected: Bool
    let isRunning: Bool
    var onSelect: () -> Void
    var onLaunchSteam: () -> Void
    var onOpenLogs: () -> Void
    var onRevealPrefix: () -> Void
    var onReset: () -> Void
    var onDelete: () -> Void

    var body: some View {
        if !isSelected {
            Button(action: onSelect) {
                Label("Select Bottle", systemImage: "checkmark.circle")
            }
        }

        Button(action: onLaunchSteam) {
            Label("Launch Steam in Bottle", systemImage: "play.fill")
        }
        .disabled(isRunning)

        Divider()

        Button(action: onOpenLogs) {
            Label("Open Bottle Logs", systemImage: "doc.text.magnifyingglass")
        }
        .disabled(isRunning)

        Button(action: onRevealPrefix) {
            Label("Reveal Prefix in Finder", systemImage: "folder")
        }

        Divider()

        Button(role: .destructive, action: onReset) {
            Label("Reset Prefix…", systemImage: "arrow.counterclockwise")
        }
        .disabled(isRunning)

        Button(role: .destructive, action: onDelete) {
            Label("Delete Bottle…", systemImage: "trash")
        }
        .disabled(isRunning)
    }
}

extension View {
    func bottleContextMenu(
        bottle: Bottle,
        isSelected: Bool,
        isRunning: Bool,
        onSelect: @escaping () -> Void,
        onLaunchSteam: @escaping () -> Void,
        onOpenLogs: @escaping () -> Void,
        onRevealPrefix: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        contextMenu {
            BottleContextMenuItems(
                bottle: bottle,
                isSelected: isSelected,
                isRunning: isRunning,
                onSelect: onSelect,
                onLaunchSteam: onLaunchSteam,
                onOpenLogs: onOpenLogs,
                onRevealPrefix: onRevealPrefix,
                onReset: onReset,
                onDelete: onDelete
            )
        }
    }
}
