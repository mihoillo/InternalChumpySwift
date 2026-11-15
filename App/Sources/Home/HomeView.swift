import SwiftUI
import NetworkExtension
import ChumpyCore

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var now = Date()
    /// The live delay through the running tunnel; nil until measured.
    @State private var liveDelay: Int?
    @State private var liveDelayTask: Task<Void, Never>?

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavHost {
            VStack(spacing: 20) {
                profileCard
                connectButton
                if let error = appState.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                infoChips
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .navigationTitle("Chumpy")
        }
        .onReceive(ticker) { now = $0 }
        .onAppear { startLiveDelayIfUp() }
        .onChange(of: appState.status) { _ in startLiveDelayIfUp() }
        .onDisappear {
            liveDelayTask?.cancel()
            liveDelayTask = nil
        }
    }

    // MARK: - Live delay

    /// While the tunnel stands, the delay is the real thing: a plain
    /// request through the running core's own loopback SOCKS inbound, timed
    /// with a watch — the chip answers with the tunnel's own number, not a
    /// throwaway core's. Ported from the Android client's home ping chip.
    private func startLiveDelayIfUp() {
        liveDelayTask?.cancel()
        liveDelayTask = nil
        guard appState.status == .connected || appState.status == .reasserting
        else {
            liveDelay = nil
            return
        }
        liveDelayTask = Task {
            while !Task.isCancelled {
                liveDelay = await Self.measureLiveDelay()
                guard !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    static func measureLiveDelay() async -> Int? {
        var configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            kCFStreamPropertySOCKSProxyHost as String: "127.0.0.1",
            kCFStreamPropertySOCKSProxyPort as String: XrayConfigBuilder.localSocksPort,
        ]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let url = URL(string: ConnectionStore.current().testURL) else { return nil }
        let started = Date()
        do {
            let (_, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode)
            else { return nil }
            let millis = Int(Date().timeIntervalSince(started) * 1000)
            return millis
        } catch {
            return nil
        }
    }

    // MARK: - Profile card

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("home.selectedProfile")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(currentProfileName)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(statusColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .chumpyGlassCard()
        .padding(.horizontal, 20)
    }

    private var currentProfileName: String {
        if let profile = appState.store.selectedProfile() {
            return profile.remarks.isEmpty ? profile.server : profile.remarks
        }
        return String(localized: "home.noProfile", bundle: .main)
    }

    // MARK: - Connect button

    private var connectButton: some View {
        Button {
            Task { await appState.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .opacity(isActive ? 0.18 : 1)
                    .frame(width: 128, height: 128)
                Circle()
                    .strokeBorder(Chumpy.accent.opacity(isActive ? 0.9 : 0.35), lineWidth: 3)
                    .frame(width: 128, height: 128)
                if appState.status == .connecting || appState.status == .disconnecting {
                    ProgressView()
                        .scaleEffect(1.4)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: isActive ? "stop.fill" : "play.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Chumpy.accent)
                        Text(isActive ? "home.disconnect" : "home.connect")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Chumpy.accent)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(appState.isProcessing)
    }

    private var isActive: Bool {
        appState.status == .connected || appState.status == .reasserting
    }

    private var fillColor: Color {
        isActive ? Chumpy.accent : Color(.secondarySystemBackground)
    }

    private var statusText: LocalizedStringKey {
        switch appState.status {
        case .connected: return "home.status.connected"
        case .connecting: return "home.status.connecting"
        case .disconnecting: return "home.status.disconnecting"
        case .reasserting: return "home.status.reasserting"
        case .invalid: return "home.status.invalid"
        case .disconnected: return "home.status.disconnected"
        @unknown default: return "home.status.invalid"
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .connected, .reasserting: return .green
        case .connecting, .disconnecting: return .orange
        default: return .secondary
        }
    }

    // MARK: - Info chips

    private var infoChips: some View {
        HStack(spacing: 10) {
            InfoChip(icon: "clock", title: "home.uptime", value: uptimeText)
            InfoChip(icon: "arrow.down.arrow.up", title: "home.traffic", value: trafficText)
            InfoChip(icon: "bolt.horizontal", title: "home.ping", value: pingText)
        }
        .padding(.horizontal, 20)
    }

    private var pingText: String {
        guard let liveDelay else { return "—" }
        return "\(liveDelay) ms"
    }

    private var uptimeText: String {
        guard
            let connectedAt = ChumpyConstant.sharedDefaults
                .object(forKey: ChumpyConstant.Keys.connectedAt) as? Double,
            isActive || connectedAt > 0
        else { return "—" }
        let interval = now.timeIntervalSince1970 - connectedAt
        guard interval >= 0 else { return "—" }
        let mins = Int(interval) / 60
        let hours = mins / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, mins % 60)
        }
        return String(format: "%dm %02ds", mins, Int(interval) % 60)
    }

    private var trafficText: String {
        let bytes = ChumpyConstant.sharedDefaults
            .double(forKey: ChumpyConstant.Keys.statsBytesTotal)
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}

private struct InfoChip: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .chumpyGlassCard(cornerRadius: 16)
    }
}
