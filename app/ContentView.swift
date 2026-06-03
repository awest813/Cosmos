import Foundation
import SwiftUI

struct ContentView: View {
    private let fileManager = FileManager.default
    private let repositoryRootURL = Self.findRepositoryRoot()
    private let profileDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cosmos/Profiles", isDirectory: true)
    private let cosmosAppsURL = URL(fileURLWithPath: "/Applications/Cosmos Apps", isDirectory: true)
    private let steamExecutableURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".wine-steam-11/drive_c/Program Files (x86)/Steam/steam.exe")
    private let consoleBottomID = "console-bottom"

    @State private var output = "Welcome to Cosmos\n\nSelect a saved profile or use the quick actions to manage your setup."
    @State private var profiles: [SavedProfile] = []
    @State private var selectedProfileID: String?
    @State private var cosmosInstalled = false
    @State private var steamInstalled = false
    @State private var isRunning = false
    @State private var showResetConfirmation = false
    @State private var showUninstallConfirmation = false

    private var selectedProfile: SavedProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .frame(minWidth: 270)
        } detail: {
            detailContent
        }
        .tint(Color.cosmosPrimary)
        .task {
            refreshStatus()
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(alignment: .center, spacing: 0) {
            // Logo header
            VStack(spacing: 10) {
                CosmosLogoMark(size: 64)
                Text("Cosmos")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.cosmosPrimary)
                Text("Apple Silicon Launcher")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)

            Divider()

            // Status summary
            statusSummary
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Divider()
                .padding(.top, 14)

            // Profile list
            List(selection: $selectedProfileID) {
                Section("Saved Profiles") {
                    if profiles.isEmpty {
                        Label("No profiles yet", systemImage: "tray")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                            .accessibilityLabel("No saved game profiles available")
                    } else {
                        ForEach(profiles) { profile in
                            profileRow(profile)
                                .tag(profile.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func profileRow(_ profile: SavedProfile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(profile.name)
                .font(.headline)
            Text(profile.args.isEmpty ? profile.path : profile.args)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                heroSection
                launchSection
                managementGrid
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

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedProfile?.name ?? "Launcher Dashboard")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.cosmosPrimary)
            Text(selectedProfile == nil
                 ? "Manage Cosmos, launch Steam, and jump into saved game profiles from one place."
                 : "Ready to launch this saved profile through the Wine-based shell flow.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Quick launch

    private var launchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Quick Launch", systemImage: "bolt.fill")

            HStack(spacing: 14) {
                prominentButton(
                    title: "Launch Steam",
                    subtitle: "Open Steam in the bottle",
                    systemImage: "play.fill"
                ) {
                    runCommand(script: "run.command", arguments: ["--steam"])
                }

                prominentButton(
                    title: "Launch Profile",
                    subtitle: selectedProfileLaunchSubtitle,
                    systemImage: "gamecontroller.fill",
                    disabled: !selectedProfileHasExecutablePath
                ) {
                    guard let selectedProfile else { return }
                    runCommand(
                        script: "run.command",
                        arguments: ["--game", selectedProfile.path] + shellArguments(from: selectedProfile.args)
                    )
                }
            }
        }
    }

    // MARK: - Management grid

    private var managementGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Setup & Maintenance", systemImage: "wrench.and.screwdriver.fill")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                secondaryButton(title: "Install Cosmos", subtitle: "Wine & deps · Terminal", systemImage: "arrow.down.circle.fill") {
                    runInTerminal(script: "install_cosmos.command")
                }

                secondaryButton(title: "Detect Games", subtitle: "List Steam games", systemImage: "magnifyingglass") {
                    runCommand(script: "detect_steam_games.command", arguments: ["--list"])
                }

                secondaryButton(title: "Build Launchers", subtitle: "Detect → build apps · Terminal", systemImage: "square.grid.2x2.fill") {
                    runInTerminal(script: "detect_steam_games.command", arguments: ["--install"])
                }

                secondaryButton(title: "Profiles Folder", subtitle: "Open in Finder", systemImage: "folder.fill") {
                    runCommand(script: "run.command", arguments: ["--profiles"])
                }

                secondaryButton(title: "Open Logs", subtitle: "Latest launch log", systemImage: "doc.text.magnifyingglass") {
                    runCommand(script: "run.command", arguments: ["--logs"])
                }

                secondaryButton(title: "Refresh", subtitle: "Reload status", systemImage: "arrow.clockwise") {
                    refreshStatus(message: "Status refreshed.")
                }

                secondaryButton(title: "Reset Bottle", subtitle: "Delete prefix", systemImage: "arrow.counterclockwise", destructive: true) {
                    showResetConfirmation = true
                }

                secondaryButton(title: "Uninstall", subtitle: "Remove everything · Terminal", systemImage: "trash.fill", destructive: true) {
                    showUninstallConfirmation = true
                }
            }
        }
        .confirmationDialog("Reset the Steam bottle?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset Bottle", role: .destructive) {
                runCommand(script: "run.command", arguments: ["--reset-bottle", "--force"])
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the Wine prefix and everything installed inside it (including Steam and games). Wine and DXMT downloads are kept.")
        }
        .confirmationDialog("Uninstall Cosmos?", isPresented: $showUninstallConfirmation, titleVisibility: .visible) {
            Button("Uninstall in Terminal", role: .destructive) {
                runInTerminal(script: "uninstall.command")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Opens Terminal to remove the installed Cosmos apps, the Wine prefix, and the downloaded Wine and DXMT runtimes. The uninstaller asks before deleting each item.")
        }
    }

    private func selectedProfileSection(_ profile: SavedProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Selected Profile", systemImage: "gamecontroller.fill")

            VStack(alignment: .leading, spacing: 14) {
                detailRow(title: "Executable", value: profile.path)
                Divider()
                detailRow(title: "Arguments", value: profile.args.isEmpty ? "None" : profile.args)
                Divider()
                detailRow(title: "Config file", value: profile.fileURL.lastPathComponent)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cosmosPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.cosmosPrimary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private var selectedProfileLaunchSubtitle: String {
        guard let selectedProfile else { return "Select a profile first" }
        return selectedProfileHasExecutablePath ? "Ready to launch" : "Set an executable path"
    }

    private var selectedProfileHasExecutablePath: Bool {
        selectedProfile?.path.isEmpty == false
    }

    // MARK: - Console

    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                sectionHeader("Launcher Output", systemImage: "terminal.fill")
                if isRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.cosmosPrimary)
                        Text("Running…")
                            .font(.caption)
                            .foregroundStyle(Color.cosmosPrimary)
                    }
                }
                Spacer()
                Button {
                    output = ""
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(output.isEmpty || isRunning)
                .help("Clear the output")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(output)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .foregroundStyle(Color(red: 0.85, green: 0.80, blue: 1.0))
                        // Anchor the auto-scroll to the end of the output so the
                        // newest lines stay visible while a command streams.
                        Color.clear
                            .frame(height: 1)
                            .id(consoleBottomID)
                    }
                    .padding(16)
                }
                .frame(minHeight: 220)
                .background(Color(red: 0.07, green: 0.03, blue: 0.16), in: RoundedRectangle(cornerRadius: 16))
                .onChange(of: output) { _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(consoleBottomID, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Reusable components

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow(
                label: cosmosInstalled ? "Cosmos installed" : "Cosmos required",
                icon: cosmosInstalled ? "checkmark.circle.fill" : "arrow.down.circle",
                color: cosmosInstalled ? Color.green : Color.orange
            )
            statusRow(
                label: steamInstalled ? "Steam ready" : "Steam not installed",
                icon: steamInstalled ? "shippingbox.fill" : "shippingbox",
                color: steamInstalled ? Color.cosmosBright : Color.secondary
            )
            statusRow(
                label: "\(profiles.count) profile\(profiles.count == 1 ? "" : "s") saved",
                icon: "gamecontroller.fill",
                color: Color.cosmosPrimary.opacity(0.8)
            )
        }
        .font(.subheadline)
    }

    private func statusRow(label: String, icon: String, color: Color) -> some View {
        Label(label, systemImage: icon)
            .foregroundStyle(color)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.cosmosPrimary)
    }

    private func prominentButton(
        title: String,
        subtitle: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .opacity(0.85)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.cosmosBright, Color.cosmosPrimary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .shadow(color: Color.cosmosPrimary.opacity(0.4), radius: 8, y: 4)
            .hoverBrighten()
        }
        .buttonStyle(CosmosButtonStyle())
        .disabled(disabled || isRunning)
        .opacity((disabled || isRunning) ? 0.55 : 1)
    }

    private func secondaryButton(
        title: String,
        subtitle: String,
        systemImage: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(destructive ? Color.red.opacity(0.8) : Color.cosmosPrimary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        destructive ? Color.red.opacity(0.2) : Color.cosmosPrimary.opacity(0.12),
                        lineWidth: 1
                    )
            )
            .hoverBrighten()
        }
        .buttonStyle(CosmosButtonStyle())
        .disabled(isRunning)
        .opacity(isRunning ? 0.55 : 1)
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.cosmosPrimary.opacity(0.7))
                .textCase(.uppercase)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private func refreshStatus(message: String? = nil) {
        cosmosInstalled = fileManager.fileExists(atPath: cosmosAppsURL.path)
        steamInstalled = fileManager.fileExists(atPath: steamExecutableURL.path)
        profiles = loadProfiles()

        if !profiles.contains(where: { $0.id == selectedProfileID }) {
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
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("["),
                  let separatorIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: separatorIndex)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))

            switch key {
            case "name":
                if !value.isEmpty {
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

        return SavedProfile(id: fileURL.lastPathComponent, name: name, path: path, args: args, fileURL: fileURL)
    }

    // Pure helper for splitting the profile args field; edge cases can be unit-tested independently of the launcher and this only targets trusted local profile text.
    private func shellArguments(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        // This splitter only handles simple quoted groups; backslashes stay literal, unclosed quotes stay literal, and trailing whitespace is ignored.
        enum QuoteState {
            case none
            case single
            case double
        }

        let whitespaceCharacters = CharacterSet.whitespacesAndNewlines
        var state: QuoteState = .none
        var current = ""
        var result: [String] = []

        for character in text {
            switch character {
            case "'" where state == .none:
                state = .single
            case "'" where state == .single:
                state = .none
            case "\"" where state == .none:
                state = .double
            case "\"" where state == .double:
                state = .none
            default:
                if state == .none, character.unicodeScalars.allSatisfy({ whitespaceCharacters.contains($0) }) {
                    if !current.isEmpty {
                        result.append(current)
                        current = ""
                    }
                } else {
                    current.append(character)
                }
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }

    // Locate a helper script, preferring a copy bundled into the app's
    // Resources (installed Cosmos.app) and falling back to the repository
    // checkout (running from a development build).
    private func resolveScript(_ script: String) -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent(script)
            if fileManager.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }
        if let repositoryRootURL {
            let dev = repositoryRootURL.appendingPathComponent(script)
            if fileManager.isExecutableFile(atPath: dev.path) {
                return dev
            }
        }
        return nil
    }

    // Run a helper in Terminal.app instead of the embedded console. Use this for
    // actions that need a real TTY — `sudo` password entry and interactive
    // confirmations — which the piped Process runner cannot provide. We launch it
    // and return; completion happens in Terminal, so the user taps Refresh after.
    private func runInTerminal(script: String, arguments: [String] = []) {
        guard let scriptURL = resolveScript(script) else {
            output = "Script not found or not executable: \(script)"
            return
        }

        let shellCommand = ([scriptURL.path] + arguments)
            .map(Self.shellQuote)
            .joined(separator: " ")

        let appleScript = """
        tell application "Terminal"
            activate
            do script "\(Self.appleScriptEscape(shellCommand))"
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", appleScript]

        do {
            try task.run()
            let displayed = ([script] + arguments).joined(separator: " ")
            output = """
            Opened Terminal to run: \(displayed)

            Complete any password or confirmation prompts in the Terminal window, \
            then press Refresh here to update the status.
            """
        } catch {
            output = "Failed to open Terminal: \(error.localizedDescription)"
        }
    }

    // Wrap a value in single quotes for safe use as one shell word.
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // Escape a value for embedding inside an AppleScript double-quoted string.
    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runCommand(script: String, arguments: [String] = [], environment: [String: String] = [:]) {
        guard let scriptURL = resolveScript(script) else {
            output = "Script not found or not executable: \(script)"
            return
        }

        let displayedCommand = ([script] + arguments).joined(separator: " ")
        output = "Running: \(displayedCommand)\n\n"
        isRunning = true

        let task = Process()
        task.executableURL = scriptURL
        task.arguments = arguments
        task.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        var mergedEnvironment = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        task.environment = mergedEnvironment

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                return
            }

            DispatchQueue.main.async {
                output += text
                // Keep the buffer bounded: detached launches (e.g. Steam) can
                // stream logs indefinitely, which would otherwise grow memory and
                // stall the text view.
                if output.count > 120_000 {
                    output = "…(earlier output trimmed)…\n" + String(output.suffix(100_000))
                }
            }
        }

        task.terminationHandler = { process in
            pipe.fileHandleForReading.readabilityHandler = nil
            // Drain anything written between the last readability callback and exit
            // so a script's final lines are not truncated from the output pane.
            let tail = pipe.fileHandleForReading.readDataToEndOfFile()
            let tailText = String(data: tail, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                if !tailText.isEmpty {
                    output += tailText
                }
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

    private static func findRepositoryRoot() -> URL? {
        let fileManager = FileManager.default
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        while candidate.path != "/" {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("run.command").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        if fileManager.fileExists(atPath: currentDirectory.appendingPathComponent("run.command").path) {
            return currentDirectory
        }

        return nil
    }

}

private struct SavedProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let args: String
    let fileURL: URL
}

// MARK: - Interaction styling

/// Press feedback for the dashboard's custom buttons, which would otherwise be
/// inert under `.buttonStyle(.plain)`.
private struct CosmosButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Subtle brighten-on-hover for pointer feedback on macOS.
private struct HoverBrighten: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .brightness(isHovering ? 0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

private extension View {
    func hoverBrighten() -> some View { modifier(HoverBrighten()) }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif
