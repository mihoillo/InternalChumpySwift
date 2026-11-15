import Foundation

/// Parsers for share links: vmess://, vless://, trojan://, ss://, socks://,
/// hysteria2://, wireguard:// and .conf file bodies. Ported from the Android
/// client's `LinkParsers` (originally v2rayNG's fmt/, Apache-2.0).
///
/// A parser returns a draft `Profile` with an empty id and no subscription;
/// the repository stamps identity and ownership on insert. Nil means
/// "not a link of mine".
public enum LinkParsers {

    private static let tls = "tls"
    private static let reality = "reality"
    private static let defaultVmessSecurity = "auto"
    private static let defaultWGAddress = "172.16.0.2/32"
    private static let defaultWGMTU = 1420

    /// Dispatches on the scheme; accepts trimmed lines with surrounding junk spaces.
    public static func parse(_ link: String) -> Profile? {
        let raw = link.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schemeEnd = raw.range(of: "://") else { return nil }
        let trimmed = raw[raw.startIndex..<schemeEnd.lowerBound].lowercased()
            + raw[schemeEnd.lowerBound...]

        var parsed: Profile?
        if trimmed.hasPrefix("vmess://") {
            parsed = parseVmess(String(trimmed))
        } else if trimmed.hasPrefix("vless://") {
            parsed = parseVless(String(trimmed))
        } else if trimmed.hasPrefix("trojan://") {
            parsed = parseTrojan(String(trimmed))
        } else if trimmed.hasPrefix("ss://") {
            parsed = parseShadowsocks(String(trimmed))
        } else if trimmed.hasPrefix("socks://") || trimmed.hasPrefix("socks5://") {
            parsed = parseSocks(String(trimmed))
        } else if trimmed.hasPrefix("hy2://") || trimmed.hasPrefix("hysteria2://") {
            parsed = parseHysteria2(String(trimmed))
        } else if trimmed.hasPrefix("wireguard://") || trimmed.hasPrefix("wg://") {
            parsed = parseWireguardURI(String(trimmed))
        } else {
            parsed = nil
        }

        // The link itself rides along, verbatim.
        guard var profile = parsed else { return nil }
        guard
            !profile.server.isEmpty,
            (1...65535).contains(profile.serverPort)
        else { return nil }

        switch profile.type {
        case .vmess, .vless, .trojan:
            guard !profile.password.isEmpty else { return nil }
        case .wireguard:
            guard !profile.wgSecretKey.isEmpty, !profile.publicKey.isEmpty else { return nil }
        case .shadowsocks:
            guard !profile.method.isEmpty, !profile.password.isEmpty else { return nil }
        default:
            break
        }

        profile.sourceLink = raw
        return profile
    }

    /// A WireGuard .conf file body (the tunnel-migration import path).
    public static func parseWireguardConf(_ text: String) -> Profile? {
        var interfaceParams: [String: String] = [:]
        var peerParams: [String: String] = [:]
        var section: String? = nil
        var peers = 0

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.lowercased().hasPrefix("[interface]") {
                section = "interface"
            } else if line.lowercased().hasPrefix("[peer]") {
                peers += 1
                if peers > 1 { return nil }
                section = "peer"
            } else if line.hasPrefix("[") {
                section = nil
            } else if section != nil {
                guard let eqIdx = line.firstIndex(of: "="), eqIdx > line.startIndex else { continue }
                let key = String(line[..<eqIdx]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                if section == "interface" {
                    interfaceParams[key] = value
                } else {
                    peerParams[key] = value
                }
            }
        }

        guard let endpoint = peerParams["endpoint"], !endpoint.isEmpty,
              let privateKey = interfaceParams["privatekey"], !privateKey.isEmpty,
              let publicKey = peerParams["publickey"], !publicKey.isEmpty
        else { return nil }

        let endpointHost: String
        let endpointPort: Int
        if let colon = endpoint.lastIndex(of: ":"), colon > endpoint.startIndex {
            endpointHost = String(endpoint[..<colon]).removeSurrounding("[", "]")
            endpointPort = LinkUtils.parsePort(String(endpoint[endpoint.index(after: colon)...]))
        } else {
            endpointHost = endpoint
            endpointPort = 0
        }
        guard !endpointHost.isEmpty, (1...65535).contains(endpointPort) else { return nil }

        var profile = Profile(type: .wireguard)
        profile.server = endpointHost
        profile.serverPort = endpointPort
        profile.remarks = ""
        profile.wgSecretKey = privateKey
        profile.wgLocalAddress = interfaceParams["address"] ?? defaultWGAddress
        profile.wgMTU = interfaceParams["mtu"].flatMap(Int.init) ?? defaultWGMTU
        profile.publicKey = publicKey
        profile.wgPresharedKey = peerParams["presharedkey"] ?? ""
        profile.wgReserved = peerParams["reserved"] ?? "0,0,0"
        return profile
    }

    // MARK: - vmess

