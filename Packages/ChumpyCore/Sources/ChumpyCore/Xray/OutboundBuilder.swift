import Foundation

/// Renders a `Profile` as one Xray outbound, in the current core's flat settings
/// dialect (`address`/`port`/… directly in settings — the form Xray-core's own
/// config loader accepts and v2rayNG emits). Ported from the Android client's
/// `OutboundBuilder` (modeled on v2rayNG's CoreOutboundBuilder).
public enum OutboundBuilder {

    private static let tls = "tls"
    private static let reality = "reality"

    /// The endpoint host the config's address field wants, IPv6 brackets included.
    private static func host(_ profile: Profile) -> String {
        LinkUtils.ipv6Brackets(profile.server)
    }

    public static func build(_ profile: Profile, tag: String = "proxy") -> [String: Any] {
        var outbound: [String: Any] = [
            "tag": tag,
            "protocol": protocolName(profile.type),
            "settings": settings(profile),
            "mux": ["enabled": false as Any],
        ]
        if profile.type != .wireguard {
            if let stream = streamSettings(profile) {
                outbound["streamSettings"] = stream
            }
        }
        return outbound
    }

    public static func protocolName(_ type: ProfileType) -> String {
        switch type {
        case .vmess: return "vmess"
        case .vless: return "vless"
        case .trojan: return "trojan"
        case .shadowsocks: return "shadowsocks"
        case .socks: return "socks"
        case .wireguard: return "wireguard"
        case .hysteria2: return "hysteria"
        // A balancer never reaches an outbound: it is unwrapped into its members
        // at build time, in XrayConfigBuilder.
        case .balancer: return "balancer"
        }
    }

    private static func settings(_ profile: Profile) -> [String: Any] {
        switch profile.type {
        case .balancer:
            // A balancer is not an outbound; XrayConfigBuilder unwraps it first.
            return [:]

        case .vmess:
            return [
                "address": host(profile),
                "port": profile.serverPort,
                "id": profile.password,
                "security": profile.method.isEmpty ? "auto" : profile.method,
                "level": 8,
            ]

        case .vless:
            var s: [String: Any] = [
                "address": host(profile),
                "port": profile.serverPort,
                "id": profile.password,
                "encryption": profile.method.isEmpty ? "none" : profile.method,
                "level": 8,
            ]
            if !profile.flow.isEmpty { s["flow"] = profile.flow }
            return s

        case .trojan:
            var s: [String: Any] = [
                "address": host(profile),
                "port": profile.serverPort,
                "password": profile.password,
                "level": 8,
            ]
            if !profile.flow.isEmpty { s["flow"] = profile.flow }
            return s

        case .shadowsocks:
            return [
                "address": host(profile),
                "port": profile.serverPort,
                "method": profile.method,
                "password": profile.password,
                "level": 8,
            ]

        case .socks:
            var s: [String: Any] = [
                "address": host(profile),
                "port": profile.serverPort,
                "level": 8,
            ]
            if !profile.username.isEmpty { s["user"] = profile.username }
            if !profile.password.isEmpty { s["pass"] = profile.password }
            return s

        case .hysteria2:
            return [
                "version": 2,
                "address": host(profile),
                "port": profile.serverPort,
            ]

        case .wireguard:
            return wireguardSettings(profile)
        }
    }

    private static func wireguardSettings(_ profile: Profile) -> [String: Any] {
        var peers: [String: Any] = [
            "publicKey": profile.publicKey,
            "endpoint": "\(host(profile)):\(profile.serverPort)",
            "keepAlive": 0,
        ]
        if !profile.wgPresharedKey.isEmpty {
            peers["preSharedKey"] = profile.wgPresharedKey
        }
        var settings: [String: Any] = [
            "secretKey": profile.wgSecretKey,
            "address": profile.wgLocalAddress
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            "peers": [peers],
            "mtu": profile.wgMTU > 0 ? profile.wgMTU : 1420,
            "remoteDNS": ["1.1.1.1", "8.8.8.8"],
        ]
        if let reserved = reservedOf(profile) {
            settings["reserved"] = reserved
        }
        return settings
    }

    /// The WireGuard client's reserved bytes, "1,2,3"-style, as a JSON array.
    private static func reservedOf(_ profile: Profile) -> [Int]? {
        let bytes = profile.wgReserved
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return bytes.count == 3 ? bytes : nil
    }

    // MARK: - Stream

