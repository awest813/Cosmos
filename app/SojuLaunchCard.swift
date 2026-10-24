import SwiftUI

/// Battle.net, Epic, and GOG launch fixes.
/// Cosmos implements them itself. Soju is GPL-3.0 and is not included.
struct SojuLaunchCard: View {
    var rosettaAvx: String
    var wineWritecopy: String
    var status: SojuCommandStatus
    var isRunning: Bool
    var onAvxChange: (String) -> Void
    var onWritecopyChange: (String) -> Void
    var onCheckLayout: () -> Void
    var onInstallLayout: () -> Void
    var onUndoLayout: () -> Void
    var onSeedBattleNet: () -> Void
    var onGuide: () -> Void

    @State private var pendingInstall = false
    @State private var pendingUndo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("These stores need a few launch settings. AVX is for Apple Silicon. The login page is for Battle.net, Epic, and GOG. D3DMetal still comes from your own Apple download.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            modePicker(
                title: "AVX on Apple Silicon",
                selection: rosettaAvx,
                accessibilityLabel: "AVX on Apple Silicon",
                caption: GraphicsSettings.rosettaAvxCaption(for: rosettaAvx),
                onChange: onAvxChange
            )

            modePicker(
                title: "Store login page",
                selection: wineWritecopy,
                accessibilityLabel: "Store login page",
                caption: GraphicsSettings.wineWritecopyCaption(for: wineWritecopy),
                onChange: onWritecopyChange
            )

            if !status.headline.isEmpty || !status.detail.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if !status.headline.isEmpty {
                        Text(status.headline)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusTint)
                    }
                    if !status.detail.isEmpty {
                        Text(status.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("soju-status-message")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { layoutButtons }
                VStack(alignment: .leading, spacing: 8) { layoutButtons }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { otherButtons }
                VStack(alignment: .leading, spacing: 8) { otherButtons }
            }
        }
        .confirmationDialog(
            "Install the D3DMetal layout?",
            isPresented: $pendingInstall,
            titleVisibility: .visible
        ) {
            Button("Install") { onInstallLayout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cosmos copies Apple's Direct3D libraries into this Wine install and links them to D3DMetal. Wine's originals are saved so you can undo. An incomplete download is left untouched.")
        }
        .confirmationDialog(
            "Remove the D3DMetal layout?",
            isPresented: $pendingUndo,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) { onUndoLayout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Wine's original Direct3D libraries come back, and the D3DMetal copies are removed from the Wine install.")
        }
    }

    private var statusTint: Color {
        switch status.layout {
        case "complete": return Color.cosmosSuccess
        case "partial", "error": return Color.cosmosWarning
        default: return Color.cosmosPrimary
        }
    }

    @ViewBuilder
    private var layoutButtons: some View {
        Button(action: onCheckLayout) {
            Label("Check layout", systemImage: "checkmark.shield")
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
        .help("See whether D3DMetal's three pieces are installed")

        Button {
            pendingInstall = true
        } label: {
            Label("Install layout", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
        .help("Install D3DMetal into Wine. Your Apple download is required.")

        Button {
            pendingUndo = true
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
        .help("Restore Wine's original Direct3D libraries")
    }

    @ViewBuilder
    private var otherButtons: some View {
        Button(action: onSeedBattleNet) {
            Label("Update Battle.net", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
        .help("Copy Battle.net into each versioned folder so sign-in is accepted")

        Button(action: onGuide) {
            Label("Guide", systemImage: "book")
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
    }

    private func modePicker(
        title: String,
        selection: String,
        accessibilityLabel: String,
        caption: String,
        onChange: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                .textCase(.uppercase)
            Picker(title, selection: Binding(get: { selection }, set: onChange)) {
                Text("Auto").tag("auto")
                Text("On").tag("on")
                Text("Off").tag("off")
            }
            .pickerStyle(.segmented)
            .disabled(isRunning)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(selection == "on" ? "On" : (selection == "off" ? "Off" : "Auto"))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
