import SwiftUI

/// Manages `.app` launcher generation and shows the current state of
/// `/Applications/Merlot Apps`.
struct LaunchersView: View {
    @EnvironmentObject private var engine: CiderEngine

    @State private var installedApps: [String] = []

    private let merlotAppsPath = "/Applications/Merlot Apps"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Launchers")
                    .font(.largeTitle.bold())

                GroupBox("Installed Launchers") {
                    if installedApps.isEmpty {
                        Text("No launchers found in \(merlotAppsPath).")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(installedApps, id: \.self) { app in
                                HStack {
                                    Image(systemName: "app.fill")
                                        .foregroundStyle(.blue)
                                    Text(app)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await engine.rebuildLaunchers()
                            refreshInstalledApps()
                        }
                    } label: {
                        Label("Rebuild All Launchers", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isRunning)

                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: merlotAppsPath)
                    } label: {
                        Label("Open in Finder", systemImage: "folder")
                    }
                    .disabled(!FileManager.default.fileExists(atPath: merlotAppsPath))

                    Button {
                        refreshInstalledApps()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                if engine.isRunning {
                    ProgressView("Rebuilding…")
                }

                GroupBox("How It Works") {
                    Text("""
                    Cider uses `install_merlot.command` to generate lightweight \
                    `.app` bundles inside `/Applications/Merlot Apps`. Each bundle \
                    contains the shared launcher, a copy of `run.command`, and a \
                    per-game `merlot.env` with the profile's environment overrides.

                    Add or edit game profiles in the **Library** tab, then click \
                    **Rebuild All Launchers** to regenerate the apps.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .onAppear { refreshInstalledApps() }
    }

    private func refreshInstalledApps() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: merlotAppsPath) else {
            installedApps = []
            return
        }
        installedApps = contents
            .filter { $0.hasSuffix(".app") }
            .sorted()
    }
}
