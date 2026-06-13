import XCTest
@testable import Cosmos

final class SteamHealthMonitorTests: XCTestCase {
    func testParseSteamHealthLines() {
        let sample = """
        prefix_initialized=1
        steam_installed=1
        mingw_available=0
        webhelper_wrapper=0
        webhelper_wrapper_pending=1
        native_scan_enabled=1
        dual_install_count=2
        dual_install_appids=730,440
        userdata_present=0
        cloud_log_warning=1
        games_installed=3
        games_broken=1
        """
        let status = SteamHealthMonitor.parse(lines: sample)
        XCTAssertTrue(status.prefixInitialized)
        XCTAssertTrue(status.steamInstalled)
        XCTAssertFalse(status.mingwAvailable)
        XCTAssertEqual(status.dualInstallCount, 2)
        XCTAssertEqual(status.dualInstallAppIDs, ["730", "440"])
        XCTAssertFalse(status.userdataPresent)
        XCTAssertTrue(status.cloudLogWarning)
        XCTAssertTrue(status.needsMingwForWrapper)
        XCTAssertFalse(status.needsWrapperInstall)
        XCTAssertTrue(status.hasDualInstallWarning)
        XCTAssertTrue(status.hasCloudWarning)
        XCTAssertEqual(status.gamesInstalled, 3)
        XCTAssertEqual(status.gamesBroken, 1)
        XCTAssertTrue(status.hasBrokenInstalls)
    }

    func testNeedsWrapperInstallWhenMingwPresent() {
        let sample = """
        prefix_initialized=1
        steam_installed=1
        mingw_available=1
        webhelper_wrapper=0
        webhelper_wrapper_pending=1
        """
        let status = SteamHealthMonitor.parse(lines: sample)
        XCTAssertFalse(status.needsMingwForWrapper)
        XCTAssertTrue(status.needsWrapperInstall)
    }
}
