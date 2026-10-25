import XCTest
@testable import Cosmos

final class WinePortTests: XCTestCase {
    func testPortHostRequirements() {
        func version(_ major: Int, _ minor: Int) -> OperatingSystemVersion {
            OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
        }
        XCTAssertNotNil(PortHostSupport.unavailableReason(architecture: "x86_64", version: version(26, 0)))
        XCTAssertNotNil(PortHostSupport.unavailableReason(architecture: "arm64", version: version(13, 6)))
        XCTAssertNotNil(PortHostSupport.unavailableReason(architecture: "arm64", version: version(14, 5)))
        XCTAssertNil(PortHostSupport.unavailableReason(architecture: "arm64", version: version(14, 6)))
        XCTAssertNil(PortHostSupport.unavailableReason(architecture: "arm64", version: version(26, 0)))
    }

    func testDetectsWindowsExecutableArchitectureWithoutLaunching() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Game With Spaces.exe")
        var bytes = [UInt8](repeating: 0, count: 256)
        bytes[0] = 0x4d; bytes[1] = 0x5a; bytes[60] = 128
        bytes[128] = 0x50; bytes[129] = 0x45
        bytes[132] = 0x4c; bytes[133] = 0x01
        try Data(bytes).write(to: url)
        XCTAssertEqual(WindowsProgramArchitecture.detect(at: url), .win32)
        bytes[132] = 0x64; bytes[133] = 0x86
        try Data(bytes).write(to: url)
        XCTAssertEqual(WindowsProgramArchitecture.detect(at: url), .win64)
        bytes[151] = 0x20 // DLL flag: not a program.
        try Data(bytes).write(to: url)
        XCTAssertNil(WindowsProgramArchitecture.detect(at: url))
        try Data([0x4d, 0x5a]).write(to: url)
        XCTAssertNil(WindowsProgramArchitecture.detect(at: url))
        XCTAssertNil(WindowsProgramArchitecture.detect(at: root.appendingPathComponent("missing.exe")))
    }

    func testDefaultStackMatchesSikarugirAppleSiliconDefaults() throws {
        let backend = PortStack.resolve(.appleSiliconDefaults, distribution: "personal")
        XCTAssertEqual(try backend.get(), "spockd3d9")
    }

    func testDxmtWithoutD9vkStaysOnDxmt() throws {
        var renderers = PortRenderers.appleSiliconDefaults
        renderers.d9vk = false
        XCTAssertEqual(try PortStack.resolve(renderers, distribution: "personal").get(), "dxmt")
    }

    func testPersonalD3DMetalWins() throws {
        var renderers = PortRenderers.appleSiliconDefaults
        renderers.d3dmetal = true
        XCTAssertEqual(try PortStack.resolve(renderers, distribution: "personal").get(), "d3dmetal")
    }

    func testSharedD3DMetalIsRefused() {
        var renderers = PortRenderers.appleSiliconDefaults
        renderers.d3dmetal = true
        let result = PortStack.resolve(renderers, distribution: "share")
        guard case .failure(let error) = result else {
            return XCTFail("expected shared D3DMetal to fail")
        }
        XCTAssertEqual(error, .sharedD3DMetal)
        XCTAssertTrue(error.message.contains("D3DMetal"))
    }

    func testDxvkOnly() throws {
        let renderers = PortRenderers(dxmt: false, d3dmetal: false, dxvk: true, d9vk: false, cncDDraw: false, wineD3D: false)
        XCTAssertEqual(try PortStack.resolve(renderers, distribution: "personal").get(), "dxvk")
    }

    func testD9vkOnlyUsesSpock() throws {
        let renderers = PortRenderers(dxmt: false, d3dmetal: false, dxvk: false, d9vk: true, cncDDraw: false, wineD3D: false)
        XCTAssertEqual(try PortStack.resolve(renderers, distribution: "share").get(), "spockd3d9")
    }

    func testClassicRenderersFallBackToWineD3D() throws {
        let renderers = PortRenderers(dxmt: false, d3dmetal: false, dxvk: false, d9vk: false, cncDDraw: true, wineD3D: false)
        XCTAssertEqual(try PortStack.resolve(renderers, distribution: "personal").get(), "wined3d")
    }

    func testNoRendererFails() {
        let renderers = PortRenderers(dxmt: false, d3dmetal: false, dxvk: false, d9vk: false, cncDDraw: false, wineD3D: false)
        XCTAssertEqual(PortStack.resolve(renderers, distribution: "personal"), .failure(.noRenderer))
    }

    func testSpockOnlyDescriptionDoesNotClaimDxmtOrFallback() {
        var renderers = PortRenderers.appleSiliconDefaults
        renderers.dxmt = false
        renderers.wineD3D = false
        let summary = PortStack.launchSummary(renderers, distribution: "personal")
        XCTAssertFalse(summary.contains("DXMT"))
        XCTAssertTrue(summary.contains("fallback is off"))
        renderers.wineD3D = true
        XCTAssertTrue(PortStack.launchSummary(renderers, distribution: "personal").contains("WineD3D handles DirectX 9"))
        let port = WinePort(id: "spock", settings: ["PORT_PRIMARY": "spockd3d9", "PORT_RENDER_D9VK": "1"], directory: URL(fileURLWithPath: "/tmp/spock"))
        XCTAssertEqual(port.graphicsLabel, "SpockD3D9")
    }

    func testCreateArgumentsUseTheAppleSiliconDefaults() {
        var draft = WinePortDraft.empty
        draft.name = "Notepad"
        draft.exe = "/tmp/notepad.exe"
        let args = draft.commandArguments
        XCTAssertEqual(args.prefix(4), ["create", "--name", "Notepad", "--exe"])
        XCTAssertTrue(args.contains("--distribution"))
        XCTAssertTrue(args.contains("personal"))
        XCTAssertTrue(args.contains("--dxmt"))
        XCTAssertEqual(flag(args, "--d3dmetal"), "0")
        XCTAssertEqual(flag(args, "--dxmt"), "1")
        XCTAssertEqual(flag(args, "--d9vk"), "1")
        XCTAssertEqual(flag(args, "--program-arch"), "win64")
        XCTAssertFalse(args.contains("--args"))
        XCTAssertEqual(flag(args, "--cnc-ddraw"), "1")
        XCTAssertFalse(args.contains("--bottle"))
        XCTAssertFalse(args.contains("--gptk-path"))
    }

    func testSharedDraftDropsGptkAndRejectsD3DMetal() {
        var draft = WinePortDraft.empty
        draft.name = "Shared"
        draft.exe = "/tmp/game.exe"
        draft.distribution = "share"
        draft.renderers.d3dmetal = true
        draft.gptkPath = "/Users/me/GPTK"
        XCTAssertEqual(draft.validationError, PortStackError.sharedD3DMetalMessage)
        XCTAssertFalse(draft.commandArguments.contains("--gptk-path"))

        draft.renderers.d3dmetal = false
        XCTAssertEqual(
            draft.validationError,
            "A Game Porting Toolkit path is only saved on a personal port."
        )
        XCTAssertFalse(draft.commandArguments.contains("--gptk-path"))
    }

    func testLoadPortConf() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ports-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent("notepad", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let body = """
        PORT_SCHEMA="cosmos-port-v1"
        PORT_NAME="Notepad"
        PORT_SLUG="notepad"
        PORT_EXE="/tmp/notepad.exe"
        PORT_DISTRIBUTION="personal"
        PORT_WINDOWS="win10"
        PORT_PRIMARY="spockd3d9"
        PORT_RENDER_DXMT="1"
        PORT_RENDER_D3DMETAL="0"
        PORT_RENDER_D9VK="1"
        PORT_RENDER_CNC_DDRAW="1"
        PORT_RENDER_WINED3D="1"
        """
        try body.write(to: dir.appendingPathComponent("port.conf"), atomically: true, encoding: .utf8)

        let ports = WinePortStore.load(from: root)
        XCTAssertEqual(ports.map(\.id), ["notepad"])
        XCTAssertEqual(ports.first?.name, "Notepad")
        XCTAssertEqual(ports.first?.primaryBackend, "spockd3d9")
        XCTAssertEqual(ports.first?.renderers, PortRenderers(
            dxmt: true, d3dmetal: false, dxvk: false, d9vk: true, cncDDraw: true, wineD3D: true
        ))
        XCTAssertEqual(ports.first?.cardDetail, "This Mac · Windows 10 · DXMT + SpockD3D9")
        XCTAssertEqual(ports.first?.programArch, "win64")
    }

    func testLaunchArgumentsAnd32BitProgram() {
        var draft = WinePortDraft.empty
        draft.name = "Old Game"
        draft.exe = "/tmp/game.exe"
        draft.arguments = "--windowed"
        draft.programArch = "win32"
        let args = draft.commandArguments
        XCTAssertEqual(flag(args, "--program-arch"), "win32")
        XCTAssertEqual(flag(args, "--args"), "--windowed")
    }

    func testPortsDirectoryMatchesCLIOverrides() {
        let originalSupport = ProcessInfo.processInfo.environment["COSMOS_SUPPORT_DIR"]
        let originalPorts = ProcessInfo.processInfo.environment["COSMOS_PORTS_DIR"]
        defer {
            if let originalSupport { setenv("COSMOS_SUPPORT_DIR", originalSupport, 1) }
            else { unsetenv("COSMOS_SUPPORT_DIR") }
            if let originalPorts { setenv("COSMOS_PORTS_DIR", originalPorts, 1) }
            else { unsetenv("COSMOS_PORTS_DIR") }
        }
        unsetenv("COSMOS_PORTS_DIR")
        setenv("COSMOS_SUPPORT_DIR", "/tmp/cosmos-custom-support", 1)
        XCTAssertEqual(WinePortStore.portsDirectoryURL.path, "/tmp/cosmos-custom-support/Ports")
        setenv("COSMOS_PORTS_DIR", "/tmp/cosmos-custom-ports", 1)
        XCTAssertEqual(WinePortStore.portsDirectoryURL.path, "/tmp/cosmos-custom-ports")
    }

    func testPortOperationLabels() {
        XCTAssertEqual(
            CosmosOperationLabel.title(script: "port.command", arguments: ["launch", "notepad"]),
            "Opening your port…"
        )
        XCTAssertEqual(
            CosmosOperationLabel.title(script: "port.command", arguments: ["build", "notepad"]),
            "Making a Mac app…"
        )
        XCTAssertEqual(
            CosmosOperationLabel.title(script: "port.command", arguments: ["create", "--name", "Notepad"]),
            "Creating a port…"
        )
    }

    private func flag(_ args: [String], _ name: String) -> String? {
        guard let index = args.firstIndex(of: name), args.index(after: index) < args.endIndex else {
            return nil
        }
        return args[args.index(after: index)]
    }
}
