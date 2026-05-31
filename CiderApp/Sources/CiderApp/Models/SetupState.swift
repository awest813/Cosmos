import Foundation

/// Tracks which components are currently installed.
struct SetupState {
    var rosettaInstalled: Bool = false
    var wineInstalled: Bool = false
    var winePrefixReady: Bool = false
    var steamInstalled: Bool = false
    var dxmtInstalled: Bool = false

    /// True when every prerequisite is in place and Steam can be launched.
    var isReady: Bool {
        rosettaInstalled && wineInstalled && winePrefixReady && steamInstalled && dxmtInstalled
    }
}

extension SetupState {
    /// Detect current state by checking well-known paths.
    static func detect(
        wineVersion: String = CiderEngine.defaultWineVersion,
        winePrefix: String = CiderEngine.defaultWinePrefix,
        dxmtRoot: String = CiderEngine.defaultDXMTRoot
    ) -> SetupState {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let wineRoot = "\(home)/wine-\(wineVersion)"
        let wineBin = "\(wineRoot)/Wine Devel.app/Contents/Resources/wine/bin/wine"
        let prefixReg = "\(winePrefix)/system.reg"
        let steam32 = "\(winePrefix)/drive_c/Program Files (x86)/Steam/steam.exe"
        let steam64 = "\(winePrefix)/drive_c/Program Files/Steam/steam.exe"
        let dxmt386 = "\(dxmtRoot)/i386-windows"
        let dxmt64w = "\(dxmtRoot)/x86_64-windows"
        let dxmt64u = "\(dxmtRoot)/x86_64-unix"

        // Rosetta: try running arch -x86_64 true
        let rosetta = Self.checkRosetta()

        return SetupState(
            rosettaInstalled: rosetta,
            wineInstalled: fm.isExecutableFile(atPath: wineBin),
            winePrefixReady: fm.fileExists(atPath: prefixReg),
            steamInstalled: fm.fileExists(atPath: steam32) || fm.fileExists(atPath: steam64),
            dxmtInstalled: fm.fileExists(atPath: dxmt386)
                && fm.fileExists(atPath: dxmt64w)
                && fm.fileExists(atPath: dxmt64u)
        )
    }

    private static func checkRosetta() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        proc.arguments = ["-x86_64", "/usr/bin/true"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}
