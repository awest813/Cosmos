import SwiftUI

struct ContentView: View {
    private let fileManager = FileManager.default
    private let repositoryRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private let profileDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cider/Profiles", isDirectory: true)
    private let merlotDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Merlot", isDirectory: true)
    private let steamExecutableURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cider/drive_c/Program Files (x86)/Steam/Steam.exe")

    @State private var output = "Welcome to Cider\n\nSelect a saved profile or use the quick actions to manage your setup."
    @State private var profiles: [SavedProfile] = []
    @State private var selectedProfileID: String?
    @State private var merlotInstalled = false
    @State private var steamInstalled = false
    @State private var isRunning = false

    private var selectedProfile: SavedProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cider")
                        .font(.largeTitle.weight(.bold))
                    Text("Apple Silicon game launcher dashboard")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                statusSummary

                List(selection: $selectedProfileID) {
                    Section("Saved Profiles") {
                        if profiles.isEmpty {
                            Text("No profiles saved yet")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(profiles) { profile in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name)
                                        .font(.headline)
                                    Text(profile.args.isEmpty ? profile.path : profile.args)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .tag(profile.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .padding(20)
            .frame(minWidth: 260)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection
                    actionGrid
                    if let selectedProfile {
                        selectedProfileSection(selectedProfile)
                    }
                    consoleSection
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .task {
            refreshStatus()
        }
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(merlotInstalled ? "Merlot installed" : "Merlot required", systemImage: merlotInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(merlotInstalled ? Color.green : Color.orange)
            Label(steamInstalled ? "Steam prefix ready" : "Steam not installed yet", systemImage: steamInstalled ? "shippingbox.fill" : "shippingbox")
                .foregroundStyle(steamInstalled ? Color.blue : Color.secondary)
            Label("\(profiles.count) saved profile\(profiles.count == 1 ? "" : "s")", systemImage: "gamecontroller")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedProfile?.name ?? "Launcher Dashboard")
                .font(.system(size: 30, weight: .bold))
            Text(selectedProfile == nil
                 ? "Manage Merlot, launch Steam, and quickly jump into saved game profiles from one place."
                 : "Ready to launch this saved profile through the existing Wine-based shell flow.")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                metricCard(title: "Profiles", value: "\(profiles.count)", icon: "list.bullet.rectangle")
                metricCard(title: "Merlot", value: merlotInstalled ? "Installed" : "Needed", icon: merlotInstalled ? "checkmark.circle" : "arrow.down.circle")
                metricCard(title: "Steam", value: steamInstalled ? "Ready" : "Setup", icon: steamInstalled ? "shippingbox.fill" : "shippingbox")
            }
        }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            actionButton(title: "Launch Steam", subtitle: "Open Steam through the launcher", systemImage: "play.fill", prominent: true) {
                runCommand("./run.command --steam")
            }

            actionButton(title: "Launch Selected Profile", subtitle: selectedProfile?.name ?? "Choose a saved profile first", systemImage: "gamecontroller.fill", prominent: true, disabled: selectedProfile == nil) {
                guard let selectedProfile else { return }
                runCommand("./run.command --game \(shellEscape(selectedProfile.name))")
            }

            actionButton(title: "Install Merlot", subtitle: "Install dependencies and Wine tooling", systemImage: "arrow.down.circle") {
                runCommand("./install_merlot.command")
            }

            actionButton(title: "Open Profiles Folder", subtitle: "Reveal saved .conf profiles in Finder", systemImage: "folder") {
                runCommand("./run.command --profiles")
            }

            actionButton(title: "Refresh Status", subtitle: "Reload profile and install state", systemImage: "arrow.clockwise") {
                refreshStatus(message: "Status refreshed.")
            }

            actionButton(title: "Uninstall", subtitle: "Remove the Cider prefix and app bundle", systemImage: "trash") {
                runCommand("./uninstall.command")
            }
        }
    }

    private func selectedProfileSection(_ profile: SavedProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Selected Profile")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                detailRow(title: "Executable", value: profile.path)
                detailRow(title: "Arguments", value: profile.args.isEmpty ? "None" : profile.args)
                detailRow(title: "Config file", value: profile.fileURL.lastPathComponent)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Launcher Output")
                    .font(.title2.weight(.semibold))
                Spacer()
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ScrollView {
                Text(output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .frame(minHeight: 220)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func metricCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }

    private func actionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        prominent: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(prominent ? Color.white.opacity(0.85) : Color.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .background(prominent ? Color.accentColor : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(disabled || isRunning)
        .opacity((disabled || isRunning) ? 0.6 : 1)
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private func refreshStatus(message: String? = nil) {
        merlotInstalled = fileManager.fileExists(atPath: merlotDirectoryURL.path)
        steamInstalled = fileManager.fileExists(atPath: steamExecutableURL.path)
        profiles = loadProfiles()

        if let selectedProfileID, profiles.contains(where: { $0.id == selectedProfileID }) == false {
            self.selectedProfileID = profiles.first?.id
        }

        if self.selectedProfileID == nil {
            self.selectedProfileID = profiles.first?.id
        }

        if let message {
            output = message + "\n\n" + output
        }
    }

    private func loadProfiles() -> [SavedProfile] {
        let profileURLs = (try? fileManager.contentsOfDirectory(at: profileDirectoryURL, includingPropertiesForKeys: nil)) ?? []

        return profileURLs
            .filter { $0.pathExtension == "conf" }
            .compactMap(loadProfile)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadProfile(from fileURL: URL) -> SavedProfile? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        var name = fileURL.deletingPathExtension().lastPathComponent
        var path = ""
        var args = ""

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false,
                  trimmed.hasPrefix("[") == false,
                  let separatorIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: separatorIndex)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))

            switch key {
            case "name":
                if value.isEmpty == false {
                    name = value
                }
            case "path":
                path = value
            case "args":
                args = value
            default:
                break
            }
        }

        return SavedProfile(id: fileURL.path, name: name, path: path, args: args, fileURL: fileURL)
    }

    private func runCommand(_ command: String) {
        output = "Running: \(command)\n\n"
        isRunning = true

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", command]
        task.currentDirectoryURL = repositoryRootURL
        task.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8), text.isEmpty == false else {
                return
            }

            DispatchQueue.main.async {
                output += text
            }
        }

        task.terminationHandler = { process in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                isRunning = false
                output += process.terminationStatus == 0 ? "\nDone." : "\nExited with status \(process.terminationStatus)."
                refreshStatus()
            }
        }

        do {
            try task.run()
        } catch {
            isRunning = false
            output = "Failed to run command: \(error.localizedDescription)"
        }
    }

    private func shellEscape(_ value: String) -> String {
        guard value.isEmpty == false else { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct SavedProfile: Identifiable {
    let id: String
    let name: String
    let path: String
    let args: String
    let fileURL: URL
}

#Preview {
    ContentView()
}
