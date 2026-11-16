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

/// The connect button's own glass. The color rides under the glass, not on
/// it: two streams of soft color waves enter from the left and right edges —
/// the refraction at the rim — and travel toward the center, wobbling as
/// they go, brightening where they meet. Over them stands the glass itself:
/// stock Liquid Glass on iOS 26, plain frosted matte below — the waves read
/// through the material the way light reads through frosted glass.
///
/// The waves always drift at one constant speed, so the motion never jumps
/// when the state flips — only the intensity animates, which SwiftUI does
/// natively: dim while idle, full strength once the tunnel stands.
struct LiquidConnectBar: View {
    let isUp: Bool

    private struct Wave {
        let color: Color
        /// Where in the loop this wave stands, 0…1.
        let offset: Double
        /// The vertical wobble's own frequency and phase.
        let yFreq: Double
        let yPhase: Double
    }

    /// The left stream's palette and the right's — different hues per side
    /// so the two fronts read as two refractions meeting.
    private let leftWaves: [Wave] = [
        Wave(color: Chumpy.accent, offset: 0.00, yFreq: 3, yPhase: 0.0),
        Wave(color: .teal, offset: 0.33, yFreq: 4, yPhase: 1.3),
        Wave(color: .purple, offset: 0.66, yFreq: 3, yPhase: 2.6),
    ]
    private let rightWaves: [Wave] = [
        Wave(color: .pink, offset: 0.16, yFreq: 3, yPhase: 0.7),
        Wave(color: .blue, offset: 0.50, yFreq: 4, yPhase: 2.0),
        Wave(color: .orange, offset: 0.83, yFreq: 3, yPhase: 4.1),
    ]

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                Canvas { context, size in
                    draw(timeline: timeline, size: size, context: context)
                }
                .blur(radius: 6)
            }
            // Idle the refraction stays a quiet undertone; connected it
            // comes up to full strength.
            .opacity(isUp ? 1.0 : 0.38)

            glassLayer
        }
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.7), value: isUp)
    }

    /// The glass itself: stock Liquid Glass on iOS 26, plain frosted matte
    /// below — no painted rims, no fake speculars.
    @ViewBuilder
    private var glassLayer: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(in: Capsule())
        } else {
            Capsule().fill(.regularMaterial)
        }
        #else
        Capsule().fill(.regularMaterial)
        #endif
    }

    /// One wave's whole run: born at its edge, gliding to the center,
    /// wobbling on its own frequency, fading out as the two fronts meet.
    private func draw(timeline: TimelineViewDefaultContext, size: CGSize, context: GraphicsContext) {
        // Light composites as light: the waves add onto each other where
        // they overlap — the meeting point at the center glows.
        context.blendMode = .plusLighter
        let width = size.width
        let height = size.height
        // One edge-to-center run takes ~2.8 s; three waves per side keep a
        // front arriving roughly every second.
        let t = timeline.date.timeIntervalSinceReferenceDate * 0.35

        for (direction, waves) in [(CGFloat(1), leftWaves), (CGFloat(-1), rightWaves)] {
            let edgeX = direction > 0 ? CGFloat(0) : width
            for wave in waves {
                let progress = (t + wave.offset).truncatingRemainder(dividingBy: 1)
                let x = edgeX + direction * CGFloat(progress) * width * 0.5
                // Born at the rim, dead at the center — the fade-ins keep
                // the birth at the edge soft, the fade-outs let the two
                // fronts dissolve into each other where they meet.
                let alpha = min(progress * 5, 1) * min((1 - progress) * 6, 1)
                let y = height / 2
                    + CGFloat(sin(progress * .pi * wave.yFreq + wave.yPhase)) * height * 0.15
                let radius = height * 0.38
                let rect = CGRect(
                    x: x - radius, y: y - radius, width: radius * 2, height: radius * 2
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(colors: [
                            wave.color.opacity(0.85 * alpha),
                            wave.color.opacity(0),
                        ]),
                        center: CGPoint(x: x, y: y),
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
    }
}
