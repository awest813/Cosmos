import AppKit
import SwiftUI
import XCTest
@testable import Cosmos

/// Render the native controls in an isolated window. No Wine, network requests,
/// or user files are involved. CI uploads the PNGs for visual review.
final class PortsRenderingTests: XCTestCase {
    func testPortsNativeLayouts() throws {
        guard let output = ProcessInfo.processInfo.environment["COSMOS_UI_SMOKE_OUTPUT_DIR"] else {
            throw XCTSkip("Set COSMOS_UI_SMOKE_OUTPUT_DIR to capture native UI layouts.")
        }
        try onMain {
            _ = NSApplication.shared
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let installation = PendingGameInstallation(id: "simcity/game", name: "SimCity 3000 Unlimited", slug: "simcity-3000-unlimited", bottle: "game-simcity", folder: "/Games/SimCity", installer: "/Downloads/Setup.exe", stage: "awaiting-game")
            for step in InstallationWizardStep.allCases {
                try capture(
                    InstallationWizardView(request: .init(resuming: true, installation: installation), bottles: [], busy: false,
                        hostIssue: nil, requirements: "Wine is installed. Review any installer and macOS permission prompts.", initialStep: step,
                        initialPreview: .init(hostFolder: URL(fileURLWithPath: "/Games/SimCity"), windowsFolder: "C:\\Games\\SimCity", assumedMappings: false),
                        onCancel: {}, onSubmit: { _, _ in }),
                    name: "installation-wizard-\(step.rawValue)", size: NSSize(width: 620, height: 570),
                    scheme: step == .review ? .dark : .light, directory: directory
                )
            }
            try capture(
                InstallationWizardView(request: .init(), bottles: [], busy: false, hostIssue: nil, requirements: "Wine may download during setup.",
                    onCancel: {}, onSubmit: { _, _ in }), name: "installation-wizard-new", size: NSSize(width: 620, height: 570), scheme: .light, directory: directory
            )
            try capture(
                StoreImportSheet(request: .cloneEnvironment(source: "game-simcity"), onCancel: {}, onSubmit: { _ in nil }),
                name: "clone-environment", size: NSSize(width: 520, height: 400), scheme: .light, directory: directory
            )
            let settings = [
                "PORT_NAME": "A Very Long Classic Windows Game Title — Complete Edition",
                "PORT_EXE": "/Users/you/Games/Classic Windows Game/game.exe",
                "PORT_PROGRAM_ARCH": "win32", "PORT_PRIMARY": "spockd3d9",
                "PORT_RENDER_DXMT": "1", "PORT_RENDER_D9VK": "1",
                "PORT_RENDER_CNC_DDRAW": "1", "PORT_RENDER_WINED3D": "1"
            ]
            let port = WinePort(id: "classic-game", settings: settings, directory: directory)
            let environmentBottle = Bottle(id: "classic-games", settings: ["COSMOS_BACKEND": "wined3d", "COSMOS_PREFIX_ARCH": "wow64", "WINDOWS_VERSION": "win10"],
                prefixURL: directory.appendingPathComponent("fixture-prefix"), isInitialized: true, steamInstalled: false)
            let environmentPort = WinePort(id: port.id, settings: settings.merging(["PORT_BOTTLE": "classic-games"]) { _, value in value }, directory: directory)
            let environmentCatalog = WorkspaceEnvironment.catalog(bottles: [environmentBottle], ports: [environmentPort], main: .defaults, mainInitialized: false)
            for scheme in [ColorScheme.light, .dark] {
                try capture(
                    ScrollView {
                        WorkspaceEnvironmentsView(environments: environmentCatalog, selection: .constant(.named("classic-games")), busy: false,
                            reason: { _ in nil }, perform: { _ in }, onCreate: {}, onOpenGame: { _ in }).padding(24)
                    }, name: "environments-\(scheme == .dark ? "dark" : "light")", size: NSSize(width: 800, height: 680), scheme: scheme, directory: directory
                )
            }
            try capture(
                WorkspaceEnvironmentsView(environments: environmentCatalog, selection: .constant(.named("removed")), busy: false,
                    reason: { _ in "Unavailable" }, perform: { _ in }, onCreate: {}, onOpenGame: { _ in }).padding(24),
                name: "environment-unavailable", size: NSSize(width: 800, height: 500), scheme: .light, directory: directory
            )
            let environmentRequest = try XCTUnwrap(EnvironmentSettingsRequest(environment: environmentCatalog[1], revision: String(repeating: "a", count: 64)))
            let recipeFixture = try XCTUnwrap(EnvironmentRecipe.parse(data: Data("# Source: Highball DB (CC0-1.0); upstream requirements need separate review.\nTYPE=dependency\nID=xact\nDESCRIPTION=XAudio 2.7 / XACT for older 32-bit games\nWINETRICKS=xact\n".utf8), fileID: "xact", kind: .dependency))
            for scheme in [ColorScheme.light, .dark] {
                try capture(
                    EnvironmentToolsView(request: EnvironmentToolsRequest(environment: environmentCatalog[1], runtimeRoot: "/Fixture/wine-11.8"), busy: false,
                        hostIssue: nil, initialRecipes: [recipeFixture], onClose: {}, onRun: { _, _ in }),
                    name: "environment-dependencies-\(scheme == .dark ? "dark" : "light")", size: NSSize(width: 760, height: 620), scheme: scheme, directory: directory
                )
            }
            try capture(
                EnvironmentSettingsView(request: environmentRequest, busy: false, onCancel: {}, onSave: { _, _ in }),
                name: "environment-settings", size: NSSize(width: 570, height: 600), scheme: .light, directory: directory
            )
            for scheme in [ColorScheme.light, .dark] {
                try capture(
                    ScrollView {
                        WorkspaceLibraryView(games: [.port(port)], selection: .constant("port:classic-game"), reason: { _ in nil }, perform: { _ in }).padding(24)
                    }, name: "workspace-library-\(scheme == .dark ? "dark" : "light")",
                    size: NSSize(width: 720, height: 640), scheme: scheme, directory: directory
                )
            }
            try capture(
                WorkspaceLibraryView(games: [], selection: .constant(nil), reason: { _ in nil }, perform: { _ in }).padding(24),
                name: "workspace-first-launch", size: NSSize(width: 720, height: 500), scheme: .light, directory: directory
            )
            try capture(
                ScrollView { WineEnvironmentFilesView(layout: WineEnvironmentLayout(prefix: directory.appendingPathComponent("missing-prefix"))).padding(20) },
                name: "windows-environment-files", size: NSSize(width: 560, height: 640), scheme: .light, directory: directory
            )
            let pending = PendingGameInstallation(id: "custom/simcity", name: "SimCity 3000 Unlimited", slug: "simcity", bottle: "custom", folder: "/Users/you/Games/SimCity 3000 Unlimited", installer: "/Users/you/Downloads/Setup.exe", stage: "awaiting-game")
            try capture(
                PendingGameInstallationsView(installations: [pending], isBusy: false, onContinue: { _, _ in }).padding(20),
                name: "unfinished-installations", size: NSSize(width: 520, height: 300), scheme: .light, directory: directory
            )
            for scheme in [ColorScheme.light, .dark] {
                let dashboard = PortsDashboard(
                    ports: [port], bottleNames: ["Classic Games"], isRunning: false,
                    onOpenDownloads: {}, onInstall: {}, onResumeInstall: {},
                    onUpdate: { _, _, done in done(nil) }, onOpenLogs: { _ in }, onDiagnose: { _ in },
                    onStopEnvironment: { _ in }, onCloneEnvironment: { _ in }, onCreate: { _, done in done(nil) },
                    onLaunch: { _ in }, onBuild: { _ in }, onDelete: { _ in }
                )
                try capture(
                    ScrollView { dashboard.padding(20) },
                    name: "ports-\(scheme == .dark ? "dark" : "light")",
                    size: NSSize(width: 640, height: 640), scheme: scheme, directory: directory
                )
            }
            let empty = PortsDashboard(
                ports: [], bottleNames: [], isRunning: false,
                onInstall: {}, onResumeInstall: {}, onCreate: { _, done in done(nil) },
                onLaunch: { _ in }, onBuild: { _ in }, onDelete: { _ in }
            )
            try capture(
                ScrollView { empty.padding(20) }, name: "ports-empty",
                size: NSSize(width: 640, height: 640), scheme: .light, directory: directory
            )
            try capture(
                StoreImportSheet(request: .classicGame(resuming: true), onCancel: {}, onSubmit: { _ in nil }),
                name: "finish-installation", size: NSSize(width: 520, height: 640), scheme: .light, directory: directory
            )
            try capture(
                StoreImportSheet(request: .classicGame(), onCancel: {}, onSubmit: { _ in nil }),
                name: "install-windows-game", size: NSSize(width: 520, height: 640), scheme: .dark, directory: directory
            )
            let unavailable = PortsDashboard(
                ports: [], bottleNames: [], isRunning: false,
                unavailableReason: PortHostSupport.unavailableReason(
                    architecture: "x86_64", version: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
                ),
                onOpenDownloads: {}, onInstall: {}, onResumeInstall: {}, onCreate: { _, done in done(nil) },
                onLaunch: { _ in }, onBuild: { _ in }, onDelete: { _ in }
            )
            try capture(
                unavailable.padding(20), name: "ports-unsupported-host",
                size: NSSize(width: 640, height: 500), scheme: .light, directory: directory
            )
            try capture(
                NewPortSheet(bottleNames: ["Classic Games"], isRunning: false, onCancel: {}, onCreate: { _, done in done(nil) }),
                name: "new-port", size: NSSize(width: 560, height: 640), scheme: .light, directory: directory
            )
            try capture(
                NewPortSheet(bottleNames: [], isRunning: false, initialDraft: WinePortDraft(port: port), isEditing: true, onCancel: {}, onCreate: { _, done in done(nil) }),
                name: "edit-port", size: NSSize(width: 560, height: 640), scheme: .dark, directory: directory
            )
            try capture(
                PortFileCheckView(port: port, check: PortFileCheck.inspect(port, mainPrefix: directory.appendingPathComponent("missing-prefix"), bottlesDirectory: directory)).padding(20),
                name: "port-file-check", size: NSSize(width: 520, height: 400), scheme: .light, directory: directory
            )
        }
    }

    private func onMain(_ body: @MainActor () throws -> Void) throws {
        if Thread.isMainThread { try MainActor.assumeIsolated { try body() } }
        else { try DispatchQueue.main.sync { try MainActor.assumeIsolated { try body() } } }
    }

    @MainActor
    private func capture<Content: View>(
        _ content: Content, name: String, size: NSSize, scheme: ColorScheme, directory: URL
    ) throws {
        let view = NSHostingView(rootView: content.environment(\.colorScheme, scheme))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = view
        window.setContentSize(size)
        window.orderFrontRegardless()
        defer { window.close() }
        // Allow SwiftUI's onAppear/selection and native control layout to settle.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1000, "Native rendering must produce a nonempty image")
        try png.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
