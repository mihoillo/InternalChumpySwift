import Foundation

/// The raw-config subscription dialect: instead of share links, the panel
/// answers with whole Xray client configs — one object, or an array of them.
/// The profiles live in the outbounds: every proxy outbound is one server,
/// everything else (freedom, blackhole, dns, selectors) is plumbing.
/// Ported from the Android client's `ConfigParser`.
public enum ConfigParser {

    private static let tls = "tls"
    private static let reality = "reality"

    /// The protocols that mark a real proxy outbound; everything else is plumbing.
    private static let proxyProtocols: Set<String> = [
        "vless", "vmess", "trojan", "shadowsocks", "socks", "hysteria", "wireguard",
    ]

    /// The strategies this core runs, normalized to the names it switches on.
    private static let strategies: Set<String> = ["random", "roundrobin", "leastping", "leastload"]

    /// One config's reading: the outbounds parsed as (tag, profile) pairs,
    /// plus the balancers its routing carries.
    private struct Bundle {
        let prefix: String
        let entries: [(tag: String, profile: Profile)]
        let balancerSpecs: [[String: Any]]
        let routingRules: String
        let geodataSources: String
    }

    /// The profiles found in a raw-config body, deduplicated; nil when it is not one.
    public static func parse(_ body: String) -> [Profile]? {
        let trimmed = body
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") || trimmed.hasPrefix("{") else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data)
        else { return nil }

        let configs: [[String: Any]]
        if let array = root as? [Any] {
            let objects = array.compactMap { $0 as? [String: Any] }
            guard !objects.isEmpty else { return nil }
            configs = objects
        } else if let object = root as? [String: Any] {
            configs = [object]
        } else {
            return nil
        }
        guard configs.contains(where: { JSONX.array($0, "outbounds") != nil }) else { return nil }

        let bundles = configs.map { config -> Bundle in
            let proxies = proxyOutbounds(config)
            return Bundle(
                prefix: (JSONX.str(config, "remarks") ?? "")
                    .trimmingCharacters(in: .whitespaces),
                entries: proxies.compactMap { outbound in
                    guard let profile = outboundToProfile(outbound) else { return nil }
                    return (JSONX.str(outbound, "tag") ?? "", profile)
                },
                balancerSpecs: JSONX.arrayOfObjects(
                    JSONX.array(JSONX.obj(config, "routing"), "balancers")
                ),
                routingRules: routingRulesOf(config),
                geodataSources: GeodataSources.fromConfig(config)
            )
        }

        // The list runs in the panel's own order; a config whose routing carries
        // a surviving balancer hides its outbounds behind the group row.
        var seenBalancers = Set<String>()
        var emitted: [String: Int] = [:]
        var profiles: [Profile] = []

        for bundle in bundles {
            let balancers = balancersOf(bundle)
            for balancer in balancers {
                let key = balancer.computeLinkKey()
                if seenBalancers.insert(key).inserted {
                    var b = balancer
                    b.routingRules = bundle.routingRules
                    b.geodataSources = bundle.geodataSources
                    profiles.append(b)
                }
            }
            let internalConfig = !balancers.isEmpty
            // One proxy in the config takes the remarks alone; more ride the
            // remarks and the tag together.
            let singleProxy = bundle.entries.count == 1
            for (tag, profile) in bundle.entries {
                let key = profile.computeLinkKey()
                if let index = emitted[key] {
                    if !internalConfig {
                        var filed = profiles[index]
                        if filed.hidden {
                            filed.hidden = false
                            filed.remarks = bundle.prefix.isEmpty ? tag : bundle.prefix
                            filed.routingRules = bundle.routingRules
                            filed.geodataSources = bundle.geodataSources
                            profiles[index] = filed
                        }
                    }
                } else {
                    let name: String
                    if singleProxy {
                        name = bundle.prefix.isEmpty ? tag : bundle.prefix
                    } else if !bundle.prefix.isEmpty && !tag.isEmpty {
                        name = "\(bundle.prefix) \(tag)"
                    } else {
                        name = tag
                    }
                    var p = profile
                    p.remarks = name
                    p.routingRules = bundle.routingRules
                    p.geodataSources = bundle.geodataSources
                    p.hidden = internalConfig
                    emitted[key] = profiles.count
                    profiles.append(p)
                }
            }
        }
        return profiles.isEmpty ? nil : profiles
    }

    /// The balancers one config's routing carries, as profile drafts.
    private static func balancersOf(_ bundle: Bundle) -> [Profile] {
        guard !bundle.entries.isEmpty, !bundle.balancerSpecs.isEmpty else { return [] }
        let multiple = bundle.balancerSpecs.count >= 2
        return bundle.balancerSpecs.compactMap { spec -> Profile? in
            let selector = JSONX.strings(JSONX.array(spec, "selector"))
            let fallbackTag = (JSONX.str(spec, "fallbackTag") ?? "")
                .trimmingCharacters(in: .whitespaces)
            guard !selector.isEmpty || !fallbackTag.isEmpty else { return nil }

            var members: [(tag: String, profile: Profile)] = []
            for (tag, profile) in bundle.entries {
                if selector.contains(where: { !$0.isEmpty && tag.hasPrefix($0) }),
                   !members.contains(where: { $0.profile == profile }) {
                    members.append((tag, profile))
                }
            }
            // The fallback joins the members only to keep a lone one alive.
            if members.count < 2, !fallbackTag.isEmpty {
                for (tag, profile) in bundle.entries {
                    if tag == fallbackTag, !members.contains(where: { $0.profile == profile }) {
                        members.append((tag, profile))
                    }
                }
            }
            guard members.count >= 2 else { return nil }

            let tagName = (JSONX.str(spec, "tag") ?? "").trimmingCharacters(in: .whitespaces)
            var shortTag = tagName
            if shortTag.hasSuffix("_Balancer") { shortTag = String(shortTag.dropLast("_Balancer".count)) }
            if shortTag.hasSuffix("Balancer") { shortTag = String(shortTag.dropLast("Balancer".count)) }
            if shortTag.isEmpty { shortTag = tagName.isEmpty ? "Balancer" : tagName }

            let name: String
            if !bundle.prefix.isEmpty && multiple {
                name = "\(bundle.prefix) (\(shortTag))"
            } else if !bundle.prefix.isEmpty {
                name = bundle.prefix
            } else {
                name = shortTag
            }

            var profile = Profile(type: .balancer)
            profile.remarks = name
            profile.balancerStrategy = normalizeStrategy(JSONX.str(JSONX.obj(spec, "strategy"), "type"))
            profile.balancerMembers = members
                .map { $0.profile.computeLinkKey() }
                .joined(separator: "\n")
            return profile
        }
    }

    /// The strategies this core runs, normalized; anything else falls back to random.
    private static func normalizeStrategy(_ type: String?) -> String {
        let normalized = (type ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return strategies.contains(normalized) ? normalized : "random"
    }

    private static func proxyOutbounds(_ config: [String: Any]) -> [[String: Any]] {
        JSONX.arrayOfObjects(JSONX.array(config, "outbounds"))
            .filter { outbound in
                guard let protocolName = JSONX.str(outbound, "protocol") else { return false }
                return proxyProtocols.contains(protocolName)
            }
    }

    /// One outbound as a profile draft; nil when its endpoint does not hold together.
    private static func outboundToProfile(_ outbound: [String: Any]) -> Profile? {
        let type: ProfileType
        switch JSONX.str(outbound, "protocol") {
        case "vless": type = .vless
        case "vmess": type = .vmess
        case "trojan": type = .trojan
        case "shadowsocks": type = .shadowsocks
        case "socks": type = .socks
        case "hysteria": type = .hysteria2
        case "wireguard": type = .wireguard
        default: return nil
        }

        let settings = JSONX.obj(outbound, "settings") ?? [:]

        if type == .wireguard {
            let peers = JSONX.arrayOfObjects(JSONX.array(settings, "peers"))
            guard peers.count == 1, let peer = peers.first else { return nil }
            guard let endpoint = JSONX.str(peer, "endpoint") else { return nil }
            let host = endpoint.substringBeforeLast(":").removeSurrounding("[", "]")
            guard let port = Int(endpoint.substringAfterLast(":")) else { return nil }
            guard let secret = JSONX.str(settings, "secretKey"), !secret.isEmpty else { return nil }
            guard let key = JSONX.str(peer, "publicKey"), !key.isEmpty else { return nil }
            guard !host.isEmpty, (1...65535).contains(port) else { return nil }
            var profile = Profile(type: .wireguard)
            profile.server = host
            profile.serverPort = port
            profile.wgSecretKey = secret
            profile.publicKey = key
            profile.wgPresharedKey = JSONX.str(peer, "preSharedKey") ?? ""
            profile.wgLocalAddress = JSONX.strings(JSONX.array(settings, "address")).joined(separator: ",")
            profile.wgMTU = JSONX.int(settings, "mtu") ?? 1420
            profile.wgReserved = JSONX.strings(JSONX.array(settings, "reserved")).joined(separator: ",")
            return profile
        }

        // The nested dialect nests the endpoint in vnext/servers with a users
        // list inside; the flat one keeps address/port/id directly in settings.
        let endpoint = JSONX.arrayOfObjects(JSONX.array(settings, "vnext")).first
            ?? JSONX.arrayOfObjects(JSONX.array(settings, "servers")).first
        let user = JSONX.arrayOfObjects(JSONX.array(endpoint, "users")).first

        let server = JSONX.str(endpoint, "address") ?? JSONX.str(settings, "address") ?? ""
        let port = JSONX.int(endpoint, "port") ?? JSONX.int(settings, "port") ?? 0
        guard !server.isEmpty, (1...65535).contains(port) else { return nil }

        var profile = Profile(type: type)
        profile.remarks = JSONX.str(outbound, "tag") ?? ""
        profile.server = server
        profile.serverPort = port

        switch type {
        case .vless:
            profile.password = user.flatMap { JSONX.str($0, "id") }
                ?? JSONX.str(settings, "id") ?? ""
            profile.method = user.flatMap { JSONX.str($0, "encryption") }
                ?? JSONX.str(settings, "encryption") ?? "none"
            profile.flow = user.flatMap { JSONX.str($0, "flow") }
                ?? JSONX.str(settings, "flow") ?? ""

        case .vmess:
            profile.password = user.flatMap { JSONX.str($0, "id") }
                ?? JSONX.str(settings, "id") ?? ""
            profile.method = user.flatMap { JSONX.str($0, "security") }
                ?? JSONX.str(settings, "security") ?? "auto"
            profile.flow = user.flatMap { JSONX.str($0, "flow") }
                ?? JSONX.str(settings, "flow") ?? ""

        case .trojan:
            profile.password = JSONX.str(endpoint, "password")
                ?? JSONX.str(settings, "password") ?? ""
            profile.flow = JSONX.str(endpoint, "flow") ?? JSONX.str(settings, "flow") ?? ""

        case .shadowsocks:
            profile.method = JSONX.str(endpoint, "method") ?? JSONX.str(settings, "method") ?? ""
            profile.password = JSONX.str(endpoint, "password") ?? JSONX.str(settings, "password") ?? ""

        case .socks:
            profile.username = user.flatMap { JSONX.str($0, "user") }
                ?? JSONX.str(settings, "user") ?? ""
            profile.password = user.flatMap { JSONX.str($0, "pass") }
                ?? JSONX.str(settings, "pass") ?? ""

        case .hysteria2:
            guard let hysteria = JSONX.obj(JSONX.obj(outbound, "streamSettings"), "hysteriaSettings")
            else { return nil }
            guard JSONX.int(settings, "version") == 2, JSONX.int(hysteria, "version") == 2 else {
                return nil
            }
            guard let auth = JSONX.str(hysteria, "auth") else { return nil }
            var obfsPassword = ""
            var portHopping = ""
            var portHoppingInterval = ""
            let masks = JSONX.arrayOfObjects(
                JSONX.array(JSONX.obj(JSONX.obj(outbound, "streamSettings"), "finalmask"), "udp")
            )
            for mask in masks {
                switch JSONX.str(mask, "type") {
                case "salamander":
                    obfsPassword = JSONX.str(JSONX.obj(mask, "settings"), "password") ?? ""
                case "udphop":
                    portHopping = JSONX.str(JSONX.obj(mask, "settings"), "remotePorts") ?? ""
                    portHoppingInterval = JSONX.str(JSONX.obj(mask, "settings"), "interval") ?? ""
                default:
                    break
                }
            }
            profile.password = auth
            profile.obfsPassword = obfsPassword
            profile.portHopping = portHopping
            profile.portHoppingInterval = portHoppingInterval

        default:
            return nil
        }

        if type == .vless || type == .vmess || type == .trojan {
            guard !profile.password.isEmpty else { return nil }
        }
        if type == .shadowsocks {
            guard !profile.method.isEmpty, !profile.password.isEmpty else { return nil }
        }

        var streamed = withStream(profile, JSONX.obj(outbound, "streamSettings"))
        if type == .hysteria2 {
            streamed.network = "hysteria"
        }
        return streamed
    }

    /// The streamSettings object folded into the transport and security fields
    /// links carry — the reading mirror of OutboundBuilder's writing.
    private static func withStream(_ profile: Profile, _ stream: [String: Any]?) -> Profile {
        guard let stream else { return profile }
        var result = profile
        result.network = {
            let n = JSONX.str(stream, "network") ?? ""
            return n.isEmpty ? "tcp" : n
        }()

        // Security: the settings object that rides under it tells the details.
        let declared = JSONX.str(stream, "security") ?? ""
        let security = (declared == tls || declared == reality) ? declared : ""
        result.security = security

        let secure = security == reality
            ? JSONX.obj(stream, "realitySettings")
            : JSONX.obj(stream, "tlsSettings")
        if let secure {
            result.sni = JSONX.str(secure, "serverName") ?? ""
            result.fingerprint = JSONX.str(secure, "fingerprint") ?? ""
            result.alpn = JSONX.strings(JSONX.array(secure, "alpn")).joined(separator: ",")
            result.allowInsecure = security == tls && JSONX.str(secure, "allowInsecure") == "true"
            if security == reality {
                result.publicKey = JSONX.str(secure, "publicKey") ?? ""
                result.shortID = JSONX.str(secure, "shortId") ?? ""
                result.spiderX = JSONX.str(secure, "spiderX") ?? ""
            }
        }

        switch result.network {
        case "tcp", "raw":
            if let header = JSONX.obj(JSONX.obj(stream, "tcpSettings"), "header"),
               JSONX.str(header, "type") == "http" {
                let request = JSONX.obj(header, "request")
                result.headerType = "http"
                result.host = JSONX.strings(JSONX.array(JSONX.obj(request, "headers"), "Host"))
                    .joined(separator: ",")
                result.path = JSONX.strings(JSONX.array(request, "path")).first ?? ""
            }

        case "kcp", "mkcp":
            if let kcp = JSONX.obj(stream, "kcpSettings") {
                result.headerType = JSONX.str(JSONX.obj(kcp, "header"), "type") ?? ""
                result.seed = JSONX.str(kcp, "seed") ?? ""
            }

        case "ws", "websocket":
            if let ws = JSONX.obj(stream, "wsSettings") {
                result.path = JSONX.str(ws, "path") ?? ""
                result.host = JSONX.str(ws, "host")
                    ?? JSONX.str(JSONX.obj(ws, "headers"), "Host")
                    ?? JSONX.str(JSONX.obj(ws, "headers"), "host") ?? ""
            }

        case "httpupgrade":
            if let up = JSONX.obj(stream, "httpupgradeSettings") {
                result.path = JSONX.str(up, "path") ?? ""
                result.host = JSONX.str(up, "host") ?? ""
            }

        case "grpc":
            if let grpc = JSONX.obj(stream, "grpcSettings") {
                result.serviceName = JSONX.str(grpc, "serviceName") ?? ""
                result.authority = JSONX.str(grpc, "authority") ?? ""
                result.mode = JSONX.str(grpc, "multiMode") == "true" ? "multi" : ""
            }

        case "xhttp", "splithttp":
            if let xhttp = JSONX.obj(stream, "xhttpSettings") {
                result.host = JSONX.str(xhttp, "host") ?? ""
                result.path = JSONX.str(xhttp, "path") ?? ""
                result.mode = JSONX.str(xhttp, "mode") ?? ""
                result.xhttpExtra = JSONX.obj(xhttp, "extra").flatMap { JSONX.toJSONString($0) }
            }

        default:
            break
        }
        return result
    }

    /// The routing rules worth carrying, as a raw JSON array: the panel's own
    /// intent for its servers, rewritten onto the session's tags at build time.
    private static func routingRulesOf(_ config: [String: Any]) -> String {
        var targets: [String: String] = [:]
        for outbound in JSONX.arrayOfObjects(JSONX.array(config, "outbounds")) {
            let tag = JSONX.str(outbound, "tag") ?? ""
            switch JSONX.str(outbound, "protocol") {
            case "freedom": targets[tag] = "direct"
            case "blackhole": targets[tag] = "block"
            default: targets[tag] = tag
            }
        }

        let raw = JSONX.arrayOfObjects(JSONX.array(JSONX.obj(config, "routing"), "rules"))
        let carried: [[String: Any]] = raw.compactMap { rule in
            let type = (JSONX.str(rule, "type") ?? "")
                .trimmingCharacters(in: .whitespaces).lowercased()
            guard type.isEmpty || type == "field" else { return nil }

            let outboundTarget = nonBlank(JSONX.str(rule, "outboundTag"))
                ?? nonBlank(JSONX.str(rule, "outbound"))
            let balancerTarget = nonBlank(JSONX.str(rule, "balancerTag"))
            guard outboundTarget != nil || balancerTarget != nil else { return nil }

            var matchers: [String: Any] = ["type": "field"]

            func strings(_ keys: [String], into: String) {
                for key in keys {
                    guard let element = rule[key] else { continue }
                    let values: [String]
                    if let array = element as? [Any] {
                        values = JSONX.strings(array)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    } else if let s = JSONX.strValue(element) {
                        let trimmed = s.trimmingCharacters(in: .whitespaces)
                        values = trimmed.isEmpty ? [] : [trimmed]
                    } else {
                        values = []
                    }
                    if !values.isEmpty {
                        matchers[into] = values as [Any]
                        return
                    }
                }
            }
            strings(["domain", "domains"], into: "domain")
            strings(["ip", "ips"], into: "ip")
            strings(["source"], into: "source")
            strings(["protocol"], into: "protocol")

            func scalar(_ key: String, into: String, transform: ((String) -> String?)? = nil) {
                guard let raw = JSONX.str(rule, key)?
                    .trimmingCharacters(in: .whitespaces)
                else { return }
                let value = transform?(raw) ?? raw
                guard !value.isEmpty else { return }
                matchers[into] = value
            }
            scalar("port", into: "port")
            scalar("sourcePort", into: "sourcePort")
            scalar("attrs", into: "attrs")
            // One protocol only; "tcp,udp" is a catch-all, not a matcher.
            scalar("network", into: "network") { raw in
                switch raw.lowercased() {
                case "tcp": return "tcp"
                case "udp": return "udp"
                default: return nil
                }
            }
            guard matchers.count > 1 else { return nil }

            if let outboundTarget {
                matchers["outboundTag"] = targets[outboundTarget] ?? outboundTarget
            } else {
                matchers["balancerTag"] = balancerTarget ?? ""
            }
            return matchers
        }
        guard !carried.isEmpty else { return "" }
        return JSONX.toJSONString(carried) ?? ""
    }

    private static func nonBlank(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s.trimmingCharacters(in: .whitespaces)
    }
}

extension String {
    /// Kotlin `substringBeforeLast`.
    func substringBeforeLast(_ delimiter: String) -> String {
        guard let range = range(of: delimiter, options: .backwards) else { return self }
        return String(self[..<range.lowerBound])
    }

    /// Kotlin `substringAfterLast`.
    func substringAfterLast(_ delimiter: String) -> String {
        guard let range = range(of: delimiter, options: .backwards) else { return self }
        return String(self[range.upperBound...])
    }
}
