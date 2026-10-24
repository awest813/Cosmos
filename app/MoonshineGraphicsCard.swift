import SwiftUI

/// OpenGL 3.2 check and Wine log detail inspired by Moonshine.
/// Cosmos implements this itself. Moonshine and Whisky are GPL-3.0 and are not included.
struct MoonshineGraphicsCard: View {
    var preset: String
    var status: OpenGLPatchStatus
    var isRunning: Bool
    var onPresetChange: (String) -> Void
    var onCheck: () -> Void
    var onApply: () -> Void
    var onUndo: () -> Void
    var onGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OpenGL (Moonshine)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.cosmosPrimary)
            Text("SDL3 and some older games need an OpenGL 3.2 context. Cosmos flips one check in Wine's Mac driver only when that byte still matches. A different Wine build is left alone.")
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
                    ? "Detailed records Wine warnings and module loads, so a crash is easier to read."
                    : "Quiet keeps the log to errors. This is the Cosmos default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !status.message.isEmpty {
                Text(status.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("opengl-status-message")
            }
            if !status.path.isEmpty {
                Text(status.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                Button(action: onCheck) {
                    Label("Check OpenGL fix", systemImage: "checkmark.shield")
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)

                Button(action: onApply) {
                    Label("Apply OpenGL fix", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.cosmosPrimary)
                .disabled(isRunning)

                Button(action: onUndo) {
                    Label("Undo OpenGL fix", systemImage: "arrow.uturn.backward")
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
}
