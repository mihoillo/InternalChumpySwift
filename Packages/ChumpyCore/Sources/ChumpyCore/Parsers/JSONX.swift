import Foundation

/// JSON plumbing shared by the config/subscription parsers: tolerant accessors
/// over `JSONSerialization` values, mirroring the Kotlin JsonPrimitive helpers
/// the Android parsers used (numbers and booleans read as their string form).
public enum JSONX {

    /// String form of a primitive value: String as-is, numbers/bools as text.
    /// Nil for missing keys, objects and arrays.
    public static func str(_ dict: [String: Any]?, _ key: String) -> String? {
        guard let value = dict?[key] else { return nil }
        return strValue(value)
    }

    public static func strValue(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue ? "true" : "false"
            }
            return n.stringValue
        case let b as Bool:
            return b ? "true" : "false"
        default:
            return nil
        }
    }

    /// Int from a primitive's string form (Kotlin `str(key)?.toIntOrNull()`).
    public static func int(_ dict: [String: Any]?, _ key: String) -> Int? {
        guard let s = str(dict, key) else { return nil }
        return Int(s.trimmingCharacters(in: .whitespaces))
    }

    public static func obj(_ dict: [String: Any]?, _ key: String) -> [String: Any]? {
        dict?[key] as? [String: Any]
    }

    public static func array(_ dict: [String: Any]?, _ key: String) -> [Any]? {
        dict?[key] as? [Any]
    }

    public static func arrayOfObjects(_ array: [Any]?) -> [[String: Any]] {
        (array ?? []).compactMap { $0 as? [String: Any] }
    }

    public static func strings(_ array: [Any]?) -> [String] {
        (array ?? []).compactMap { strValue($0) }
    }

    /// Case-insensitive string lookup (panels spell keys both ways).
    public static func stringIgnoreCase(_ dict: [String: Any], _ key: String) -> String? {
        for (k, value) in dict {
            if k.caseInsensitiveCompare(key) == .orderedSame,
               let s = value as? String {
                return s
            }
        }
        return nil
    }

    /// Serializes any JSON-compatible value to a compact JSON string.
    public static func toJSONString(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
