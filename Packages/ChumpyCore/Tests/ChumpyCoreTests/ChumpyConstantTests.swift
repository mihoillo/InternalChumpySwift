import XCTest
@testable import ChumpyCore

final class ChumpyConstantTests: XCTestCase {

    func testSharedDefaultsAreUsable() {
        let defaults = ChumpyConstant.sharedDefaults
        let key = "chumpy.tests.smoke"
        defaults.set("hello", forKey: key)
        XCTAssertEqual(defaults.string(forKey: key), "hello")
        defaults.removeObject(forKey: key)
    }

    func testDirectoriesResolveUnderAppGroupContainer() {
        XCTAssertEqual(
            ChumpyConstant.dataDir.path,
            ChumpyConstant.appGroupContainer
                .appendingPathComponent("Library/Application Support/Xray").path
        )
        XCTAssertEqual(
            ChumpyConstant.tunnelConfigPath.lastPathComponent,
            "config_final.json"
        )
    }

    func testEnsureDirectoriesIsIdempotent() {
        ChumpyConstant.ensureDirectories()
        ChumpyConstant.ensureDirectories()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: ChumpyConstant.configsDir.path)
        )
    }
}
