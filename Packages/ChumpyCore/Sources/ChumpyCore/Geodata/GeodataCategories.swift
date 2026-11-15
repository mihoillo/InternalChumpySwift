import Foundation

/// Errors of the geodata container walk.
public enum GeodataContainerError: Error, LocalizedError {
    case truncated
    case invalidVarint
    case invalidContainer
    case invalidField
    case invalidWireType
    case invalidCategory
    case missingCategory
    case tooManyCategories
    case sizeLimit
    case empty

    public var errorDescription: String? {
        switch self {
        case .truncated: return "Truncated geodata"
        case .invalidVarint: return "Invalid varint"
        case .invalidContainer: return "Invalid geodata container"
        case .invalidField: return "Invalid geodata field"
        case .invalidWireType: return "Invalid geodata wire type"
        case .invalidCategory: return "Invalid category"
        case .missingCategory: return "Missing geodata category"
        case .tooManyCategories: return "Too many geodata categories"
        case .sizeLimit: return "Geodata size limit"
        case .empty: return "Empty geodata"
        }
    }
}

/// Reads the category names out of a geodata database — the
/// `geosite.dat`/`geoip.dat` container format: a length-delimited stream of
/// `GeoSiteList` entries, each a protobuf message whose field 1 is the
/// category name. Ported from the Android client's `GeodataFiles.categories`.
public enum GeodataCategories {

    /// No real database comes close; a hostile one does not get to OOM.
    public static let maxEntries = 100_000

    /// The byte budget of the whole walk — one entry and the total both.
    public static let maxBytes = 64 * 1024 * 1024

    public static func categories(of data: Data) throws -> Set<String> {
        let bytes = [UInt8](data)
        var index = 0
        var total = 0
        var entries = 0
        var result = Set<String>()

        func readVarint(eofAllowed: Bool = false) throws -> Int64? {
            var value: Int64 = 0
            for shift in Swift.stride(from: 0, through: 63, by: 7) {
                guard index < bytes.count else {
                    if shift == 0 && eofAllowed { return nil }
                    throw GeodataContainerError.truncated
                }
                let next = bytes[index]
                index += 1
                if shift == 63 && next > 1 { throw GeodataContainerError.invalidVarint }
                value |= Int64(next & 0x7F) << shift
                if next & 0x80 == 0 {
                    guard value >= 0 else { throw GeodataContainerError.invalidVarint }
                    return value
                }
            }
            throw GeodataContainerError.invalidVarint
        }

        while true {
            guard let tag = try readVarint(eofAllowed: true) else { break }
            entries += 1
            guard entries <= maxEntries else { throw GeodataContainerError.tooManyCategories }
            guard tag == 10 else { throw GeodataContainerError.invalidContainer }
            guard let length = try readVarint() else { throw GeodataContainerError.truncated }
            guard length >= 1, length <= Int64(maxBytes),
                  total + Int(length) <= maxBytes
            else { throw GeodataContainerError.sizeLimit }
            total += Int(length)

            let entryEnd = index + Int(length)
            guard entryEnd <= bytes.count else { throw GeodataContainerError.truncated }

            var name: String?
            while index < entryEnd {
                guard let field = try readVarint() else { throw GeodataContainerError.truncated }
                guard field >> 3 > 0 else { throw GeodataContainerError.invalidField }
                switch field & 7 {
                case 0:
                    _ = try readVarint()
                case 1:
                    index += 8
                    guard index <= entryEnd else { throw GeodataContainerError.truncated }
                case 2:
                    guard let size = try readVarint() else { throw GeodataContainerError.truncated }
                    guard size >= 0, index + Int(size) <= entryEnd
                    else { throw GeodataContainerError.truncated }
                    if field >> 3 == 1 {
                        guard size >= 1, size <= 256 else {
                            throw GeodataContainerError.invalidCategory
                        }
                        let raw = bytes[index..<(index + Int(size))]
                        name = String(decoding: raw, as: UTF8.self).uppercased()
                    }
                    index += Int(size)
                case 5:
                    index += 4
                    guard index <= entryEnd else { throw GeodataContainerError.truncated }
                default:
                    throw GeodataContainerError.invalidWireType
                }
            }

            guard let parsed = name,
                  !parsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw GeodataContainerError.missingCategory }
            result.insert(parsed)
        }
        guard !result.isEmpty else { throw GeodataContainerError.empty }
        return result
    }

    /// The categories of a database file on disk; nil when unreadable or
    /// invalid — the caller treats that as "nothing available".
    public static func categories(ofFile url: URL) -> Set<String>? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? categories(of: data)
    }
}
