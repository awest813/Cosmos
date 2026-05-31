import SwiftUI

/// Shows the installation status of each prerequisite and offers a one-click
/// "Install Everything" button.
struct SetupStatusView: View {
    @EnvironmentObject private var engine: CiderEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Setup Status")
                    .font(.largeTitle.bold())

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        statusRow("Rosetta 2", installed: engine.setupState.rosettaInstalled)
                        statusRow("Wine (\(CiderEngine.defaultWineVersion))", installed: engine.setupState.wineInstalled)
                        statusRow("Wine Prefix", installed: engine.setupState.winePrefixReady)
                        statusRow("Steam", installed: engine.setupState.steamInstalled)
                        statusRow("DXMT (\(CiderEngine.defaultDXMTVersion))", installed: engine.setupState.dxmtInstalled)
                    }
                    .padding(.vertical, 4)
                }

                if engine.setupState.isReady {
                    Label("All components installed — ready to play.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                } else {
                    Label("Some components are missing.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.headline)
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await engine.installAndLaunchSteam() }
                    } label: {
                        Label("Install Everything & Launch Steam", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isRunning)

                    Button {
                        engine.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(engine.isRunning)
                }

                if engine.isRunning {
                    ProgressView("Working…")
                        .padding(.top, 4)
                }

                if let err = engine.lastError {
                    GroupBox("Error") {
                        Text(err)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }

                if !engine.lastOutput.isEmpty {
                    GroupBox("Output") {
                        ScrollView {
                            Text(engine.lastOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func statusRow(_ label: String, installed: Bool) -> some View {
        HStack {
            Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(installed ? .green : .secondary)
            Text(label)
            Spacer()
            Text(installed ? "Installed" : "Not found")
                .foregroundStyle(installed ? .green : .secondary)
                .font(.callout)
        }
    }
}
