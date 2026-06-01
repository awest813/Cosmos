import SwiftUI

/// Repair tools: view logs, reinstall components, kill processes.
struct RepairView: View {
    @EnvironmentObject private var engine: CiderEngine
    @State private var logText = ""
    @State private var showConfirmReset = false
    private static let resetWarning = "Deletes the entire Wine prefix (\(CiderEngine.defaultWinePrefix)). Steam and all game data in the prefix will be lost. You will need to re-run setup."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Logs & Repair")
                    .font(.largeTitle.bold())

                // -- Logs --
                GroupBox("Steam Log") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                logText = engine.readSteamLog()
                            } label: {
                                Label("Load Log", systemImage: "doc.text")
                            }

                            Button {
                                let url = URL(fileURLWithPath: CiderEngine.defaultSteamLog)
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label("Open in Console", systemImage: "terminal")
                            }
                        }

                        if !logText.isEmpty {
                            ScrollView {
                                Text(logText)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 250)
                        }
                    }
                }

                // -- Repair actions --
                GroupBox("Repair Actions") {
                    VStack(alignment: .leading, spacing: 12) {
                        repairButton(
                            title: "Reinstall DXMT",
                            icon: "arrow.triangle.2.circlepath",
                            help: "Deletes the current DXMT installation and re-downloads it."
                        ) {
                            Task { await engine.reinstallDXMT() }
                        }

                        repairButton(
                            title: "Rebuild Launchers",
                            icon: "apps.iphone",
                            help: "Regenerates all `.app` bundles in /Applications/Merlot Apps."
                        ) {
                            Task { await engine.rebuildLaunchers() }
                        }

                        repairButton(
                            title: "Kill Wine / Steam",
                            icon: "xmark.octagon",
                            help: "Force-kills all Wine and Steam processes."
                        ) {
                            Task { await engine.killWineProcesses() }
                        }

                        Divider()

                        Button(role: .destructive) {
                            showConfirmReset = true
                        } label: {
                            Label("Reset Wine Prefix", systemImage: "trash")
                        }
                        .help(Self.resetWarning)
                    }
                    .padding(.vertical, 4)
                }

                if engine.isRunning {
                    ProgressView("Working…")
                }

                if let err = engine.lastError {
                    GroupBox("Error") {
                        Text(err)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
        }
        .alert("Reset Wine Prefix?", isPresented: $showConfirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { await engine.resetWinePrefix() }
            }
        } message: {
            Text(Self.resetWarning)
        }
    }

    @ViewBuilder
    private func repairButton(title: String, icon: String, help: String, action: @escaping () -> Void) -> some View {
        HStack {
            Button(action: action) {
                Label(title, systemImage: icon)
            }
            .disabled(engine.isRunning)

            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
