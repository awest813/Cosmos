import SwiftUI

/// Game library: browse, add, edit, and launch game profiles.
struct LibraryView: View {
    @EnvironmentObject private var engine: CiderEngine
    @State private var selectedProfile: GameProfile?
    @State private var showEditor = false
    @State private var editorProfile = GameProfile(slug: "", displayName: "")
    @State private var isNewProfile = false

    var body: some View {
        HSplitView {
            // Profile list
            List(engine.profiles, selection: $selectedProfile) { profile in
                VStack(alignment: .leading) {
                    Text(profile.displayName)
                        .font(.headline)
                    if !profile.steamGameID.isEmpty {
                        Text("App ID: \(profile.steamGameID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(profile)
                .contextMenu {
                    Button("Edit…") { beginEdit(profile) }
                    Button("Delete", role: .destructive) { delete(profile) }
                }
            }
            .frame(minWidth: 180)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isNewProfile = true
                        editorProfile = GameProfile(slug: "", displayName: "")
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }

            // Detail
            if let profile = selectedProfile {
                ProfileDetailView(profile: profile) {
                    beginEdit(profile)
                } onLaunch: {
                    Task { await engine.launchSteam(profile: profile) }
                }
            } else {
                Text("Select a game from the sidebar, or click + to add one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showEditor) {
            ProfileEditorSheet(
                profile: $editorProfile,
                isNew: isNewProfile
            ) { saved in
                do {
                    try engine.saveProfile(saved)
                    selectedProfile = saved
                } catch {
                    engine.lastError = error.localizedDescription
                }
            }
        }
    }

    private func beginEdit(_ profile: GameProfile) {
        isNewProfile = false
        editorProfile = profile
        showEditor = true
    }

    private func delete(_ profile: GameProfile) {
        do {
            try engine.deleteProfile(profile)
            if selectedProfile == profile { selectedProfile = nil }
        } catch {
            engine.lastError = error.localizedDescription
        }
    }
}

// MARK: - Detail view

private struct ProfileDetailView: View {
    let profile: GameProfile
    let onEdit: () -> Void
    let onLaunch: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(profile.displayName)
                    .font(.largeTitle.bold())

                GroupBox {
                    LabeledContent("Steam App ID", value: profile.steamGameID.isEmpty ? "—" : profile.steamGameID)
                    LabeledContent("Backend", value: profile.backend.uppercased())
                    LabeledContent("Retina", value: profile.retina ? "On" : "Off")
                    LabeledContent("Mouse Warp", value: profile.mouseWarp.isEmpty ? "Default" : profile.mouseWarp)
                }

                if !profile.envOverrides.isEmpty {
                    GroupBox("Environment Overrides") {
                        VStack(alignment: .leading) {
                            ForEach(profile.envOverrides, id: \.self) { line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }

                if !profile.notes.isEmpty {
                    GroupBox("Notes") {
                        Text(profile.notes)
                    }
                }

                HStack {
                    Button("Launch") { onLaunch() }
                        .buttonStyle(.borderedProminent)
                    Button("Edit…") { onEdit() }
                }
            }
            .padding()
        }
    }
}

// MARK: - Editor sheet

private struct ProfileEditorSheet: View {
    @Binding var profile: GameProfile
    let isNew: Bool
    let onSave: (GameProfile) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var slug = ""
    @State private var displayName = ""
    @State private var steamGameID = ""
    @State private var backend = "dxmt"
    @State private var retina = false
    @State private var mouseWarp = ""
    @State private var envText = ""
    @State private var notes = ""

    private let backends = ["dxmt", "gptk"]
    private let mouseWarpOptions = ["", "force", "enable", "disable"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if isNew {
                    TextField("Slug (url-safe ID)", text: $slug)
                }
                TextField("Display Name", text: $displayName)
                TextField("Steam App ID", text: $steamGameID)
                Picker("Backend", selection: $backend) {
                    ForEach(backends, id: \.self) { Text($0.uppercased()) }
                }
                Toggle("Retina Mode", isOn: $retina)
                Picker("Mouse Warp", selection: $mouseWarp) {
                    Text("Default").tag("")
                    Text("Force").tag("force")
                    Text("Enable").tag("enable")
                    Text("Disable").tag("disable")
                }
                TextField("Env Overrides (one KEY=VAL per line)", text: $envText, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(computedSlug.isEmpty || displayName.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 380)
        .onAppear {
            slug = profile.slug
            displayName = profile.displayName
            steamGameID = profile.steamGameID
            backend = profile.backend
            retina = profile.retina
            mouseWarp = profile.mouseWarp
            envText = profile.envOverrides.joined(separator: "\n")
            notes = profile.notes
        }
    }

    private var computedSlug: String {
        isNew ? slug : profile.slug
    }

    private func save() {
        let saved = GameProfile(
            slug: computedSlug,
            displayName: displayName,
            steamGameID: steamGameID,
            backend: backend,
            retina: retina,
            mouseWarp: mouseWarp,
            envOverrides: envText.components(separatedBy: "\n").filter { !$0.isEmpty },
            notes: notes
        )
        onSave(saved)
        dismiss()
    }
}
