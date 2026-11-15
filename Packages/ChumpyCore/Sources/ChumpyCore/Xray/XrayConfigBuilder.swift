import Foundation

/// Assembles the complete Xray config documents the core runs: the full VPN
/// config (TUN + local SOCKS inbounds, the selected proxy, direct/block
/// outbounds, routing by `RoutingMode`) and the bare single-outbound document
/// used for delay measurements. Ported from the Android client's
/// `XrayConfigBuilder`; everything is plain JSON over `OutboundBuilder`.
public enum XrayConfigBuilder {

    public static let proxyTag = "proxy"
    public static let directTag = "direct"
    public static let blockTag = "block"
    public static let socksTag = "socks"
    public static let tunTag = "tun"

    /// The loopback SOCKS port the UI reaches the running core on.
    public static let localSocksPort = 10808

    /// The default URL real delay measurements fetch through the tested outbound.
    public static let defaultTestURL = "https://www.gstatic.com/generate_204"

    private static let tunName = "chumpy0"
    private static let tunMTU = 1500
    private static let userLevel = 8

    /// The tag of the balancer over the members, when the session runs one.
    private static let balancerTag = "balancer"

    /// How often the observatory re-probes a balancer's members.
    private static let observatoryProbeInterval = "1m"

    /// The strategies the core's balancer switch knows; the two observing ones
    /// need the root-level observatory, which the builder emits with them.
    private static let observingStrategies: Set<String> = ["leastping", "leastload"]

    public enum BuildError: Error, LocalizedError {
        case balancerWithoutMembers
        case serializationFailed

        public var errorDescription: String? {
            switch self {
            case .balancerWithoutMembers:
                return "Balancer has no usable servers"
            case .serializationFailed:
                return "Could not serialize the Xray config"
            }
        }
    }

    /// The document the tunnel hands to the core alongside the TUN descriptor.
    ///
    /// A BALANCER profile carries no endpoint of its own: its `members` — the
    /// resolved member rows — ride along instead, each its own tagged outbound,
    /// with the balancer over them and the routing's fall-through aimed at it.
    /// The first member keeps the plain proxy tag: it is the default outbound a
    /// dead balancer falls back to, and the tag the stats have always counted.
    public static func buildFull(
        profile: Profile,
        mode: RoutingMode,
        members: [Profile] = [],
        testURL: String = defaultTestURL
    ) throws -> String {
        guard profile.type != .balancer || !members.isEmpty else {
            throw BuildError.balancerWithoutMembers
        }
        let balancerMembers = profile.type == .balancer ? members : []
        let strategy = profile.balancerStrategy.isEmpty ? "random" : profile.balancerStrategy

        var outbounds: [[String: Any]] = []
        if balancerMembers.isEmpty {
            outbounds.append(OutboundBuilder.build(profile, tag: proxyTag))
        } else {
            for (index, member) in balancerMembers.enumerated() {
                outbounds.append(OutboundBuilder.build(member, tag: memberTag(index)))
            }
        }
        outbounds.append([
            "tag": directTag,
            "protocol": "freedom",
            "settings": ["domainStrategy": "UseIP"],
        ])
        outbounds.append([
            "tag": blockTag,
            "protocol": "blackhole",
            "settings": ["response": ["type": "http"]],
        ])

        var config: [String: Any] = [
            "stats": [:] as [String: Any],
            "log": ["loglevel": "warning"],
            "policy": [
                "levels": [
                    "8": [
                        "handshake": 4,
                        "connIdle": 300,
                        "uplinkOnly": 1,
                        "downlinkOnly": 1,
                    ],
                ],
                "system": [
                    "statsOutboundUplink": true,
                    "statsOutboundDownlink": true,
                ],
            ],
            "inbounds": [
                [
                    "tag": socksTag,
                    "port": localSocksPort,
                    "listen": "127.0.0.1",
                    "protocol": "socks",
                    "settings": [
                        "auth": "noauth",
                        "udp": true,
                        "userLevel": userLevel,
                    ],
                    "sniffing": sniffing(),
                ],
                [
                    "tag": tunTag,
                    "protocol": "tun",
                    "settings": [
                        "name": tunName,
                        "mtu": tunMTU,
                        "userLevel": userLevel,
                    ],
                    "sniffing": sniffing(),
                ],
            ],
            "outbounds": outbounds,
            "routing": routing(
                mode: mode,
                balanced: !balancerMembers.isEmpty,
                strategy: strategy,
                profileRules: mode == .global ? profile.routingRules : "",
                geodataSources: profile.geodataSources
            ),
            "dns": [
                "hosts": [:] as [String: Any],
                // The first server is the one the wireguard outbound asks for
                // its peer endpoint — and the only resolver that knows
                // private-zone names (the system's). It must be "localhost".
                "servers": ["localhost", "1.1.1.1", "8.8.8.8"],
            ],
        ]

        if observingStrategies.contains(strategy) && !balancerMembers.isEmpty {
            // The observing strategies need a probe source: one root-level
            // observatory over the members.
            config["observatory"] = [
                "subjectSelector": [proxyTag],
                "probeURL": testURL,
                "probeInterval": observatoryProbeInterval,
                "enableConcurrency": true,
            ]
        }

        guard let json = JSONX.toJSONString(config) else {
            throw BuildError.serializationFailed
        }
        return json
    }

