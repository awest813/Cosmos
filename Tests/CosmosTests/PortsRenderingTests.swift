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
            let settings = [
                "PORT_NAME": "A Very Long Classic Windows Game Title — Complete Edition",
                "PORT_EXE": "/Users/you/Games/Classic Windows Game/game.exe",
                "PORT_PROGRAM_ARCH": "win32", "PORT_PRIMARY": "spockd3d9",
                "PORT_RENDER_DXMT": "1", "PORT_RENDER_D9VK": "1",
                "PORT_RENDER_CNC_DDRAW": "1", "PORT_RENDER_WINED3D": "1"
            ]
            let port = WinePort(id: "classic-game", settings: settings, directory: directory)
            for scheme in [ColorScheme.light, .dark] {
                let dashboard = PortsDashboard(
                    ports: [port], bottleNames: ["Classic Games"], isRunning: false,
                    onOpenDownloads: {}, onInstall: {}, onResumeInstall: {},
                    onUpdate: { _, _, done in done(nil) }, onOpenLogs: { _ in }, onCreate: { _, done in done(nil) },
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