    /// The streamSettings object: transport + security. Nil only when there is
    /// nothing to say (plain TCP without TLS), in which case the whole section
    /// is omitted. The "security" field itself matters as much as the settings
    /// object under it: the core's loader rejects a vless or trojan outbound
    /// whose security type reads empty.
    private static func streamSettings(_ profile: Profile) -> [String: Any]? {
        // Hysteria2 rides its own transport, named after the protocol; the
        // profile type decides, the network field can only agree.
        let network: String
        if profile.type == .hysteria2 {
            network = "hysteria"
        } else {
            network = profile.network.isEmpty ? "tcp" : profile.network
        }
        var json: [String: Any] = ["network": network]

        switch profile.security {
        case tls:
            json["security"] = tls
            json["tlsSettings"] = tlsSettings(profile)
        case reality:
            json["security"] = reality
            json["realitySettings"] = realitySettings(profile)
        default:
            break
        }

        if let (name, transport) = transportSettings(profile) {
            json[name] = transport
        }

        if profile.type == .hysteria2 || profile.network == "hysteria" {
            let hysteria: [String: Any] = [
                "version": 2,
                "auth": profile.password,
            ]
            json["hysteriaSettings"] = hysteria
            if let mask = finalMask(profile) {
                json["finalmask"] = mask
            }
        }

        if json.count > 1 || !(network == "tcp" || network == "raw") {
            return json
        }
        return nil
    }

    private static func tlsSettings(_ profile: Profile) -> [String: Any] {
        var s: [String: Any] = [:]
        if !profile.sni.isEmpty { s["serverName"] = profile.sni }
        if profile.allowInsecure { s["allowInsecure"] = true }
        if !profile.fingerprint.isEmpty { s["fingerprint"] = profile.fingerprint }
        // Hysteria2 rides on HTTP/3; everything else keeps the link's own list.
        let alpn = profile.alpn
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let effective: [String]
        if !alpn.isEmpty {
            effective = alpn
        } else if profile.type == .hysteria2 || profile.network == "hysteria" {
            effective = ["h3"]
        } else {
            effective = []
        }
        if !effective.isEmpty { s["alpn"] = effective }
        return s
    }

    private static func realitySettings(_ profile: Profile) -> [String: Any] {
        var s: [String: Any] = [
            "publicKey": profile.publicKey,
            "show": false,
        ]
        if !profile.sni.isEmpty { s["serverName"] = profile.sni }
        if !profile.fingerprint.isEmpty { s["fingerprint"] = profile.fingerprint }
        if !profile.shortID.isEmpty { s["shortId"] = profile.shortID }
        if !profile.spiderX.isEmpty { s["spiderX"] = profile.spiderX }
        return s
    }

    /// transport-name → settings-object, for the transports that need one.
    private static func transportSettings(_ profile: Profile) -> (String, [String: Any])? {
        switch profile.network {
        case "tcp", "raw":
            guard profile.headerType == "http" else { return nil }
            var request: [String: Any] = [
                "path": [profile.path.isEmpty ? "/" : profile.path],
            ]
            let hostHeader = profile.host
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !hostHeader.isEmpty {
                request["headers"] = ["Host": Array(hostHeader)]
            }
            return ("tcpSettings", [
                "header": [
                    "type": "http",
                    "request": request,
                ],
            ])

        case "kcp", "mkcp":
            var s: [String: Any] = [
                "header": ["type": profile.headerType.isEmpty ? "none" : profile.headerType],
            ]
            if !profile.seed.isEmpty { s["seed"] = profile.seed }
            return ("kcpSettings", s)

        case "ws", "websocket":
            var s: [String: Any] = ["path": profile.path]
            if !profile.host.isEmpty { s["host"] = profile.host }
            return ("wsSettings", s)

        case "httpupgrade":
            var s: [String: Any] = ["path": profile.path]
            if !profile.host.isEmpty { s["host"] = profile.host }
            return ("httpupgradeSettings", s)

        case "grpc":
            var s: [String: Any] = ["serviceName": profile.serviceName]
            if !profile.authority.isEmpty { s["authority"] = profile.authority }
            if profile.mode == "multi" { s["multiMode"] = true }
            return ("grpcSettings", s)

        case "xhttp", "splithttp":
            var s: [String: Any] = [
                "path": profile.path,
                "mode": profile.mode.isEmpty ? "auto" : profile.mode,
            ]
            if !profile.host.isEmpty { s["host"] = profile.host }
            if let extra = rawJSON(profile.xhttpExtra) {
                s["extra"] = extra
            }
            return ("xhttpSettings", s)

        default:
            return nil
        }
    }

    /// The Hysteria2 masking block: salamander obfuscation and UDP port hopping.
    private static func finalMask(_ profile: Profile) -> [String: Any]? {
        var udp: [[String: Any]] = []
        if !profile.obfsPassword.isEmpty {
            udp.append([
                "type": "salamander",
                "settings": ["password": profile.obfsPassword],
            ])
        }
        if !profile.portHopping.isEmpty {
            udp.append([
                "type": "udphop",
                "settings": [
                    "mode": "intervalremote",
                    "interval": profile.portHoppingInterval.isEmpty ? "30" : profile.portHoppingInterval,
                    "remotePorts": profile.portHopping,
                ],
            ])
        }
        return udp.isEmpty ? nil : ["udp": udp]
    }

    /// Pass-through of a raw JSON blob (XHTTP extra); nil when it is not valid JSON.
    private static func rawJSON(_ raw: String?) -> Any? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
