import Foundation
import NetworkExtension
import Darwin
import os
import ChumpyCore
import SwiftyXrayKit

/// The packet tunnel provider: runs Xray inside the Network Extension and
/// bridges the VPN packet flow to Xray's built-in gVisor TUN stack.
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private var bridge: XrayBridge?
    private var statsTimer: DispatchSourceTimer?
    /// The minute's deltas accumulated before the daily bucket write.
    private var pendingRx: Int64 = 0
    private var pendingTx: Int64 = 0
    private var statsTicks = 0
    private let dailyTraffic = DailyTrafficStore()
    private let logger = Logger(subsystem: "slop.miho.chumpy.swift.tunnel", category: "core")

    private enum TunnelError: LocalizedError {
        case noConfiguration

        var errorDescription: String? {
            switch self {
            case .noConfiguration:
                return "No tunnel configuration found. Open Chumpy and select a server."
            }
        }
    }

    // MARK: - Tunnel lifecycle

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let defaults = ChumpyConstant.sharedDefaults
        guard
            let configJSON = defaults.string(forKey: ChumpyConstant.Keys.tunnelConfigJSON),
            !configJSON.isEmpty
        else {
            completionHandler(TunnelError.noConfiguration)
            return
        }

        ChumpyConstant.ensureDirectories()
        ChumpyLog.shared.append("tunnel starting…")
        let profileName = defaults.string(forKey: ChumpyConstant.Keys.tunnelProfileName) ?? "—"

        setTunnelNetworkSettings(Self.makeNetworkSettings()) { [weak self] error in
            guard let self else {
                completionHandler(error)
                return
            }
            if let error {
                ChumpyLog.shared.append("network settings failed: \(error.localizedDescription)")
                completionHandler(error)
                return
            }

            let bridge = XrayBridge(packetFlow: self.packetFlow)
            let sniffing = SniffingConfiguration(
                destOverride: ["http", "tls", "quic"],
                enabled: true,
                routeOnly: false,
                domainsExcluded: [],
                metadataOnly: false
            )
            do {
                try bridge.start(
                    config: .json(configJSON),
                    dataDir: ChumpyConstant.dataDir,
                    finalConfigPath: ChumpyConstant.tunnelConfigPath,
                    sniffing: sniffing,
                    preset: .mobile,
                    traceHandle: { line in
                        ChumpyLog.shared.append(line)
                    }
                )
                self.bridge = bridge
                self.startStatsPolling()
                ChumpyLog.shared.append("tunnel up (\(profileName))")
                completionHandler(nil)
            } catch {
                ChumpyLog.shared.append("xray start failed: \(error.localizedDescription)")
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        stopStatsPolling()
        bridge?.stop()
        bridge = nil
        ChumpyLog.shared.append("tunnel down (reason \(reason.rawValue))")
        completionHandler()
    }

    // MARK: - Stats

    private func startStatsPolling() {
        let queue = DispatchQueue(label: "slop.miho.chumpy.swift.tunnel.stats")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, let bridge = self.bridge else { return }
            let delta = bridge.getAndClearStats()
            let defaults = ChumpyConstant.sharedDefaults
            let total = defaults.double(forKey: ChumpyConstant.Keys.statsBytesTotal)
            defaults.set(
                total + Double(delta.received + delta.sent),
                forKey: ChumpyConstant.Keys.statsBytesTotal
            )
            defaults.set(Date().timeIntervalSince1970, forKey: ChumpyConstant.Keys.statsUpdatedAt)

            // The week's buckets: a write a minute at most — the deltas
            // accumulate in memory and flush as the session runs.
            self.pendingRx += delta.received
            self.pendingTx += delta.sent
            self.statsTicks += 1
            if self.statsTicks >= 60 {
                self.flushDailyTraffic()
            }
        }
        timer.resume()
        statsTimer = timer
    }

    private func stopStatsPolling() {
        statsTimer?.cancel()
        statsTimer = nil
        flushDailyTraffic()
    }

    /// Folds the minute's deltas into today's bucket — the stats screen's
    /// weekly chart survives restarts and disconnected days.
    private func flushDailyTraffic() {
        guard pendingRx > 0 || pendingTx > 0 else {
            statsTicks = 0
            return
        }
        dailyTraffic.addToday(rx: pendingRx, tx: pendingTx)
        pendingRx = 0
        pendingTx = 0
        statsTicks = 0
    }

    // MARK: - Network settings
    // Ported from the SwiftyXrayKit example: pick an unused 10.x.5.2 address.

    static func makeNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let taken = enumerateInterfaceIPv4Addresses()
        var net = 5
        while taken.contains(where: { $0.hasPrefix("10.\(net).") }) {
            net += 1
        }
        let localIP = "10.\(net).5.2"

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = 1360

        let ipv4 = NEIPv4Settings(addresses: [localIP], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = [
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
        ]
        settings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        settings.dnsSettings = dns
        return settings
    }

    private static func enumerateInterfaceIPv4Addresses() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            guard
                (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING),
                let addrPtr = current.pointee.ifa_addr
            else { continue }

            var addr = addrPtr.pointee
            guard addr.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(addr.sa_len)
            if getnameinfo(&addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: host))
            }
        }
        return result
    }
}
