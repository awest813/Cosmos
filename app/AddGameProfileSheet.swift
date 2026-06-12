import SwiftUI

enum AddGameProfileStore: String, CaseIterable, Identifiable {
    case steam
    case gog

    var id: String { rawValue }

    var label: String {
        switch self {
        case .steam: return "Steam"
        case .gog: return "GOG"
        }
    }
}

struct AddGameProfileSheet: View {
    let repositoryRoot: URL
    var onCancel: () -> Void
    var onSaved: (GameProfile) -> Void

    @State private var store: AddGameProfileStore = .steam
    @State private var steamAppID = ""
    @State private var gogName = ""
    @State private var gogSlug = ""
    @State private var gogExePath = ""
    @State private var previewYAML = ""
    @State private var errorMessage: String?
    @State private var isGenerating = false
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case steamAppID, gogName, gogSlug, gogExePath
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CosmosSpacing.cardPadding) {
                Text("Add Game Profile")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CosmosGradients.heroTitle)

                Text("Create a YAML compatibility recipe in your personal library. Steam drafts use community hints; GOG profiles use a starter template you can edit after saving.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage {
                    CosmosNoticeBanner(
                        tint: .red,
                        systemImage: "exclamationmark.triangle.fill",
                        title: "Could not save profile",
                        message: errorMessage
                    )
                }

                Picker("Store", selection: $store) {
                    ForEach(AddGameProfileStore.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isGenerating || isSaving)
                .accessibilityLabel("Profile store")

                Form {
                    switch store {
                    case .steam:
                        TextField("Steam App ID", text: $steamAppID)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .steamAppID)
                            .disabled(isGenerating || isSaving)
                            .accessibilityLabel("Steam App ID")
                    case .gog:
                        TextField("Display name", text: $gogName)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .gogName)
                            .disabled(isGenerating || isSaving)
                            .accessibilityLabel("GOG display name")
                        TextField("GOG slug", text: $gogSlug)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .gogSlug)
                            .disabled(isGenerating || isSaving)
                            .accessibilityLabel("GOG slug")
                        TextField("Executable path (optional)", text: $gogExePath, prompt: Text("drive_c/GOG Games/Title/game.exe"))
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .gogExePath)
                            .disabled(isGenerating || isSaving)
                            .accessibilityLabel("GOG executable path")
                    }
                }
                .formStyle(.grouped)

                if !previewYAML.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(previewYAML)
                                .font(CosmosTypography.monoBody)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                        .padding(10)
                        .background(Color.cosmosConsoleBackground, in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                HStack {
                    if isGenerating || isSaving {
                        ProgressView()
                            .controlSize(.small)
                        Text(isGenerating ? "Generating draft…" : "Saving profile…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .disabled(isGenerating || isSaving)
                    Button("Generate Draft") {
                        generateDraft()
                    }
                    .disabled(isGenerating || isSaving)
                    Button("Save Profile") {
                        saveProfile()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cosmosPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(previewYAML.isEmpty || isGenerating || isSaving)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(Color.cosmosContentBackground)
        .onAppear {
            focusedField = .steamAppID
        }
        .onChange(of: store) { _ in
            previewYAML = ""
            errorMessage = nil
            focusedField = store == .steam ? .steamAppID : .gogName
        }
    }

    private func generateDraft() {
        errorMessage = nil
        isGenerating = true
        defer { isGenerating = false }
        do {
            switch store {
            case .steam:
                previewYAML = try GameProfileWriter.suggestSteamYAML(
                    appID: steamAppID,
                    repositoryRoot: repositoryRoot
                )
            case .gog:
                previewYAML = try GameProfileWriter.buildGOGYAML(
                    name: gogName,
                    slug: gogSlug,
                    exePath: gogExePath
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveProfile() {
        errorMessage = nil
        if previewYAML.isEmpty {
            generateDraft()
            guard previewYAML.isEmpty == false else { return }
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let filename: String
            switch store {
            case .steam:
                filename = GameProfileWriter.suggestedSteamFilename(appID: steamAppID, yaml: previewYAML)
            case .gog:
                filename = GameProfileWriter.suggestedGOGFilename(slug: gogSlug)
            }
            let savedURL = try GameProfileWriter.saveUserProfile(
                yaml: previewYAML,
                store: store.rawValue,
                suggestedFilename: filename
            )
            guard let profile = GameProfileStore.load().first(where: { $0.fileURL == savedURL }) else {
                throw GameProfileWriterError.writeFailed("Profile saved but could not reload it.")
            }
            onSaved(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
