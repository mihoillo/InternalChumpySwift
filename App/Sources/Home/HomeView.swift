import SwiftUI
import NetworkExtension
import ChumpyCore

/// Home, ported from the Android client's `HomeScreen` — monolithic, the
/// way the phone wears it: "Chumpy" and the big hour greeting, the info
/// chips flow, the error card, the server card, all anchored above the
/// connect button; no scroll anywhere, the column is one solid block.
struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    var onOpenServers: () -> Void

    @State private var now = Date()
    /// The live delay through the running tunnel; nil until measured.
    @State private var liveDelay: Int?
    @State private var liveDelayTask: Task<Void, Never>?
    /// The ping chip's own re-measure: "…" until the new value lands.
    @State private var measuringPing = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The flexible air above: everything below hangs as one solid
            // block off the bottom of the screen.
            Spacer(minLength: 12)

            Text("Chumpy")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text(greetingText)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.primary)
                .padding(.top, 4)

            Spacer().frame(height: 16)
            infoChips

            Spacer().frame(height: 12)
            if let error = appState.lastError {
                ErrorCard(message: error)
            }
            if let profile = appState.store.selectedProfile() {
                ServerCard(
                    subscription: subscriptionName(for: profile),
                    title: profile.remarks.isEmpty ? profile.server : profile.remarks,
                    flag: leadingFlagEmoji(
                        profile.remarks.isEmpty ? profile.server : profile.remarks
                    ),
                    onClick: onOpenServers
                )
            }

            Spacer().frame(height: 16)
            connectButton
        }
        .padding(.horizontal, 20)
        .onReceive(ticker) { now = $0 }
        .onAppear { startLiveDelayIfUp() }
        .onChange(of: appState.status) { _ in startLiveDelayIfUp() }
        .onDisappear {
            liveDelayTask?.cancel()
            liveDelayTask = nil
        }
    }

    // MARK: - Greeting

    /// The hour-based greeting, the Chumpy way: morning, afternoon,
    /// evening, night.
    private var greetingText: LocalizedStringKey {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5...11: return "greeting.morning"
        case 12...16: return "greeting.afternoon"
        case 17...22: return "greeting.evening"
        default: return "greeting.night"
        }
    }

    // MARK: - Info chips

    private var infoChips: some View {
        FlowStack(spacing: 4) {
            statusChip
            if isSubscriptionExpired {
                InfoChip(
                    value: String(localized: "subscription.expired.chip", bundle: .main),
                    container: Chumpy.errorContainer,
                    content: Color.red
                )
            }
            if isUp {
                InfoChip(
                    value: uptimeText,
                    icon: "clock",
                    content: .primary
                )
                pingChip
            }
        }
    }

    /// A plain status dot: filled with the accent when connected, hollow
    /// when not — riding the state's own label.
    private var statusChip: some View {
        InfoChip(
            value: stateLabel,
            container: isUp ? Chumpy.secondaryContainer : Chumpy.surfaceContainerLow,
            content: isUp ? Color.accentColor : Color.secondary,
            leading: AnyView(
                ZStack {
                    Circle()
                        .fill(isUp ? Color.accentColor : .clear)
                        .frame(width: 10, height: 10)
                    if !isUp {
                        Circle()
                            .strokeBorder(Color.secondary, lineWidth: 1.5)
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.leading, 2)
            )
        )
    }

    /// 200 ms is where the server starts feeling far away: the chip goes
    /// red from there. A tap re-measures on the spot — "…" until the new
    /// value lands. Ported from the Android client's home ping chip.
    private var pingChip: some View {
        let pingSlow = (liveDelay ?? 0) >= 200
        return InfoChip(
            value: pingChipValue,
            container: pingSlow ? Chumpy.errorContainer : Chumpy.surfaceContainerLow,
            content: pingSlow ? Color.red : Color.primary,
            animateValue: true,
            action: {
                guard !measuringPing else { return }
                measuringPing = true
                liveDelay = nil
                Task {
                    let measured = await Self.measureLiveDelay()
                    liveDelay = measured
                    measuringPing = false
                }
            }
        )
    }

    private var pingChipValue: String {
        if measuringPing { return "…" }
        if let liveDelay { return "\(liveDelay) ms" }
        return "…"
    }

    // MARK: - State

    private var isUp: Bool {
        appState.status == .connected || appState.status == .reasserting
    }

    private var stateLabel: String {
        let key: String
        switch appState.status {
        case .connected, .reasserting: key = "home.state.up"
        case .connecting: key = "home.state.connecting"
        case .disconnecting: key = "home.state.disconnecting"
        case .invalid, .disconnected: key = "home.state.down"
        @unknown default: key = "home.state.down"
        }
        return NSLocalizedString(key, bundle: .main, comment: "")
    }

    private var uptimeText: String {
        guard
            let connectedAt = ChumpyConstant.sharedDefaults
                .object(forKey: ChumpyConstant.Keys.connectedAt) as? Double,
            isUp
        else { return "…" }
        let interval = max(now.timeIntervalSince1970 - connectedAt, 0)
        let totalSeconds = Int(interval)
        return String(
            format: "%d:%02d:%02d",
            totalSeconds / 3600,
            (totalSeconds % 3600) / 60,
            totalSeconds % 60
        )
    }

    private var selectedSubscription: SubscriptionEntity? {
        guard let profile = appState.store.selectedProfile(),
              let subID = profile.subscriptionID
        else { return nil }
        return appState.store.subscription(byID: subID)
    }

    private var isSubscriptionExpired: Bool {
        guard let sub = selectedSubscription, sub.expireEpochSeconds > 0 else { return false }
        return Double(sub.expireEpochSeconds) < now.timeIntervalSince1970
    }

    private func subscriptionName(for profile: Profile) -> String? {
        guard let subID = profile.subscriptionID,
              let sub = appState.store.subscription(byID: subID),
              !sub.name.isEmpty
        else { return nil }
        return sub.name
    }

    /// The flag the panel put at the front of the name rides the icon slot,
    /// the way the country flags do — anything else keeps the globe.
    private func leadingFlagEmoji(_ name: String) -> String? {
        let scalars = Array(name.unicodeScalars.prefix(2))
        guard scalars.count == 2,
              (0x1F1E6...0x1F1FF).contains(scalars[0].value),
              (0x1F1E6...0x1F1FF).contains(scalars[1].value)
        else { return nil }
        return "\(scalars[0])\(scalars[1])"
    }

    // MARK: - Live delay

    /// While the tunnel stands, the delay is the real thing: a plain
    /// request through the running core's own loopback SOCKS inbound, timed
    /// with a watch — the chip answers with the tunnel's own number.
    private func startLiveDelayIfUp() {
        liveDelayTask?.cancel()
        liveDelayTask = nil
        guard isUp else {
            liveDelay = nil
            measuringPing = false
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

    // MARK: - Connect button

    /// The full-width 64pt capsule: the liquid glass bar inside carries
    /// the whole state — Siri-style color refraction swirling in the glass,
    /// dim and slow while idle, vivid once the tunnel stands.
    private var connectButton: some View {
        Button {
            Task { await appState.toggle() }
        } label: {
            LiquidConnectBar(isUp: isUp)
                .frame(height: 64)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(appState.isProcessing)
    }
}

// MARK: - Error card

/// The failed connect's own report: the error text on the error tonal card,
/// a small warning leading. Ported from the Android client's `ErrorCard`.
struct ErrorCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Chumpy.errorContainer)
        )
    }
}

