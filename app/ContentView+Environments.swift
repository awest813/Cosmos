import AppKit
import SwiftUI

extension ContentView {
    var workspaceModalPresented: Bool {
        installationWizard != nil || workspaceAddingExecutable || workspaceEditingPort != nil ||
            storeImportRequest != nil || showNewBottleSheet || showDownloads || showAddGameProfileSheet ||
            workspaceEnvironmentSettings != nil || workspaceEnvironmentConfirmation != nil || workspaceEnvironmentTools != nil
    }
    var workspaceEnvironments: [WorkspaceEnvironment] {
        WorkspaceEnvironment.catalog(bottles: bottles, ports: ports, main: steamSettings, mainInitialized: steamSettings.isPrefixInitialized)
    }
    var workspaceSelectedEnvironment: WorkspaceEnvironment? {
        workspaceEnvironments.first { $0.key == workspaceEnvironmentID }
    }
    func workspaceEnvironmentReason(_ action: WorkspaceEnvironmentAction) -> String? {
        WorkspaceEnvironmentContext(selected: workspaceDestination == .environments && workspaceUtilitySection == nil ? workspaceSelectedEnvironment : nil,
            busy: workspaceBusy || workspaceEnvironmentReading, modalPresented: workspaceModalPresented, installHostIssue: workspacePortHostIssue).disabledReason(action)
    }
    func performWorkspaceEnvironmentAction(_ action: WorkspaceEnvironmentAction) {
        guard workspaceEnvironmentReason(action) == nil, let target = workspaceSelectedEnvironment else { return }
        switch action {
        case .dependencies:
            let root = ProcessInfo.processInfo.environment["WINE_ROOT"].flatMap { $0.isEmpty ? nil : $0 }
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("wine-\(target.wineVersion)").path
            workspaceEnvironmentTools = EnvironmentToolsRequest(environment: target, runtimeRoot: root)
        case .install: installationWizard = InstallationWizardRequest(preferredEnvironment: target.bottle?.name)
        case .clone:
            if let bottle = target.bottle { storeImportRequest = .cloneEnvironment(source: bottle.name) }
        case .stop, .reset, .delete:
            workspaceEnvironmentConfirmation = EnvironmentConfirmation(environment: target, action: action)
        case .settings:
            guard let bottle = target.bottle else { return }
            workspaceEnvironmentReading = true
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { () throws -> EnvironmentSettingsRequest in
                    let data = try Data(contentsOf: bottle.configURL)
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw NSError(domain: "Cosmos.Environment", code: 1, userInfo: [NSLocalizedDescriptionKey: "Settings are not valid UTF-8."])
                    }
                    let fresh = Bottle(id: bottle.id, settings: BottleStore.parseConf(contents: text), prefixURL: bottle.prefixURL,
                        isInitialized: FileManager.default.fileExists(atPath: bottle.prefixURL.appendingPathComponent("system.reg").path), steamInstalled: bottle.steamInstalled)
                    let updated = WorkspaceEnvironment(key: target.key, name: target.name, prefix: target.prefix,
                        wineVersion: fresh.settings["WINE_VERSION"].flatMap { $0.isEmpty ? nil : $0 } ?? "11.8",
                        windowsVersion: fresh.windowsVersion, backend: fresh.backend, requestedArchitecture: fresh.prefixArch,
                        initialized: fresh.isInitialized, assignedGames: target.assignedGames, bottle: fresh)
                    guard let request = EnvironmentSettingsRequest(environment: updated, revision: EnvironmentSettingsDraft.digest(data)) else {
                        throw NSError(domain: "Cosmos.Environment", code: 2)
                    }
                    return request
                }
                DispatchQueue.main.async {
                    workspaceEnvironmentReading = false
                    guard workspaceDestination == .environments, workspaceSelectedEnvironment?.key == target.key else { return }
                    switch result {
                    case .success(let request): workspaceEnvironmentSettings = request
                    case .failure(let error): showBanner(kind: .failure, message: "Could not read environment settings: \(error.localizedDescription)")
                    }
                }
            }
        case .reveal:
            if fileManager.fileExists(atPath: target.prefix.path) { revealInFinder(target.prefix) }
        case .logs: runCommand(script: "run.command", arguments: ["--logs"], environment: target.commandEnvironment)
        case .diagnose: runCommand(script: "repair.command", arguments: ["diagnose"], environment: target.commandEnvironment, intent: .diagnose)
        }
    }
    func runWorkspaceRecipe(_ recipe: EnvironmentRecipe, request: EnvironmentToolsRequest, done: @escaping (String?) -> Void) {
        guard !workspaceBusy, workspacePortHostIssue == nil, recipe.unsupportedReason == nil,
              let current = workspaceEnvironments.first(where: { $0.key == request.environment.key }),
              current.prefix == request.environment.prefix, current.wineVersion == request.environment.wineVersion,
              current.initialized else {
            done("The environment or host is unavailable, changed, or another operation is running. Close and review again."); return
        }
        runCommand(script: "repair.command", arguments: recipe.arguments, environment: request.commandEnvironment,
            onCompletion: { success, message in done(success ? nil : message) })
    }
    func confirmWorkspaceEnvironmentAction(_ pending: EnvironmentConfirmation) {
        workspaceEnvironmentConfirmation = nil
        guard !workspaceBusy, let current = workspaceEnvironments.first(where: { $0.key == pending.environment.key }),
              current.prefix == pending.environment.prefix, current.wineVersion == pending.environment.wineVersion else {
            showBanner(kind: .failure, message: "The environment changed or is unavailable. Review its current state before retrying.")
            return
        }
        if pending.action == .stop {
            runCommand(script: "repair.command", arguments: ["apply-fix", "kill_wine"], environment: pending.environment.commandEnvironment)
        } else if let bottle = pending.environment.bottle, pending.action == .reset || pending.action == .delete {
            runCommand(script: "bottle.command", arguments: [pending.action == .reset ? "reset" : "delete", bottle.name, "--force"])
        }
    }
}
