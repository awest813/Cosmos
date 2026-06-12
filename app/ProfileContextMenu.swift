import AppKit
import SwiftUI

/// Shared right-click menu for saved launcher profiles (sidebar + library).
struct ProfileContextMenuItems: View {
    let profile: SavedProfile
    let isFavorite: Bool
    let canLaunch: Bool
    let isRunning: Bool
    var onLaunch: () -> Void
    var onToggleFavorite: () -> Void
    var onReveal: () -> Void
    var onCopyPath: (() -> Void)?

    var body: some View {
        Button(action: onLaunch) {
            Label("Launch", systemImage: "play.fill")
        }
        .disabled(!canLaunch || isRunning)

        Button(action: onToggleFavorite) {
            Label(
                isFavorite ? "Remove Favorite" : "Add to Favorites",
                systemImage: isFavorite ? "star.slash" : "star"
            )
        }
        .disabled(isRunning)

        Divider()

        Button(action: onReveal) {
            Label("Reveal Config in Finder", systemImage: "folder")
        }

        if let onCopyPath, !profile.path.isEmpty {
            Button(action: onCopyPath) {
                Label("Copy Executable Path", systemImage: "doc.on.doc")
            }
        }

        if profile.libraryStore == .steam {
            Divider()
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(profile.steamAppID ?? "", forType: .string)
            } label: {
                Label("Copy Steam App ID", systemImage: "number")
            }
            .disabled(profile.steamAppID?.isEmpty != false)
        } else if profile.libraryStore == .gog {
            Divider()
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(profile.gogSlug ?? "", forType: .string)
            } label: {
                Label("Copy GOG Slug", systemImage: "number")
            }
            .disabled(profile.gogSlug?.isEmpty != false)
        }
    }
}

extension View {
    func profileContextMenu(
        profile: SavedProfile,
        isFavorite: Bool,
        canLaunch: Bool,
        isRunning: Bool,
        onLaunch: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onCopyPath: (() -> Void)? = nil
    ) -> some View {
        contextMenu {
            ProfileContextMenuItems(
                profile: profile,
                isFavorite: isFavorite,
                canLaunch: canLaunch,
                isRunning: isRunning,
                onLaunch: onLaunch,
                onToggleFavorite: onToggleFavorite,
                onReveal: onReveal,
                onCopyPath: onCopyPath
            )
        }
    }
}
