import XCTest
import Darwin
@testable import Cosmos

final class PortFileCheckTests: XCTestCase {
    func testWindowsJunctionIsFollowedWithoutChangingThePrefix() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let drive = root.appendingPathComponent("drive_c")
        let actual = drive.appendingPathComponent("Versions/One/Game.exe")
        try executable(at: actual, arch: .win32)
        let stub = drive.appendingPathComponent("Current?")
        try FileManager.default.createDirectory(at: stub, withIntermediateDirectories: true)
        let text = Array("\\??\\C:\\Versions\\One".data(using: .utf16LittleEndian)!)
        var bytes: [UInt8] = [3, 0, 0, 160]
        let size = 8 + text.count
        bytes += [UInt8(size & 255), UInt8(size >> 8), 0, 0, 0, 0, UInt8(text.count & 255), UInt8(text.count >> 8), 0, 0, 0, 0]
        bytes += text
        let status = bytes.withUnsafeBytes { buffer in
            setxattr(stub.path, "user.WINEREPARSE", buffer.baseAddress, buffer.count, 0, 0)
        }
        guard status == 0 else { throw XCTSkip("Fixture volume does not support Wine reparse xattrs") }
        let before = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
        let port = WinePort(id: "junction", settings: settings("drive_c/Current/Game.exe"), directory: root)
        let check = PortFileCheck.inspect(port, mainPrefix: root)
        XCTAssertEqual(check.gameURL?.resolvingSymlinksInPath().path, actual.resolvingSymlinksInPath().path)
        XCTAssertEqual(check.findings.first { $0.id == "executable" }?.passed, true)
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: drive.appendingPathComponent("Current").path))
    }

    private func executable(at url: URL, arch: WindowsProgramArchitecture) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var bytes = [UInt8](repeating: 0, count: 256)
        bytes[0] = 0x4d; bytes[1] = 0x5a; bytes[60] = 128
        bytes[128] = 0x50; bytes[129] = 0x45
        bytes[132] = arch == .win32 ? 0x4c : 0x64
        bytes[133] = arch == .win32 ? 0x01 : 0x86
        try Data(bytes).write(to: url)
    }

    private func settings(_ exe: String, bottle: String = "", arch: String = "win32") -> [String: String] {
        ["PORT_EXE": exe, "PORT_BOTTLE": bottle, "PORT_PROGRAM_ARCH": arch,
         "PORT_PRIMARY": "wined3d", "PORT_RENDER_WINED3D": "1"]
    }

    func testValidX86FilesDoNotBecomeAGameplayClaimOrWriteData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = root.appendingPathComponent("prefix")
        try executable(at: prefix.appendingPathComponent("drive_c/Game/SC3U.exe"), arch: .win32)
        let registry = prefix.appendingPathComponent("system.reg")
        let original = "WINE REGISTRY Version 2\n#arch=win64\n"
        try original.write(to: registry, atomically: true, encoding: .utf8)
        let before = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
        let port = WinePort(id: "simcity", settings: settings("drive_c/Game/SC3U.exe"), directory: root)
        let check = PortFileCheck.inspect(port, mainPrefix: prefix, bottlesDirectory: root.appendingPathComponent("unused"))
        XCTAssertTrue(check.findings.allSatisfy(\.passed), check.report(for: port))
        XCTAssertEqual(check.gameURL?.path, prefix.appendingPathComponent("drive_c/Game/SC3U.exe").path)
        XCTAssertTrue(check.report(for: port).contains("gameplay NOT TESTED"))
        XCTAssertTrue(check.report(for: port).contains("WoW64 support"))
        XCTAssertEqual(try String(contentsOf: registry), original)
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted(), before)
    }

    func testArchitectureMismatchAndWin32PrefixAreActionable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let exe = root.appendingPathComponent("drive_c/Game/game.exe")
        try executable(at: exe, arch: .win64)
        try "WINE REGISTRY Version 2\n#arch=win32\n".write(to: root.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
        let port = WinePort(id: "wrong", settings: settings(exe.path), directory: root)
        let check = PortFileCheck.inspect(port, mainPrefix: root)
        XCTAssertEqual(check.findings.first { $0.id == "architecture" }?.passed, false)
        XCTAssertEqual(check.findings.first { $0.id == "prefix-architecture" }?.passed, false)
        XCTAssertTrue(check.report(for: port).contains("Edit"))
    }

    func testMissingFilesAndTraversalDoNotCreateAnEnvironment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let port = WinePort(id: "missing", settings: settings("drive_c/../../outside.exe", bottle: "missing"), directory: root)
        let check = PortFileCheck.inspect(port, mainPrefix: root, bottlesDirectory: root)
        XCTAssertNil(check.gameURL)
        XCTAssertEqual(check.findings.first { $0.id == "environment" }?.passed, false)
        XCTAssertEqual(check.findings.first { $0.id == "executable" }?.passed, false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testNamedEnvironmentUsesItsOwnPrefix() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = root.appendingPathComponent("classic")
        let prefix = environment.appendingPathComponent("prefix")
        try executable(at: prefix.appendingPathComponent("drive_c/Game/game.exe"), arch: .win32)
        try "".write(to: environment.appendingPathComponent("bottle.conf"), atomically: true, encoding: .utf8)
        let port = WinePort(id: "classic", settings: settings("drive_c/Game/game.exe", bottle: "classic"), directory: root)
        let check = PortFileCheck.inspect(port, mainPrefix: root.appendingPathComponent("unrelated"), bottlesDirectory: root)
        XCTAssertEqual(check.prefixURL?.path, prefix.path)
        XCTAssertEqual(check.findings.first { $0.id == "environment" }?.passed, true)
        XCTAssertEqual(check.findings.first { $0.id == "executable" }?.passed, true)
        XCTAssertEqual(check.findings.first { $0.id == "prefix" }?.passed, false)
    }
}
