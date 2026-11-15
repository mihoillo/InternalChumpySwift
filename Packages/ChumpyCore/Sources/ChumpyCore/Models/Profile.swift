import Foundation
import CryptoKit

/// Proxy protocol kinds a profile can carry. The raw values match the Android
/// client's enum names (used inside the link key digest).
public enum ProfileType: String, Codable, CaseIterable {
    case vmess = "VMESS"
    case vless = "VLESS"
    case trojan = "TROJAN"
    case shadowsocks = "SHADOWSOCKS"
    case socks = "SOCKS"
    case wireguard = "WIREGUARD"
    case hysteria2 = "HYSTERIA2"
    /// Not a server: a routing balancer over the subscription's other profiles.
    case balancer = "BALANCER"
}

/// One server, imported from a subscription link or a manual paste. The fields
/// follow the link formats' own vocabulary (transport in `network`/`host`/`path`,
/// security in `security`/`sni`/…), flat and denormalized on purpose — ported
/// 1:1 from the Android client's `ProfileEntity`.
public struct Profile: Codable, Equatable, Identifiable, Hashable {

    public var id: String
    /// Owning subscription, or nil for a manually pasted profile.
    public var subscriptionID: String?
    public var type: ProfileType
    public var remarks: String = ""
    /// Position within the subscription, kept stable across updates.
    public var order: Int = 0
    /// The share link the profile was born from, verbatim; nil for configs.
    public var sourceLink: String?

    // Endpoint and authentication.
    public var server: String = ""
    public var serverPort: Int = 0
    /// VMess UUID, VLESS id, Trojan/SS/Hy2 password, SOCKS pass.
    public var password: String = ""
    /// SS cipher; VMess security; VLESS encryption.
    public var method: String = ""
    /// SOCKS user.
    public var username: String = ""

    // Transport.
    public var network: String = "tcp"
    public var headerType: String = ""
    public var host: String = ""
    public var path: String = ""
    /// KCP seed.
    public var seed: String = ""
    /// gRPC service name.
    public var serviceName: String = ""
    /// gRPC authority.
    public var authority: String = ""
    /// gRPC multi / XHTTP mode.
    public var mode: String = ""
    /// XHTTP extra JSON, passed through verbatim.
    public var xhttpExtra: String?

    // TLS / REALITY.
    /// "", "tls" or "reality".
    public var security: String = ""
    public var sni: String = ""
    /// Comma-separated ALPN list, as links carry it.
    public var alpn: String = ""
    public var fingerprint: String = ""
    public var flow: String = ""
    public var allowInsecure: Bool = false
    /// REALITY public key (WireGuard peer key on WIREGUARD profiles).
    public var publicKey: String = ""
    public var shortID: String = ""
    public var spiderX: String = ""

    // Hysteria2.
    public var obfsPassword: String = ""
    public var portHopping: String = ""
    public var portHoppingInterval: String = ""

    // WireGuard.
    public var wgSecretKey: String = ""
    public var wgPresharedKey: String = ""
    /// Comma-separated interface addresses.
    public var wgLocalAddress: String = ""
    public var wgMTU: Int = 0
    /// "1,2,3"-style client reserved bytes.
    public var wgReserved: String = ""

    // Balancer (BALANCER profiles only).
    /// The Xray strategy: random, roundrobin, leastping or leastload.
    public var balancerStrategy: String = ""
    /// The members' linkKeys, newline-joined.
    public var balancerMembers: String = ""

    // Routing (profiles imported from raw configs).
    /// The routing rules the panel's own config carried, as a raw JSON array.
    public var routingRules: String = ""
    public var geodataSources: String = ""

    /// The balancer's internal rows stay in the store but not in the list.
    public var hidden: Bool = false

    // Measurements / state (ride identity through subscription updates).
    /// The last real ping through the core, in millis; nil when never measured.
    public var testDelayMillis: Int64?
    public var lastTestAt: Date?
    public var lastUsedAt: Date?
    public var pinned: Bool = false
    /// The user's own hide — stays in the store, out of the list.
    public var concealed: Bool = false

    /// A digest of everything that defines the server. Subscription updates
    /// diff on it: a profile whose linkKey survives keeps identity and state.
    public var linkKey: String = ""

    public init(
        id: String = "",
        subscriptionID: String? = nil,
        type: ProfileType
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.type = type
    }

    /// Computes the canonical link key digest (SHA-256).
    public func computeLinkKey() -> String {
        let canonical: String
        if type == .balancer {
            canonical = [type.rawValue, remarks, balancerStrategy].joined(separator: "\u{01}")
        } else {
            let parts: [String] = [
                type.rawValue,
                server,
                String(serverPort),
                password,
                method,
                username,
                network,
                headerType,
                host,
                path,
                seed,
                serviceName,
                authority,
                mode,
                xhttpExtra ?? "",
                security,
                sni,
                alpn,
                fingerprint,
                flow,
                String(allowInsecure),
                publicKey,
                shortID,
                spiderX,
                obfsPassword,
                portHopping,
                portHoppingInterval,
                wgSecretKey,
                wgPresharedKey,
                wgLocalAddress,
                String(wgMTU),
                wgReserved,
            ]
            canonical = parts.joined(separator: "\u{01}")
        }
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The balancer's member linkKeys, in column order.
    public var balancerMemberKeys: [String] {
        balancerMembers.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// The endpoint in host:port form, IPv6 bracketed.
    public var endpoint: String {
        "\(LinkUtils.ipv6Brackets(server)):\(serverPort)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case subscriptionID
        case type
        case remarks
        case order
        case sourceLink
        case server
        case serverPort
        case password
        case method
        case username
        case network
        case headerType
        case host
        case path
        case seed
        case serviceName
        case authority
        case mode
        case xhttpExtra
        case security
        case sni
        case alpn
        case fingerprint
        case flow
        case allowInsecure
        case publicKey
        case shortID
        case spiderX
        case obfsPassword
        case portHopping
        case portHoppingInterval
        case wgSecretKey
        case wgPresharedKey
        case wgLocalAddress
        case wgMTU
        case wgReserved
        case balancerStrategy
        case balancerMembers
        case routingRules
        case geodataSources
        case hidden
        case testDelayMillis
        case lastTestAt
        case lastUsedAt
        case pinned
        case concealed
        case linkKey
    }
}
