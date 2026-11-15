import Foundation

/// The Clash YAML subscription dialect: a `proxies:` list of proxy maps, the
/// format panels serve to Clash-flavoured clients. Supported inline rules are
/// converted to Xray rules. Ported from the Android client's `ClashYamlParser`.
public enum ClashYamlParser {

    /// The profiles found in the `proxies:` list, deduplicated; nil when it is
    /// not this dialect.
    public static func parse(_ body: String) -> [Profile]? {
        guard body.range(of: "(?m)^proxies:", options: .regularExpression) != nil else {
            return nil
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let noBOM = trimmed.hasPrefix("\u{FEFF}")
            ? String(trimmed.dropFirst("\u{FEFF}".count)) : trimmed
        guard let root = (try? MiniYaml.parse(noBOM)) as? [String: Any?] else { return nil }
        guard let proxies = root["proxies"] as? [Any?] else { return nil }

        var profiles: [Profile] = []
        for entry in proxies {
            guard let proxy = entry as? [String: Any?], let profile = proxyToProfile(proxy) else {
                continue
            }
            profiles.append(profile)
        }
        guard !profiles.isEmpty else { return nil }

        let names = Set(profiles.map(\.remarks))
        let rules = ClashRouting.parse(root, proxyNames: names)
        var seen = Set<String>()
        var result: [Profile] = []
        for profile in profiles {
            if seen.insert(profile.computeLinkKey()).inserted {
                var p = profile
                p.routingRules = rules
                result.append(p)
            }
        }
        return result
    }

    /// One clash proxy map as a profile draft; nil when its endpoint does not
    /// hold together.
    private static func proxyToProfile(_ proxy: [String: Any?]) -> Profile? {
        let type: ProfileType
        switch proxy["type"] as? String {
        case "vless": type = .vless
        case "vmess": type = .vmess
        case "trojan": type = .trojan
        case "ss", "shadowsocks": type = .shadowsocks
        case "socks5", "socks": type = .socks
        case "hysteria2", "hy2": type = .hysteria2
        default: return nil
        }
        guard let server = proxy["server"] as? String,
              let port = (proxy["port"] as? String).flatMap(Int.init)
        else { return nil }
        guard !server.trimmingCharacters(in: .whitespaces).isEmpty, (1...65535).contains(port) else {
            return nil
        }

        var profile = Profile(type: type)
        profile.remarks = (proxy["name"] as? String) ?? ""
        profile.server = server
        profile.serverPort = port

        switch type {
        case .vless:
            guard let uuid = proxy["uuid"] as? String else { return nil }
            profile.password = uuid
            profile.method = "none"
            profile.flow = (proxy["flow"] as? String) ?? ""

        case .vmess:
            guard let uuid = proxy["uuid"] as? String else { return nil }
            profile.password = uuid
            profile.method = (proxy["cipher"] as? String) ?? "auto"

        case .trojan:
            guard let password = proxy["password"] as? String else { return nil }
            profile.password = password

        case .shadowsocks:
            profile.method = (proxy["cipher"] as? String) ?? ""
            profile.password = (proxy["password"] as? String) ?? ""

        case .socks:
            profile.username = (proxy["username"] as? String) ?? ""
            profile.password = (proxy["password"] as? String) ?? ""

        case .hysteria2:
            guard let password = proxy["password"] as? String else { return nil }
            profile.password = password
            profile.obfsPassword = (proxy["obfs-password"] as? String) ?? ""
            profile.portHopping = (proxy["ports"] as? String) ?? ""
            profile.portHoppingInterval = (proxy["hop-interval"] as? String) ?? ""

        default:
            return nil
        }

        let reality = proxy["reality-opts"] as? [String: Any?]
        if type == .hysteria2 {
            profile.network = "hysteria"
        } else {
            switch proxy["network"] as? String {
            case "ws", "websocket", "grpc", "httpupgrade", "kcp", "mkcp":
                profile.network = proxy["network"] as? String ?? "tcp"
            case "h2", "http":
                profile.network = "http"
            default:
                profile.network = "tcp"
            }
        }
        if reality != nil {
            profile.security = "reality"
        } else if type == .hysteria2 || type == .trojan {
            profile.security = "tls"
        } else if (proxy["tls"] as? String) == "true" {
            profile.security = "tls"
        } else {
            profile.security = ""
        }
        profile.sni = (proxy["servername"] as? String) ?? (proxy["sni"] as? String) ?? ""
        profile.fingerprint = (proxy["client-fingerprint"] as? String) ?? ""
        if let alpn = proxy["alpn"] as? [Any?] {
            profile.alpn = alpn.map { stringify($0) }.joined(separator: ",")
        } else {
            profile.alpn = ""
        }
        profile.allowInsecure = (proxy["skip-cert-verify"] as? String) == "true"
        profile.publicKey = (reality?["public-key"] as? String) ?? ""
        profile.shortID = (reality?["short-id"] as? String) ?? ""

        switch profile.network {
        case "ws", "websocket":
            if let ws = proxy["ws-opts"] as? [String: Any?] {
                profile.path = (ws["path"] as? String) ?? ""
                profile.host = hostOf(ws["headers"])
            }
        case "grpc":
            if let grpc = proxy["grpc-opts"] as? [String: Any?] {
                profile.serviceName = (grpc["grpc-service-name"] as? String) ?? ""
            }
        default:
            break
        }
        return profile
    }

    private static func stringify(_ value: Any?) -> String {
        value.map { "\($0)" } ?? ""
    }

    /// The Host header, which clash writes as a scalar, a list or a one-key map.
    private static func hostOf(_ headers: Any?) -> String {
        switch headers {
        case nil:
            return ""
        case let map as [String: Any?]:
            let inner = map["Host"] ?? map["host"]
            guard let value = inner else { return "" }
            return hostOf(value)
        case let list as [Any?]:
            return list.map { stringify($0) }.joined(separator: ",")
        case let scalar as String:
            return scalar
        default:
            return headers.map { "\($0)" } ?? ""
        }
    }
}

/// The inline `rules:` list of a Clash config, converted to the Xray rule shape
/// the builder carries. Ported from the Android client's `ClashRouting`.
enum ClashRouting {

