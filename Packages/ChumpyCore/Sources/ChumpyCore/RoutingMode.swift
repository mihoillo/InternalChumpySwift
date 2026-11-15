import Foundation

/// Routing modes, ported from the Android client (`XrayConfigBuilder.RoutingMode`).
public enum RoutingMode: String, CaseIterable, Codable, Identifiable {

    case global
    case ru
    case cn
    case ir
    case af
    case id
    case tr
    case br

    public var id: String { rawValue }

    /// Key used to localize the display name (en: "Global" / "Bypass Russia" …).
    public var localizationKey: String {
        switch self {
        case .global: return "routing.global"
        case .ru: return "routing.ru"
        case .cn: return "routing.cn"
        case .ir: return "routing.ir"
        case .af: return "routing.af"
        case .id: return "routing.id"
        case .tr: return "routing.tr"
        case .br: return "routing.br"
        }
    }

    /// `geosite:` categories routed directly (bypassed) in this mode.
    public var bypassGeosites: [String] {
        switch self {
        case .global: return []
        case .ru: return ["category-ru"]
        case .cn: return ["cn"]
        case .ir: return ["category-ir"]
        case .af: return ["category-af"]
        case .id: return ["category-id"]
        case .tr: return ["category-tr"]
        case .br: return ["category-br"]
        }
    }

    /// TLD domains routed directly (bypassed) in this mode.
    public var bypassTlds: [String] {
        switch self {
        case .global: return []
        case .ru: return ["ru", "su", "рф"]
        case .cn: return ["cn"]
        case .ir: return ["ir"]
        case .af: return ["af"]
        case .id: return ["id"]
        case .tr: return ["tr"]
        case .br: return ["br"]
        }
    }

    /// `geoip:` categories routed directly (bypassed) in this mode.
    public var bypassGeoips: [String] {
        switch self {
        case .global: return []
        case .ru: return ["ru"]
        case .cn: return ["cn"]
        case .ir: return ["ir"]
        case .af: return ["af"]
        case .id: return ["id"]
        case .tr: return ["tr"]
        case .br: return ["br"]
        }
    }
}