    private static func parseVmess(_ str: String) -> Profile? {
        // The modern "standard" vmess URI carries a query string; the classic
        // QR-code form is base64 of a JSON blob.
        if str.substringAfter("vmess://").substringBefore("#").contains("@") {
            return parseVmessURI(str)
        }

        let json = LinkUtils.decode(String(str.dropFirst("vmess://".count)))
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let qr = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        func field(_ name: String) -> String {
            guard let value = qr[name] else { return "" }
            if let s = value as? String { return s }
            if let n = value as? NSNumber { return n.stringValue }
            return ""
        }

        let add = field("add")
        let id = field("id")
        let net = field("net")
        guard !add.isEmpty, !id.isEmpty else { return nil }

        var profile = Profile(type: .vmess)
        profile.remarks = field("ps")
        profile.server = add
        profile.serverPort = LinkUtils.parsePort(field("port"))
        profile.password = id
        profile.method = field("scy").isEmpty ? defaultVmessSecurity : field("scy")
        profile.network = net.isEmpty ? "tcp" : net
        profile.headerType = field("type")
        profile.host = field("host")
        profile.path = field("path")
        profile.security = field("tls") == tls ? tls : ""
        profile.sni = field("sni")
        profile.alpn = field("alpn")
        profile.fingerprint = field("fp")
        profile.allowInsecure = field("insecure") == "1"

        switch profile.network {
        case "kcp", "mkcp":
            profile.seed = field("path")
        case "grpc":
            profile.mode = field("type")
            profile.serviceName = field("path")
            profile.authority = field("host")
        default:
            break
        }
        return profile
    }

    private static func parseVmessURI(_ str: String) -> Profile? {
        guard let uri = parseURI(str) else { return nil }
        var profile = Profile(type: .vmess)
        profile.remarks = fragmentOf(uri)
        profile.server = uri.idnHost
        profile.serverPort = uri.port
        profile.password = uri.userInfo ?? ""
        profile.method = defaultVmessSecurity
        return applyQueryParams(profile, uri.queryParams)
    }

    // MARK: - vless

    private static func parseVless(_ str: String) -> Profile? {
        guard let uri = parseURI(str) else { return nil }
        var profile = Profile(type: .vless)
        profile.remarks = fragmentOf(uri)
        profile.server = uri.idnHost
        profile.serverPort = uri.port
        profile.password = uri.userInfo ?? ""
        profile.method = uri.queryParams["encryption"] ?? "none"
        return applyQueryParams(profile, uri.queryParams)
    }

    // MARK: - trojan

    private static func parseTrojan(_ str: String) -> Profile? {
        guard let uri = parseURI(str) else { return nil }
        var profile = Profile(type: .trojan)
        profile.remarks = fragmentOf(uri)
        profile.server = uri.idnHost
        profile.serverPort = uri.port
        profile.password = uri.userInfo ?? ""

        let query = uri.queryParams
        if (uri.rawQuery ?? "").isEmpty {
            profile.network = "tcp"
            profile.security = tls
            return profile
        }
        profile = applyQueryParams(profile, query)
        profile.security = query["security"] ?? tls
        return profile
    }

    // MARK: - shadowsocks

    private static func parseShadowsocks(_ str: String) -> Profile? {
        parseShadowsocksSip002(str) ?? parseShadowsocksLegacy(str)
    }

    private static func parseShadowsocksSip002(_ str: String) -> Profile? {
        guard let uri = parseURI(str) else { return nil }
        guard !uri.idnHost.isEmpty, uri.port > 0 else { return nil }
        guard let userInfo = uri.userInfo, !userInfo.isEmpty else { return nil }

        var parts: [String]
        if userInfo.contains(":") {
            parts = userInfo.split(separator: ":", maxSplits: 1).map(String.init)
        } else {
            parts = LinkUtils.decode(userInfo).split(separator: ":", maxSplits: 1).map(String.init)
        }
        guard parts.count == 2, !parts[0].isEmpty else { return nil }

        var profile = Profile(type: .shadowsocks)
        profile.remarks = fragmentOf(uri)
        profile.server = uri.idnHost
        profile.serverPort = uri.port
        profile.method = parts[0]
        profile.password = parts[1]

        // The simple-obfs plugin rides along as a plain HTTP header fake.
        let plugin = uri.queryParams["plugin"] ?? ""
        if plugin.contains("obfs=http") {
            var pairs: [String: String] = [:]
            for pair in plugin.split(separator: ";") {
                let pairStr = String(pair)
                if let eqIdx = pairStr.firstIndex(of: "="), eqIdx > pairStr.startIndex {
                    pairs[String(pairStr[..<eqIdx])] = String(pairStr[pairStr.index(after: eqIdx)...])
                }
            }
            profile.network = "tcp"
            profile.headerType = "http"
            profile.host = pairs["obfs-host"] ?? ""
        }
        return profile
    }

