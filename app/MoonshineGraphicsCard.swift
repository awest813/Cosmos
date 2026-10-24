import SwiftUI

/// OpenGL 3.2 check and Wine log detail.
/// Original Cosmos code. Moonshine and Whisky are GPL-3.0 and are not copied into this file.
struct MoonshineGraphicsCard: View {
    var preset: String
    var status: OpenGLPatchStatus
    var isRunning: Bool
    var onPresetChange: (String) -> Void
    var onCheck: () -> Void
    var onApply: () -> Void
    var onUndo: () -> Void
    var onGuide: () -> Void

    @State private var pendingApply = false
    @State private var pendingUndo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Some games need an OpenGL 3.2 window. Cosmos can turn that on in Wine when this Wine build still has the original check. A different build is left alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Wine logs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                    .textCase(.uppercase)
                Picker("Wine logs", selection: Binding(get: { preset }, set: onPresetChange)) {
                    Text("Quiet").tag("cosmos")
                    Text("Detailed").tag("moonshine")
                }
                .pickerStyle(.segmented)
                .disabled(isRunning)
                .accessibilityLabel("Wine log detail")
                .accessibilityValue(preset == "moonshine" ? "Detailed" : "Quiet")
                Text(preset == "moonshine"
                    ? "Detailed records Wine warnings and which libraries loaded, so a crash is easier to read."
                    : "Quiet keeps the log to errors. This is the usual Cosmos setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                .accessibilityIdentifier("opengl-status-message")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actionButtons }
                VStack(alignment: .leading, spacing: 8) { actionButtons }
            }
        }
        .confirmationDialog(
            "Turn on OpenGL 3.2?",
            isPresented: $pendingApply,
            titleVisibility: .visible
        ) {
            Button("Apply") { onApply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cosmos changes one check in Wine's Mac driver, and only when that check still matches. You can undo it.")
        }
        .confirmationDialog(
            "Restore the original OpenGL check?",
            isPresented: $pendingUndo,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) { onUndo() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Wine goes back to the check it shipped with. Games that need OpenGL 3.2 may fail to open a window again.")
        }
    }

    private var statusTint: Color {
        switch status.status {
        case "patched": return Color.cosmosSuccess
        case "mismatch", "error": return Color.cosmosWarning
        default: return Color.cosmosPrimary
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            onCheck()
        } label: {
            Label("Check", systemImage: "checkmark.shield")
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
        .help("See whether this Wine build can take the OpenGL 3.2 fix")

        Button {
            pendingApply = true
        } label: {
            Label("Apply", systemImage: "wand.and.stars")
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.cosmosPrimary)
        .disabled(isRunning)
        .help("Turn on OpenGL 3.2 when the check still matches")

        Button {
            pendingUndo = true
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
        .help("Restore Wine's original OpenGL check")

        Button(action: onGuide) {
            Label("Guide", systemImage: "book")
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
    }
}
