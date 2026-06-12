import AppKit
import SwiftUI

/// Pending store-import action shown in a SwiftUI sheet instead of NSAlert.
struct StoreImportRequest: Identifiable {
    enum FieldKind {
        case path
        case displayName
        case epicAppName
        case battlenetSlug
    }

    struct Field: Identifiable {
        let id: FieldKind
        let label: String
        let placeholder: String
        var allowsFilePicker: Bool = false
    }

    let id = UUID()
    let title: String
    let message: String
    let fields: [Field]
    let submitLabel: String
    let script: String
    let baseArguments: [String]
    let forceTerminal: Bool
}

struct StoreImportSheet: View {
    let request: StoreImportRequest
    var onCancel: () -> Void
    /// Return `nil` to close the sheet, or an error message to show inline.
    var onSubmit: (_ values: [StoreImportRequest.FieldKind: String]) -> String?

    @State private var values: [StoreImportRequest.FieldKind: String] = [:]
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @FocusState private var focusedField: StoreImportRequest.FieldKind?

    private var canSubmit: Bool {
        request.fields.allSatisfy { field in
            !(values[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
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
                    tint: .red,
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
                            if field.allowsFilePicker {
                                Button("Choose…") {
                                    pickFile(for: field.id)
                                }
                                .accessibilityLabel("Choose \(field.label)")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

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
                    if let submitError = onSubmit(values) {
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
        .frame(width: 460)
        .background(Color.cosmosContentBackground)
        .onAppear {
            focusedField = request.fields.first?.id
        }
    }

    private func binding(for kind: StoreImportRequest.FieldKind) -> Binding<String> {
        Binding(
            get: { values[kind] ?? "" },
            set: { values[kind] = $0 }
        )
    }

    private func pickFile(for kind: StoreImportRequest.FieldKind) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = (kind == .path && request.baseArguments.contains("add-itch"))
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        values[kind] = url.path
    }
}
