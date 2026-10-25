import AppKit
import SwiftUI

/// Pending store-import action shown in a SwiftUI sheet instead of NSAlert.
struct StoreImportRequest: Identifiable {
    enum FieldKind {
        case path
        case displayName
        case epicAppName
        case battlenetSlug
        case installDirectory
        case gameExecutable
        case makeMacApp
        case launchAfterInstall
    }

    struct Field: Identifiable {
        let id: FieldKind
        let label: String
        let placeholder: String
        var allowsFilePicker: Bool = false
        var isRequired: Bool = true
        var choosesDirectory: Bool = false
        var help: String? = nil
    }

    let id = UUID()
    let title: String
    let message: String
    let fields: [Field]
    let submitLabel: String
    let script: String
    let baseArguments: [String]
    let forceTerminal: Bool

    static func classicGame(resuming: Bool = false) -> StoreImportRequest {
        var fields: [Field] = []
        if !resuming {
            fields.append(.init(id: .path, label: "Installer EXE or MSI", placeholder: "/Users/you/Downloads/setup_game.exe", allowsFilePicker: true))
        }
        fields.append(.init(id: .displayName, label: "Game title", placeholder: "SimCity 3000 Unlimited"))
        fields.append(.init(id: .installDirectory, label: "Installation folder (optional)", placeholder: "Choose in Terminal if left blank", allowsFilePicker: true, isRequired: false, choosesDirectory: true, help: "Use this same destination in the Windows installer. Recovery reuses the saved folder when left blank."))
        if resuming {
            fields.append(.init(id: .gameExecutable, label: "Installed game EXE (optional)", placeholder: "Choose after continuing if left blank", allowsFilePicker: true, isRequired: false))
        }
        return StoreImportRequest(
            title: resuming ? "Finish Game Installation" : "Install Windows Game",
            message: resuming
                ? "Enter the same title used during setup. Terminal reopens the saved installation folder so you can select the installed game EXE. Setup will not run again. Uses the default game environment."
                : "Choose an EXE or MSI installer and enter the game title. Setup runs in a dedicated Windows environment. After setup finishes, select the installed game EXE. WineD3D is the starting graphics setting; you can change it in Edit Port.",
            fields: fields,
            submitLabel: resuming ? "Continue in Terminal" : "Install in Terminal",
            script: "scripts/install_program.command",
            baseArguments: [resuming ? "resume" : "install"],
            forceTerminal: true
        )
    }

    func installerArguments(values: [FieldKind: String]) -> [String] {
        func value(_ kind: FieldKind) -> String { (values[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        var arguments = baseArguments
        if !baseArguments.contains("resume") { arguments.append(value(.path)) }
        arguments += ["--name", value(.displayName)]
        for (kind, flag) in [(FieldKind.installDirectory, "--install-dir"), (.gameExecutable, "--game-exe")] {
            let text = value(kind)
            if !text.isEmpty { arguments += [flag, text] }
        }
        if values[.makeMacApp] == "1" { arguments.append("--make-app") }
        if values[.launchAfterInstall] == "0" { arguments.append("--no-launch") }
        return arguments
    }
}

struct StoreImportSheet: View {
    let request: StoreImportRequest
    var onCancel: () -> Void
    /// Return `nil` to close the sheet, or an error message to show inline.
    var onSubmit: (_ values: [StoreImportRequest.FieldKind: String]) -> String?

    @State private var values: [StoreImportRequest.FieldKind: String] = [:]
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var makeMacApp = false
    @State private var launchAfterInstall = true
    @FocusState private var focusedField: StoreImportRequest.FieldKind?

    private var canSubmit: Bool {
        request.fields.allSatisfy { field in
            !field.isRequired || !(values[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        Group {
            if request.script == "scripts/install_program.command" {
                ScrollView { sheetContents }
                    .frame(width: 520)
                    .frame(maxHeight: 680)
            } else {
                sheetContents.frame(width: 460)
            }
        }
        .background(Color.cosmosContentBackground)
        .onAppear { focusedField = request.fields.first?.id }
    }

    private var sheetContents: some View {
        VStack(alignment: .leading, spacing: CosmosSpacing.cardPadding) {
            Text(request.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(CosmosGradients.heroTitle)

            Text(request.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                CosmosNoticeBanner(
                    tint: Color.cosmosDanger,
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Could not import",
                    message: errorMessage
                )
            }

            Form {
                ForEach(request.fields) { field in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(field.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TextField(field.placeholder, text: binding(for: field.id))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: field.id)
                                .accessibilityLabel(field.label)
                                .disabled(isSubmitting)
                            if field.allowsFilePicker {
                                Button("Choose…") {
                                    pickFile(for: field.id)
                                }
                                .accessibilityLabel("Choose \(field.label)")
                                .disabled(isSubmitting)
                            }
                        }
                        if let help = field.help {
                            Text(help).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isSubmitting)

            if request.script == "scripts/install_program.command" {
                Toggle("Create a Mac app shortcut", isOn: $makeMacApp).disabled(isSubmitting)
                Toggle("Launch game after installation", isOn: $launchAfterInstall).disabled(isSubmitting)
                Text("The shortcut is saved in ~/Applications/Cosmos Ports. Keep companion setup files beside the installer.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Starting import…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSubmitting)
                Button(request.submitLabel) {
                    errorMessage = nil
                    isSubmitting = true
                    if let validationError = StoreImportValidation.validate(request: request, values: values) {
                        errorMessage = validationError
                        isSubmitting = false
                        return
                    }
                    var submittedValues = values
                    submittedValues[.makeMacApp] = makeMacApp ? "1" : "0"
                    submittedValues[.launchAfterInstall] = launchAfterInstall ? "1" : "0"
                    if let submitError = onSubmit(submittedValues) {
                        errorMessage = submitError
                        isSubmitting = false
                        return
                    }
                    onCancel()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.cosmosPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || isSubmitting)
            }
        }
        .padding(20)
    }

    private func binding(for kind: StoreImportRequest.FieldKind) -> Binding<String> {
        Binding(
            get: { values[kind] ?? "" },
            set: { values[kind] = $0 }
        )
    }

    private func pickFile(for kind: StoreImportRequest.FieldKind) {
        let panel = NSOpenPanel()
        let directory = request.fields.first { $0.id == kind }?.choosesDirectory == true
        panel.canChooseFiles = !directory
        if request.script == "scripts/install_program.command", !directory {
            panel.allowedFileTypes = kind == .gameExecutable ? ["exe"] : ["exe", "msi"]
        }
        panel.canChooseDirectories = directory || (kind == .path && request.baseArguments.contains("add-itch"))
        panel.canCreateDirectories = directory
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        values[kind] = url.path
    }
}