    /// The bare document for delay measurements: one outbound, no inbounds.
    public static func buildTest(_ profile: Profile) -> String {
        let config: [String: Any] = [
            "log": ["loglevel": "warning"],
            "inbounds": [] as [[String: Any]],
            "outbounds": [OutboundBuilder.build(profile, tag: proxyTag)],
            "routing": [
                "domainStrategy": "AsIs",
                "rules": [] as [[String: Any]],
            ],
        ]
        return JSONX.toJSONString(config) ?? "{}"
    }

    private static func sniffing() -> [String: Any] {
        [
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
        ]
    }

    private static func routing(
        mode: RoutingMode,
        balanced: Bool,
        strategy: String,
        profileRules: String,
        geodataSources: String
    ) -> [String: Any] {
        var rules: [[String: Any]] = []
        if let region = mode.region {
            // Sniffed BitTorrent goes direct in bypass mode, as in v2rayNG's presets.
            rules.append([
                "type": "field",
                "protocol": ["bittorrent"],
                "outboundTag": directTag,
            ])
            // The geosite lists exist for the big three (v2rayNG's own presets
            // use these codes); the rest ride the country's TLD.
            var domains: [String] = []
            switch region {
            case "ru": domains.append("geosite:category-ru")
            case "ir": domains.append("geosite:category-ir")
            case "cn": domains.append("geosite:cn")
            default: break
            }
            domains.append("domain:\(region)")
            rules.append([
                "type": "field",
                "domain": domains,
                "outboundTag": directTag,
            ])
            rules.append([
                "type": "field",
                "ip": ["geoip:\(region)"],
                "outboundTag": directTag,
            ])
        }
        // QUIC would tunnel UDP 443; blocking it keeps traffic on sniffable TCP.
        rules.append([
            "type": "field",
            "port": "443",
            "network": "udp",
            "outboundTag": blockTag,
        ])
        rules.append([
            "type": "field",
            "ip": ["geoip:private"],
            "outboundTag": directTag,
        ])
        rules.append([
            "type": "field",
            "domain": ["geosite:private"],
            "outboundTag": directTag,
        ])
        // The panel's own rules, next to ours; targets rewritten onto this
        // session's tags, geodata references onto the provider's files.
        for rule in panelRules(profileRules, balanced: balanced) {
            rules.append(GeodataSources.rewrite(rule, geodataSources))
        }
        if balanced {
            // The catch-all rides the balancer: whatever the bypass rules let
            // through, the core picks the member for.
            rules.append([
                "type": "field",
                "network": "tcp,udp",
                "balancerTag": balancerTag,
            ])
        }

        var routing: [String: Any] = [
            "domainStrategy": "AsIs",
            "rules": rules,
        ]
        if balanced {
            routing["balancers"] = [
                [
                    "tag": balancerTag,
                    // Every member tag carries the proxy prefix — the first is
                    // the plain tag itself — so the one selector covers them all.
                    "selector": [proxyTag],
                    "strategy": ["type": strategy],
                ],
            ]
        }
        return routing
    }

    /// The panel's routing rules rewritten onto this session's tags:
    /// direct-ish targets go to the session's freedom, block-ish to its
    /// blackhole, and everything the panel aimed at a proxy or balancer tag
    /// funnels to the one outbound that exists here — the balancer when the
    /// session runs one, the proxy otherwise.
    private static func panelRules(_ profileRules: String, balanced: Bool) -> [[String: Any]] {
        guard !profileRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        guard let data = profileRules.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return [] }
        let rawRules = array.compactMap { $0 as? [String: Any] }
        guard !rawRules.isEmpty else { return [] }

        return rawRules.map { rule in
            let target = JSONX.str(rule, "outboundTag") ?? JSONX.str(rule, "balancerTag") ?? ""
            var rewritten = rule
            rewritten.removeValue(forKey: "outboundTag")
            rewritten.removeValue(forKey: "balancerTag")
            switch target.trimmingCharacters(in: .whitespaces).lowercased() {
            case "direct", "freedom", "bypass":
                rewritten["outboundTag"] = directTag
            case "block", "blackhole":
                rewritten["outboundTag"] = blockTag
            default:
                if balanced {
                    rewritten["balancerTag"] = balancerTag
                } else {
                    rewritten["outboundTag"] = proxyTag
                }
            }
            return rewritten
        }
    }

    /// The member tags: the first member is the plain proxy tag — the default
    /// outbound a dead balancer falls back to — and the rest ride the proxy
    /// prefix, so the one balancer selector covers them all.
    private static func memberTag(_ index: Int) -> String {
        index == 0 ? proxyTag : "\(proxyTag)-\(index + 1)"
    }
}