    private static let domainPattern = "^[A-Za-z0-9_.-]+$"
    private static let siteCodePattern = "^[A-Za-z0-9_-]+(@[A-Za-z0-9_-]+)?$"
    private static let portPattern = "^[0-9]{1,5}(-[0-9]{1,5})?$"

    static func parse(_ config: [String: Any?], proxyNames: Set<String>) -> String {
        if let mode = config["mode"] as? String, mode.lowercased() != "rule" { return "" }
        guard let entries = config["rules"] as? [Any?] else { return "" }
        var groups = Set<String>()
        for group in (config["proxy-groups"] as? [Any?]) ?? [] {
            if let name = (group as? [String: Any?])?["name"] as? String {
                groups.insert(name)
            }
        }
        var proxyTargets = proxyNames
        proxyTargets.formUnion(groups)
        proxyTargets.insert("PROXY")

        var rules: [[String: Any]] = []
        ruleLoop: for entry in entries {
            guard let entryString = entry as? String else { break }
            let parts = entryString.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard let first = parts.first else { break }
            let type = first.uppercased()
            if type == "PROCESS-NAME" { continue }
            let catchAll = type == "MATCH"
            let targetIndex = catchAll ? 1 : 2
            guard targetIndex < parts.count else { break }
            let target = parts[targetIndex]
            let outbound: String
            switch target {
            case "DIRECT": outbound = "direct"
            case "REJECT", "REJECT-DROP": outbound = "block"
            default:
                guard proxyTargets.contains(target) else { break ruleLoop }
                outbound = "proxy"
            }
            let expected = catchAll ? 2 : 3
            if parts.count != expected {
                let ipPort = type == "IP-CIDR" || type == "IP-CIDR6" || type == "GEOIP"
                guard ipPort, parts.count == expected + 1, parts.last == "no-resolve" else {
                    break ruleLoop
                }
            }

            // A later rule must not overtake an unsupported earlier rule.
            guard let (field, value) = matcher(type, catchAll ? "" : parts[1]) else { break }
            var rule: [String: Any] = [
                "type": "field",
                "outboundTag": outbound,
            ]
            if field == "domain" || field == "ip" || field == "source" {
                rule[field] = [value]
            } else {
                rule[field] = value
            }
            rules.append(rule)
            if catchAll { break }
        }
        guard !rules.isEmpty else { return "" }
        return JSONX.toJSONString(rules) ?? ""
    }

