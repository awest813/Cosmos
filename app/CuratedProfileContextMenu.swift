import AppKit
import SwiftUI

/// Right-click menu for curated YAML profile cards on the Games tab.
struct CuratedProfileContextMenuItems: View {
    let profile: GameProfile
    let isRunning: Bool
    var onApply: () -> Void
    var onShowCompatibility: () -> Void

    var body: some View {
        Button(action: onApply) {
            Label("Apply Profile", systemImage: "wand.and.stars")
        }
        .disabled(isRunning || profile.isBlocked)

        Button(action: onShowCompatibility) {
            Label("Look Up Compatibility", systemImage: "magnifyingglass")
        }
        .disabled(isRunning || profile.steamAppID.isEmpty)

        if profile.isUserAuthored {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([profile.fileURL])
            } label: {
                Label("Reveal Profile in Finder", systemImage: "folder")
            }
        }

        Divider()

        if !profile.steamAppID.isEmpty {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(profile.steamAppID, forType: .string)
            } label: {
                Label("Copy Steam App ID", systemImage: "number")
            }
        }

        if !profile.gogSlug.isEmpty {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(profile.gogSlug, forType: .string)
            } label: {
                Label("Copy GOG Slug", systemImage: "number")
            }
        }
    }
}

extension View {
    func curatedProfileContextMenu(
        profile: GameProfile,
        isRunning: Bool,
        onApply: @escaping () -> Void,
        onShowCompatibility: @escaping () -> Void
    ) -> some View {
        contextMenu {
            CuratedProfileContextMenuItems(
                profile: profile,
                isRunning: isRunning,
                onApply: onApply,
                onShowCompatibility: onShowCompatibility
            )
        }
    }
}
