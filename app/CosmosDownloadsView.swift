import SwiftUI
import AppKit

enum CosmosDownload: String, CaseIterable, Identifiable {
    case recommended, wine, dxmt, moltenvk, dxvk, spock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recommended: return "Wine + DXMT"
        case .wine: return "Wine"
        case .dxmt: return "DXMT"
        case .moltenvk: return "MoltenVK"
        case .dxvk: return "DXVK + MoltenVK"
        case .spock: return "SpockD3D9"
        }
    }
    var detail: String {
        switch self {
        case .recommended: return "Start here. Downloads the Windows compatibility engine and the recommended DirectX 11 graphics component."
        case .wine: return "Runs Windows apps and games. Includes WineD3D for older games."
        case .dxmt: return "Translates DirectX 11 graphics to Metal. Requires Wine to run games."
        case .moltenvk: return "Adds Vulkan support through Metal, used by Spock and DXVK."
        case .dxvk: return "An experimental alternative for DirectX games. Downloads both components together."
        case .spock: return "Experimental DirectX 9 support. Downloads source and builds 32-bit and 64-bit DLLs. Installs build tools through Homebrew first; this can take several minutes and several GB. MoltenVK is also needed to play."
        }
    }
    var arguments: [String] {
        self == .spock
            ? ["--build-spockd3d9", "--arch", "both", "--install-tools"]
            : ["--download-component", rawValue]
    }
}

/// Download actions share the dashboard's process state, so closing the sheet
/// never starts a second download or loses the running operation.
struct CosmosDownloadsView: View {
    let busy: Bool
    let operationTitle: String
    let result: String?
    let failed: Bool
    let output: String
    let wineInstalled: Bool
    let completed: Set<CosmosDownload>
    let activeDownload: CosmosDownload?
    let onDownload: (CosmosDownload) -> Void
    let onRetry: () -> Void
    let onContinueSetup: () -> Void
    let onChooseSpock: () -> Void
    let onChooseGPTK: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloads").font(.largeTitle.bold())
                    Text("Start with Wine + DXMT. Add other components when a game needs them.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CosmosStorageNotice()
                    componentRow(.recommended)
                    Text("Individual components").font(.headline).padding(.top, 8)
                    ForEach(CosmosDownload.allCases.filter { $0 != .recommended }) { component in
                        componentRow(component)
                    }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Apple Game Porting Toolkit").font(.headline)
                            Text("Download from Apple, then choose your extracted toolkit in Cosmos.").foregroundStyle(.secondary)
                            HStack {
                                Link("Get from Apple ↗", destination: URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!)
                                Spacer()
                                Button("Choose Toolkit…", action: onChooseGPTK).disabled(busy)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                }.padding(2)
            }
            if busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(operationTitle).font(.callout)
                    Spacer()
                }
                Text("You can close this window while Cosmos works. Keep the app open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let result {
                VStack(alignment: .leading, spacing: 8) {
                    Label(result, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(failed ? Color.orange : Color.primary)
                        .textSelection(.enabled)
                    if failed {
                        Button("Try Again", action: onRetry).disabled(busy)
                    } else {
                        Button("Back to Setup", action: onContinueSetup).disabled(busy)
                    }
                }
            }
            if !output.isEmpty {
                DisclosureGroup("Activity details", isExpanded: $showDetails) {
                    VStack(alignment: .trailing) {
                        Button("Copy Details") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(output, forType: .string)
                        }
                        ScrollView {
                            Text(output).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 90)
                    }
                }
            }
            Text("Downloads use the versions selected by Cosmos. Existing components are reused. After downloading, continue setup or select a component in Graphics settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 700, height: 700)
        .onAppear { showDetails = failed }
        .onChange(of: failed) { if $0 { showDetails = true } }
    }

    private func componentRow(_ component: CosmosDownload) -> some View {
        let available = completed.contains(component) || (component == .wine && wineInstalled)
        let active = activeDownload == component
        let actionTitle = active ? (component == .spock ? "Building…" : "Downloading…")
            : component == .spock ? (available ? "Build Again" : "Install Tools & Build")
            : available ? "Check Again" : component == .recommended ? "Download Recommended" : "Download"
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(component.title).font(.headline)
                    if component == .recommended {
                        Text("Recommended").font(.caption).foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    if available {
                        Label("Available", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(component.detail).font(.callout).foregroundStyle(.secondary)
                HStack {
                    if component == .spock {
                        Link("Get Homebrew ↗", destination: URL(string: "https://brew.sh")!)
                        Button("Choose Existing DLLs…", action: onChooseSpock).disabled(busy)
                    }
                    Spacer()
                    Button(actionTitle) {
                        onDownload(component)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                    .accessibilityLabel("\(actionTitle) \(component.title)")
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }
}