    private static func matcher(_ type: String, _ value: String) -> (String, String)? {
        func domainMatches(_ v: String) -> Bool {
            v.range(of: domainPattern, options: .regularExpression) != nil
        }
        switch type {
        case "DOMAIN":
            return domainMatches(value) ? ("domain", "full:\(value)") : nil
        case "DOMAIN-SUFFIX":
            return domainMatches(value) ? ("domain", "domain:\(value)") : nil
        case "DOMAIN-KEYWORD":
            return domainMatches(value) ? ("domain", "keyword:\(value)") : nil
        case "GEOSITE":
            guard value.range(of: siteCodePattern, options: .regularExpression) != nil else { return nil }
            return ("domain", "geosite:\(value)")
        case "GEOIP", "SRC-GEOIP":
            let lowered = value.lowercased()
            guard lowered == "ru" || lowered == "private" else { return nil }
            return (type == "GEOIP" ? "ip" : "source", "geoip:\(value)")
        case "IP-CIDR", "IP-CIDR6", "SRC-IP-CIDR":
            guard validCidr(value) else { return nil }
            return (type == "SRC-IP-CIDR" ? "source" : "ip", value)
        case "DST-PORT", "SRC-PORT":
            guard validPort(value) else { return nil }
            return (type == "DST-PORT" ? "port" : "sourcePort", value)
        case "NETWORK":
            let lowered = value.lowercased()
            guard lowered == "tcp" || lowered == "udp" else { return nil }
            return ("network", lowered)
        case "MATCH":
            return ("network", "tcp,udp")
        default:
            return nil
        }
    }

    private static func validCidr(_ value: String) -> Bool {
        guard let slash = value.firstIndex(of: "/") else { return false }
        let address = String(value[..<slash])
        guard let prefix = Int(value[value.index(after: slash)...]) else { return false }
        if address.contains(":") {
            return (0...128).contains(prefix) && isIPv6Address(address)
        }
        let octets = address.components(separatedBy: ".")
        guard (0...32).contains(prefix), octets.count == 4 else { return false }
        for octet in octets {
            guard (1...3).contains(octet.count),
                  octet.count == 1 || !octet.hasPrefix("0"),
                  octet.allSatisfy { $0.isNumber },
                  let number = Int(octet), number <= 255
            else { return false }
        }
        return true
    }

    /// Structural IPv6 check (the Android client resolved through InetAddress;
    /// the text the clash dialect carries is pure hex/colon groups).
    private static func isIPv6Address(_ address: String) -> Bool {
        let halves = address.components(separatedBy: "::")
        guard halves.count <= 2 else { return false }
        var groups = 0
        for half in halves {
            if half.isEmpty { continue }
            guard !half.hasPrefix(":") && !half.hasSuffix(":") else { return false }
            let pieces = half.components(separatedBy: ":")
            for piece in pieces {
                guard (1...4).contains(piece.count), piece.allSatisfy({ $0.isHexDigit }) else {
                    return false
                }
                groups += 1
            }
        }
        if halves.count == 2 {
            return groups <= 7
        }
        return groups == 8
    }

    private static func validPort(_ value: String) -> Bool {
        guard value.range(of: portPattern, options: .regularExpression) != nil else { return false }
        let dash = value.firstIndex(of: "-")
        let startText = dash.map { String(value[..<$0]) } ?? value
        let endText = dash.map { String(value[value.index(after: $0)...]) } ?? startText
        guard let start = Int(startText), let end = Int(endText) else { return false }
        return (1...65535).contains(start) && (start...65535).contains(end)
    }
}
