import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InstallationWizardView: View {
    let bottles: [Bottle]
    let busy: Bool
    let hostIssue: String?
    let requirements: String
    let onCancel: () -> Void
    let onSubmit: (InstallationWizardDraft, @escaping (String?) -> Void) -> Void
    @State private var draft: InstallationWizardDraft
    @State private var step: InstallationWizardStep
    @State private var preview: InstallationDestinationPreview?
    @State private var checking = false
    @State private var submitting = false
    @State private var issue: String?
    @State private var checkToken = UUID()

    init(request: InstallationWizardRequest, bottles: [Bottle], busy: Bool, hostIssue: String?, requirements: String,
         initialStep: InstallationWizardStep = .source, initialPreview: InstallationDestinationPreview? = nil,
         onCancel: @escaping () -> Void, onSubmit: @escaping (InstallationWizardDraft, @escaping (String?) -> Void) -> Void) {
        self.bottles = bottles; self.busy = busy; self.hostIssue = hostIssue; self.requirements = requirements
        self.onCancel = onCancel; self.onSubmit = onSubmit
        _draft = State(initialValue: InstallationWizardDraft(request: request))
        _step = State(initialValue: initialStep); _preview = State(initialValue: initialPreview)
    }
    private var blocked: Bool { busy || checking || submitting }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(draft.request.resuming ? "Finish Game Installation" : "Install Windows Game").font(.title.bold())
            HStack(spacing: 14) {
                ForEach(InstallationWizardStep.allCases, id: \.rawValue) { item in
                    Label(item.title, systemImage: item.rawValue < step.rawValue ? "checkmark.circle.fill" : "\(item.rawValue + 1).circle")
                        .font(.caption.weight(item == step ? .bold : .regular))
                        .foregroundStyle(item == step ? Color.primary : Color.secondary)
                        .accessibilityLabel("Step \(item.rawValue + 1): \(item.title)\(item == step ? ", current" : "")")
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stepContent
                    if let message = issue ?? hostIssue {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }.disabled(checking || submitting)
            Divider()
            HStack {
                if checking || submitting { ProgressView().controlSize(.small); Text(submitting ? "Opening Terminal…" : "Checking files and drive mappings…").font(.caption) }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction).disabled(submitting)
                if step != .source {
                    Button("Back") { issue = nil; step = InstallationWizardStep(rawValue: step.rawValue - 1)! }.disabled(blocked)
                }
                Button(step == .review ? (draft.request.resuming ? "Continue in Terminal" : "Start Setup in Terminal") : "Next") { advance() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(blocked || hostIssue != nil || (step == .review && preview == nil))
            }
        }.padding(24).frame(width: 620, height: 570)
        .onDisappear { checkToken = UUID() }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .source:
            Text(draft.request.resuming ? "Select the installed game" : "Choose your game installer").font(.headline)
            TextField("Game title", text: $draft.title).textFieldStyle(.roundedBorder)
                .disabled(draft.request.installation != nil).accessibilityLabel("Game title")
            if draft.request.installation != nil { Text("The saved title identifies this installation. Rename the game after registration.").font(.caption).foregroundStyle(.secondary) }
            if draft.request.resuming {
                pathField("Installed game EXE (optional)", text: $draft.gameExecutable, kind: "game")
                Text("Leave this blank to choose from detected game EXEs after continuing. Setup will not run again.").foregroundStyle(.secondary)
            } else {
                pathField("Installer EXE or MSI", text: $draft.installer, kind: "installer")
                Text("Choose setup, not the installed game. Keep any companion BIN files beside the installer.").foregroundStyle(.secondary)
            }
        case .destination:
            Text("Where should this game live?").font(.headline)
            if let installation = draft.request.installation {
                LabeledContent("Saved environment", value: installation.bottle)
            } else {
                Picker("Windows environment", selection: $draft.existingEnvironment) {
                    Text(draft.request.resuming ? "Use the game's default environment" : "New dedicated environment").tag("")
                    ForEach(bottles.filter { $0.prefixArch == "wow64" }) { Text($0.name).tag($0.name) }
                }
                if draft.existingEnvironment.isEmpty {
                    TextField("Environment name (optional)", text: $draft.newEnvironmentName).textFieldStyle(.roundedBorder)
                }
            }
            LabeledContent("Environment", value: draft.environmentName)
            pathField(draft.request.resuming ? "Moved installation folder (optional)" : "Installation folder (optional)", text: $draft.folder, kind: "folder")
            Text(draft.request.resuming
                 ? "Leave the folder blank to reuse the saved destination and its disconnected-drive check. Choose a folder only if you intentionally relocated the game."
                 : "Leave blank for a Games folder inside this environment. You can also enter a mapped Windows path such as C:\\Games\\SimCity. The next step checks its actual Windows destination.")
                .foregroundStyle(.secondary)
            if !draft.existingEnvironment.isEmpty && draft.request.installation == nil {
                Text("Games in this environment share Windows settings and dependencies.").font(.caption).foregroundStyle(.secondary)
            }
        case .requirements:
            Text("Check the destination and requirements").font(.headline)
            destinationSummary
            Text(requirements).foregroundStyle(.secondary)
            Text("Baseline: WoW64, Windows 10, Retina off, WineD3D. WineD3D does not require Spock or DXMT. A valid EXE header does not establish game compatibility.")
            if !draft.request.resuming {
                Text("Setup stays interactive. Select the Windows destination shown above inside the Windows installer. Cosmos does not guess unattended installer arguments.")
            }
        case .review:
            Text(draft.effectiveTitle).font(.title2.bold())
            LabeledContent("Action", value: draft.request.resuming ? "Select/register game; skip setup" : "Run installer, then choose installed game")
            if !draft.request.resuming { LabeledContent("Installer") { Text(draft.installer).textSelection(.enabled) } }
            if !draft.gameExecutable.isEmpty { LabeledContent("Game EXE") { Text(draft.gameExecutable).textSelection(.enabled) } }
            LabeledContent("Environment", value: draft.environmentName)
            destinationSummary
            Toggle("Create a Mac app shortcut", isOn: $draft.makeMacApp)
            Toggle("Launch game after registration", isOn: $draft.launchAfterInstall)
            Text("Terminal runs the guided setup and game chooser. Finish and close the Windows installer before selecting the installed game EXE. Closing this sheet before starting runs nothing.")
                .foregroundStyle(.secondary)
            Text("Once started, closing the Cosmos window does not cancel setup. Keep Cosmos open to track the result. If EXE selection is interrupted, return to Installations to continue.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var destinationSummary: some View {
        if let preview {
            LabeledContent("Mac folder") { Text(preview.hostFolder.path).textSelection(.enabled) }
            LabeledContent("Windows destination") { Text(preview.windowsFolder).textSelection(.enabled).fontWeight(.semibold) }
            Button("Copy Windows Destination") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(preview.windowsFolder, forType: .string)
            }
            if preview.assumedMappings {
                Text("This environment is not initialized yet. The destination uses Wine's default drive mappings; Terminal checks the actual mappings again before setup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func pathField(_ label: String, text: Binding<String>, kind: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.medium))
            HStack {
                TextField(label, text: text).textFieldStyle(.roundedBorder).labelsHidden()
                Button("Choose…") { choose(kind: kind) }
            }
        }
    }
    private func choose(kind: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = kind == "folder"; panel.canChooseFiles = kind != "folder"
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = kind == "folder"
        if kind != "folder" { panel.allowedContentTypes = (kind == "installer" ? ["exe", "msi"] : ["exe"]).compactMap { UTType(filenameExtension: $0) } }
        panel.begin { response in
            guard response == .OK, let path = panel.url?.path else { return }
            if kind == "folder" { draft.folder = path }
            else if kind == "game" { draft.gameExecutable = path }
            else { draft.installer = path }
        }
    }
    private func advance() {
        issue = nil
        if step == .source || step == .destination {
            let captured = draft
            let token = UUID(); checkToken = token; checking = true
            let sourceStep = step == .source
            DispatchQueue.global(qos: .userInitiated).async {
                let validation = sourceStep ? captured.sourceIssue() : captured.destinationIssue(bottles: bottles)
                var result: InstallationDestinationPreview?
                var failure = validation
                if !sourceStep && failure == nil {
                    do { result = try captured.previewDestination() } catch { failure = error.localizedDescription }
                }
                DispatchQueue.main.async {
                    guard checkToken == token else { return }
                    checking = false
                    if let failure { issue = failure; return }
                    if sourceStep { step = .destination }
                    else { preview = result; step = .requirements }
                }
            }
        } else if step == .requirements { step = .review }
        else {
            guard let failure = hostIssue else {
                submitting = true
                onSubmit(draft) { error in
                    submitting = false
                    if let error { issue = error } else { onCancel() }
                }
                return
            }
            issue = failure
        }
    }
}