    private static func parseShadowsocksLegacy(_ str: String) -> Profile? {
        var body = String(str.dropFirst("ss://".count))
        var remarks = ""
        if let hashIdx = body.firstIndex(of: "#"), hashIdx > body.startIndex {
            remarks = LinkUtils.decodeURIComponent(String(body[body.index(after: hashIdx)...]))
            body = String(body[..<hashIdx])
        }
        // Either the whole body is base64, or only the method:password half before "@".
        if let atIdx = body.firstIndex(of: "@"), atIdx > body.startIndex {
            body = LinkUtils.decode(String(body[..<atIdx])) + String(body[atIdx...])
        } else {
            body = LinkUtils.decode(body)
        }

        // ^(.+?):(.*)@(.+?):(\d+)/?$
        let pattern = #"^(.+?):(.*)@(.+?):(\d+)/?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: body, range: NSRange(body.startIndex..., options: []
              ),
              match.numberOfRanges == 5,
              let g3 = Range(match.range(at: 3), in: body),
              let g4 = Range(match.range(at: 4), in: body),
              let g2 = Range(match.range(at: 2), in: body),
              let g1 = Range(match.range(at: 1), in: body)
        else { return nil }

        var profile = Profile(type: .shadowsocks)
        profile.remarks = remarks
        profile.server = String(body[g3]).removeSurrounding("[", "]")
        profile.serverPort = LinkUtils.parsePort(String(body[g4]))
        profile.password = String(body[g2])
        profile.method = String(body[g1]).lowercased()
        return profile
    }

    // MARK: - socks

    private static func parseSocks(_ str: String) -> Profile? {
        guard let uri = parseURI(str) else { return nil }
        guard !uri.idnHost.isEmpty, uri.port > 0 else { return nil }
        var profile = Profile(type: .socks)
        profile.remarks = fragmentOf(uri)
        profile.server = uri.idnHost
        profile.serverPort = uri.port

        let userInfo = uri.rawUserInfo ?? ""
        if userInfo.contains(":") {
            profile.username = LinkUtils.decodeURIComponent(userInfo.substringBefore(":"))
            profile.password = LinkUtils.decodeURIComponent(userInfo.substringAfter(":"))
        }
        return profile
    }

    // MARK: - hysteria2

    private static func parseHysteria2(_ str: String) -> Profile? {
        guard let uri = parseURI(str) else { return nil }
        var profile = Profile(type: .hysteria2)
        profile.remarks = fragmentOf(uri)
        profile.server = uri.idnHost
        profile.serverPort = uri.port == -1 ? 443 : uri.port
        profile.password = uri.userInfo ?? ""
        profile.security = tls
        profile.network = "hysteria"

        guard let rawQuery = uri.rawQuery, !rawQuery.isEmpty else { return profile }
        let query = uri.queryParams
        profile = applyQueryParams(profile, query)
        profile.network = "hysteria"
        profile.security = query["security"] ?? tls
        profile.obfsPassword = query["obfs-password"] ?? ""
        profile.portHopping = query["mport"] ?? ""
        profile.portHoppingInterval = query["mportinterval"] ?? ""
        return profile
    }

    // MARK: - wireguard

    private static func parseWireguardURI(_ str: String) -> Profile? {
        guard let uri = parseURI(str) else { return nil }
        guard let rawQuery = uri.rawQuery, !rawQuery.isEmpty else { return nil }
        let query = uri.queryParams
        var profile = Profile(type: .wireguard)
        profile.remarks = fragmentOf(uri)
        profile.server = uri.idnHost
        profile.serverPort = uri.port
        profile.wgSecretKey = uri.userInfo ?? ""
        profile.wgLocalAddress = query["address"] ?? defaultWGAddress
        profile.publicKey = query["publickey"] ?? ""
        profile.wgPresharedKey = query["presharedkey"] ?? ""
        profile.wgMTU = query["mtu"].flatMap(Int.init) ?? defaultWGMTU
        profile.wgReserved = query["reserved"] ?? "0,0,0"
        return profile
    }

    // MARK: - shared

    /// Fills the transport/security fields shared by every scheme-with-query format.
    private static func applyQueryParams(_ profile: Profile, _ query: [String: String]) -> Profile {
        var result = profile
        result.network = query["type"] ?? "tcp"
        result.headerType = query["headerType"] ?? ""
        result.host = query["host"] ?? ""
        result.path = query["path"] ?? ""
        result.seed = query["seed"] ?? ""
        result.mode = query["mode"] ?? ""
        result.serviceName = query["serviceName"] ?? ""
        result.authority = query["authority"] ?? ""
        result.xhttpExtra = query["extra"]

        let security = query["security"]
        result.security = (security == tls || security == reality) ? security! : ""

        let insecureKeys = ["insecure", "allowInsecure", "allow_insecure"]
        result.allowInsecure = insecureKeys.contains { query[$0] == "1" }
        result.sni = query["sni"] ?? ""
        result.fingerprint = query["fp"] ?? ""
        result.alpn = query["alpn"] ?? ""
        result.publicKey = query["pbk"] ?? ""
        result.shortID = query["sid"] ?? ""
        result.spiderX = query["spx"] ?? ""
        result.flow = query["flow"] ?? ""
        return result
    }

    private static func fragmentOf(_ uri: ParsedURI) -> String {
        LinkUtils.decodeURIComponent(uri.rawFragment ?? "")
    }

    private static func parseURI(_ str: String) -> ParsedURI? {
        ParsedURI.parse(LinkUtils.fixIllegalURL(str))
    }
}
