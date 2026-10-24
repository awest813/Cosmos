import XCTest
@testable import Cosmos

final class WinePortTests: XCTestCase {
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