// MARK: - Server card

/// The picked server's own identity on home: the 28dp tonal card, the 40dp
/// tile with the flag (or the globe), "subscription →" over the region, a
/// bare chevron — a tap away from the list that changes it.
struct ServerCard: View {
    let subscription: String?
    let title: String
    let flag: String?
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Chumpy.secondaryContainer)
                        .frame(width: 40, height: 40)
                    if let flag {
                        Text(flag)
                            .font(.system(size: 22))
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    if let subscription {
                        Text("\(subscription) →")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .chumpyCard()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Liquid connect bar

/// The connect button's own glass: Siri-style color refraction — a handful
/// of glowing color blobs drifting through the capsule on lissajous paths,
/// composited `plusLighter` over the base so they read as light bending in
/// liquid glass. Idle the glass stays calm and dim; connected the light
/// comes up at full strength. The blobs always drift at one constant speed,
/// so the motion never jumps when the state flips — only the brightness
/// animates, which SwiftUI does natively.
struct LiquidConnectBar: View {
    let isUp: Bool

    private struct Blob {
        let color: Color
        let fx: Double
        let fy: Double
        let px: Double
        let py: Double
        let radius: CGFloat
    }

    /// The palette the glass refracts: the accent plus its neighbors, with a
    /// white specular riding along.
    private let blobs: [Blob] = [
        Blob(color: Chumpy.accent, fx: 0.90, fy: 1.30, px: 0.0, py: 1.7, radius: 0.90),
        Blob(color: .purple, fx: 1.10, fy: 0.70, px: 2.1, py: 4.2, radius: 1.00),
        Blob(color: .pink, fx: 0.60, fy: 1.70, px: 3.9, py: 0.6, radius: 0.80),
        Blob(color: .teal, fx: 1.40, fy: 0.90, px: 5.0, py: 2.8, radius: 0.85),
        Blob(color: .blue, fx: 0.80, fy: 1.10, px: 1.2, py: 5.5, radius: 0.95),
        Blob(color: .white, fx: 1.20, fy: 1.50, px: 4.4, py: 3.3, radius: 0.45),
    ]

    var body: some View {
        ZStack {
            Capsule()
                .fill(baseColor)

            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                Canvas { context, size in
                    // Light composites as light: the blobs add onto the base
                    // the way glow adds in glass.
                    context.blendMode = .plusLighter
                    let t = timeline.date.timeIntervalSinceReferenceDate * 0.7
                    for blob in blobs {
                        let x = size.width * (0.5 + 0.38 * CGFloat(sin(t * blob.fx + blob.px)))
                        let y = size.height * (0.5 + 0.55 * CGFloat(sin(t * blob.fy + blob.py)))
                        let r = size.height * blob.radius
                        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .radialGradient(
                                Gradient(colors: [blob.color.opacity(0.55), blob.color.opacity(0)]),
                                center: CGPoint(x: x, y: y),
                                startRadius: 0,
                                endRadius: r
                            )
                        )
                    }
                }
                .blur(radius: 10)
            }
            // Idle the refraction stays a quiet undertone; connected it
            // comes up to full strength.
            .opacity(isUp ? 1.0 : 0.35)

            // The glass's own edge: a hairline rim and the specular the
            // light leaves along the top.
            Capsule()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.16), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.7), value: isUp)
    }

    /// Connected the glass darkens so the light in it carries the state;
    /// idle it keeps the calm tonal surface.
    private var baseColor: Color {
        isUp ? Color.black.opacity(0.45) : Chumpy.surfaceContainer
    }
}
