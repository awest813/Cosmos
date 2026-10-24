import SwiftUI

/// Battle.net, Epic, and GOG launch fixes documented by Soju.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Store launch (Soju)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.cosmosPrimary)
            Text("Battle.net, Epic, and GOG need Rosetta to advertise AVX, a writable login page, and Apple's D3DMetal installed as a Metal library plus Windows shims plus unix symlinks. Cosmos applies those fixes itself. Download the Game Porting Toolkit from Apple; it is not included.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            modePicker(
                title: "AVX on Apple Silicon",
                selection: rosettaAvx,
                accessibilityLabel: "AVX advertising",
                caption: rosettaAvx == "off"
                    ? "Off leaves Rosetta's CPU report unchanged."
                    : "Auto turns this on for Apple Silicon. Diablo II: Resurrected waits forever without it.",
                onChange: onAvxChange
            )

            modePicker(
                title: "Store login page",
                selection: wineWritecopy,
                accessibilityLabel: "Store login page",
                caption: wineWritecopy == "on"
                    ? "On for every launch. Battle.net's login page stays blank without it."
                    : "Auto turns this on for Battle.net, Epic, and GOG. Steam stays on the usual setting.",
                onChange: onWritecopyChange
            )

            if !status.message.isEmpty {
                Text(status.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("soju-status-message")
            }

            HStack(spacing: 8) {
                Button(action: onCheckLayout) {
                    Label("Check D3DMetal layout", systemImage: "checkmark.shield")
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)

                Button(action: onInstallLayout) {
                    Label("Install D3DMetal layout", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.cosmosPrimary)
                .disabled(isRunning)

                Button(action: onUndoLayout) {
                    Label("Undo layout", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)
            }

            HStack(spacing: 8) {
                Button(action: onSeedBattleNet) {
                    Label("Seed Battle.net", systemImage: "signature")
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)

                Button(action: onGuide) {
                    Label("Guide", systemImage: "book")
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)
            }
        }
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
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
