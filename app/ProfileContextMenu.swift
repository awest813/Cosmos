import AppKit
import SwiftUI

/// Optional extra actions for saved launcher profile menus.
struct ProfileContextMenuExtras {
    var onShowInLibrary: (() -> Void)?
    var onApplyCurated: (() -> Void)?
    var onVerifyInstall: (() -> Void)?
}

/// Shared right-click menu for saved launcher profiles (sidebar + library).
struct ProfileContextMenuItems: View {
    let profile: SavedProfile
    let isFavorite: Bool
    let canLaunch: Bool
    let isRunning: Bool
    var extras: ProfileContextMenuExtras = ProfileContextMenuExtras()
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

        if let onShowInLibrary = extras.onShowInLibrary {
            Button(action: onShowInLibrary) {
                Label("Show in Game Library", systemImage: "square.grid.2x2")
            }
        }

        if let onApplyCurated = extras.onApplyCurated {
            Button(action: onApplyCurated) {
                Label("Apply Curated Profile", systemImage: "wand.and.stars")
            }
            .disabled(isRunning)
        }

        Divider()

        Button(action: onReveal) {
            Label("Reveal Config in Finder", systemImage: "folder")
        }

        if let onCopyPath, !profile.path.isEmpty {
            Button(action: onCopyPath) {
                Label("Copy Executable Path", systemImage: "doc.on.doc")
            }
        }

        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(profile.fileURL.path, forType: .string)
        } label: {
            Label("Copy Config Path", systemImage: "doc.on.doc")
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

            if let onVerifyInstall {
                Button(action: onVerifyInstall) {
                    Label("Verify Steam Install", systemImage: "checkmark.shield")
                }
                .disabled(isRunning)
            }
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
        extras: ProfileContextMenuExtras = ProfileContextMenuExtras(),
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
                extras: extras,
                onLaunch: onLaunch,
                onToggleFavorite: onToggleFavorite,
                onReveal: onReveal,
                onCopyPath: onCopyPath
            )
        }
    }
}
