import XCTest
@testable import ChumpyCore

/// The geodata container walk: the shipped databases' categories, the
/// hand-crafted containers, and the format's own guards. Ported from the
/// Android client's `GeodataFiles.categories` semantics.
final class GeodataCategoriesTests: XCTestCase {

    // MARK: - Fixtures

    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(
                forResource: name, withExtension: "dat"
            )
            ?? Bundle.module.url(
                forResource: name, withExtension: "dat", subdirectory: "Geodata"
            )
        return try Data(contentsOf: XCTUnwrap(url))
    }

    // MARK: - Container crafting

    private func varint(_ value: Int) -> [UInt8] {
        var remaining = UInt64(value)
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            out.append(byte)
        } while remaining != 0
        return out
    }

    /// A minimal container: entries whose only field is the category name.
    private func container(_ names: [String]) -> Data {
        var data = Data()
        for name in names {
            var entry = Data([0x0A])
            entry.append(contentsOf: varint(name.utf8.count))
            entry.append(contentsOf: Array(name.utf8))
            data.append(0x0A)
            data.append(contentsOf: varint(entry.count))
            data.append(entry)
        }
        return data
    }

    // MARK: - The shipped databases

    func testBundledGeositeCategories() throws {
        let categories = try GeodataCategories.categories(of: fixture("geosite"))
        XCTAssertEqual(
            ["CATEGORY-IR", "CATEGORY-RU", "CN", "PRIVATE"],
            categories.sorted()
        )
    }

    func testBundledGeoipCategories() throws {
        let categories = try GeodataCategories.categories(of: fixture("geoip"))
        XCTAssertEqual(
            ["AF", "BR", "CN", "ID", "IR", "PRIVATE", "RU", "TR"],
            categories.sorted()
        )
    }

    // MARK: - Hand-crafted containers

    func testNamesAreUppercased() throws {
        let categories = try GeodataCategories.categories(
            of: container(["cn", "Ru", "PRIVATE"])
        )
        XCTAssertEqual(["CN", "PRIVATE", "RU"], categories.sorted())
    }

    func testEmptyThrows() {
        XCTAssertThrowsError(
            try GeodataCategories.categories(of: Data())
        ) { error in
            XCTAssertEqual(GeodataContainerError.empty, error as? GeodataContainerError)
        }
    }

    func testTruncatedContainerThrows() {
        // An entry announcing more bytes than the container holds.
        var data = Data([0x0A, 0x10, 0x0A, 0x02, 0x52, 0x55])
        XCTAssertThrowsError(try GeodataCategories.categories(of: data))
        data = Data([0x0A])
        XCTAssertThrowsError(try GeodataCategories.categories(of: data))
    }

    func testInvalidContainerTagThrows() {
        // Field 2 as the container tag instead of the field-1 entry.
        XCTAssertThrowsError(
            try GeodataCategories.categories(of: Data([0x12, 0x00]))
        )
    }

    func testInvalidWireTypeThrows() {
        // Wire type 3 (start group) inside an entry.
        XCTAssertThrowsError(
            try GeodataCategories.categories(of: Data([0x0A, 0x02, 0x0B, 0x00]))
        )
    }

    func testMissingCategoryThrows() {
        // An entry whose field 1 never comes.
        XCTAssertThrowsError(
            try GeodataCategories.categories(of: Data([0x0A, 0x03, 0x10, 0x01, 0x00]))
        )
    }

    func testOversizedCategoryThrows() {
        // A category name beyond the 256-byte cap.
        var entry = Data([0x0A])
        entry.append(contentsOf: varint(300))
        entry.append(contentsOf: [UInt8](repeating: 0x61, count: 300))
        var data = Data([0x0A])
        data.append(contentsOf: varint(entry.count))
        data.append(entry)
        XCTAssertThrowsError(try GeodataCategories.categories(of: data))
    }

    func testTooManyEntriesThrow() {
        // One entry more than the cap — the walk must stop, not hang.
        var data = Data()
        let entry = container(["A"])
        for _ in 0...(GeodataCategories.maxEntries) {
            data.append(entry)
        }
        XCTAssertThrowsError(try GeodataCategories.categories(of: data))
    }

    func testSizeLimitThrows() {
        // An entry claiming the whole budget and then some.
        var data = Data([0x0A])
        data.append(contentsOf: varint(GeodataCategories.maxBytes + 1))
        XCTAssertThrowsError(try GeodataCategories.categories(of: data))
    }

    func testJunkFileYieldsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("junk-\(UUID().uuidString).dat")
        try Data([0xFF, 0xFF, 0xFF]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(GeodataCategories.categories(ofFile: url))
    }

    func testExtraFieldsDoNotBreakTheWalk() throws {
        // Field 2 (string), field 3 (varint), field 4 (fixed64), field 5
        // (fixed32) — decoration around the name the walk is after.
        var entry = Data()
        entry.append(contentsOf: [0x12, 0x03] + Array("zzz".utf8))           // field 2
        entry.append(contentsOf: [0x18, 0x2A])                                // field 3
        entry.append(contentsOf: [0x21] + [UInt8](repeating: 0, count: 8))    // field 4, fixed64
        entry.append(contentsOf: [0x2D] + [UInt8](repeating: 0, count: 4))    // field 5, fixed32
        entry.append(contentsOf: [0x0A, 0x02, 0x52, 0x55])                    // field 1
        var data = Data([0x0A])
        data.append(contentsOf: varint(entry.count))
        data.append(entry)
        XCTAssertEqual(["RU"], try GeodataCategories.categories(of: data))
    }
}
