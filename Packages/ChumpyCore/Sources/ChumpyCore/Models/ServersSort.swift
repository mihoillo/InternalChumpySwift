import Foundation

/// The servers list's own order, the header's chip picks it. The pinned rows keep
/// the ground floor under every mode — the pin is the list's law, not a mode's
/// suggestion; whatever the mode, it only orders what stands above the pins'
/// floor. The default is the panel's own birthday order. Ported from the
/// Android client's `ServersSort`.
public enum ServersSort: String, CaseIterable, Codable, Identifiable {
    /// The panel's own order, position within the subscription.
    case `default`
    /// By name, case folded.
    case name
    /// By the last real ping; never-measured and unreachable rows share the bottom.
    case ping
    /// By the last pick as the connect's profile, the freshest hand first.
    case lastUsed

    public var id: String { rawValue }

    /// The string table key for the mode's own name — the chip wears it.
    public var localizationKey: String {
        switch self {
        case .default: return "servers.sort.default"
        case .name: return "servers.sort.name"
        case .ping: return "servers.sort.ping"
        case .lastUsed: return "servers.sort.lastUsed"
        }
    }

    /// The mode's whole law in one ordering test: pins first, then the mode's
    /// own key, then the panel's own order as the tiebreak so no two rows ever
    /// trade places over a coin flip. Ported from `ServersSort.comparator()`.
    public func isOrdered(_ lhs: Profile, before rhs: Profile) -> Bool {
        if lhs.pinned != rhs.pinned { return lhs.pinned }
        switch self {
        case .default:
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.remarks < rhs.remarks
        case .name:
            let a = lhs.remarks.lowercased()
            let b = rhs.remarks.lowercased()
            if a != b { return a < b }
            return lhs.order < rhs.order
        case .ping:
            let a = lhs.testDelayMillis ?? Int64.max
            let b = rhs.testDelayMillis ?? Int64.max
            if a != b { return a < b }
            return lhs.order < rhs.order
        case .lastUsed:
            let a = lhs.lastUsedAt?.timeIntervalSince1970 ?? Double(Int64.min)
            let b = rhs.lastUsedAt?.timeIntervalSince1970 ?? Double(Int64.min)
            if a != b { return a > b }
            return lhs.order < rhs.order
        }
    }
}
