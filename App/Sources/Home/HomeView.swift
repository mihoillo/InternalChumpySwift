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
    /// True while the current error has already spoken its kicks.
    @State private var errorAnnounced = false

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
        // The connect button's floor: 16pt clear of the bar's top edge —
        // the same air the buttons keep between themselves (the bar
        // stands 12pt above the safe area and runs 64pt tall, so 76 +
        // 16 lands the button 16pt off the bar).
        .padding(.bottom, 92)
        .onReceive(ticker) { now = $0 }
        .onAppear {
            startLiveDelayIfUp()
            errorAnnounced = appState.lastError != nil
        }
        .onChange(of: appState.status) { oldStatus in
            // The connect result talks through the skin: a double poke
            // when the tunnel comes up, three grumpy kicks when it fails.
            if oldStatus == .connecting,
               appState.status == .connected || appState.status == .reasserting {
                Haptics.successPokes()
            }
            startLiveDelayIfUp()
        }
        .onChange(of: appState.lastError) { error in
            if error != nil {
                if !errorAnnounced {
                    errorAnnounced = true
                    Haptics.failureKicks()
                }
            } else {
                errorAnnounced = false
            }
        }
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

    /// The full-width 64pt capsule: primary fill when up, the calm tonal
    /// one when idle — the MD3 Expressive wavy bar inside carries the whole
    /// state. The bar keeps its own side insets so the wave's round caps
    /// never crowd the capsule's rounded ends.
    private var connectButton: some View {
        Button {
            Haptics.poke()
            Task { await appState.toggle() }
        } label: {
            WavyConnectBar(
                fill: connectFill,
                draining: appState.status == .disconnecting,
                // The wave is never black on the accent: white reads clean
                // on the loud fill in both themes, the accent itself rides
                // the calm tonal container when idle.
                color: isUp ? .white : Chumpy.accent,
                trackColor: (isUp ? .white : Chumpy.accent).opacity(0.30)
            )
            .padding(.horizontal, 28)
            .frame(height: 20)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                Capsule().fill(isUp ? Chumpy.accent : Chumpy.secondaryContainer)
            )
        }
        .buttonStyle(.plain)
        .disabled(appState.isProcessing)
    }

    private var connectFill: CGFloat {
        switch appState.status {
        case .connected, .reasserting, .connecting: return 1
        default: return 0
        }
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

// MARK: - Wavy connect bar

/// MD3 Expressive-style wavy progress bar, ported from the Android client's
/// `WavyConnectBar`: rounded caps everywhere, the wave travels continuously
/// (one wavelength per 1600 ms loop), the bar fills while connecting and
/// drains while disconnecting, a flat track behind the wave with a small gap.
struct WavyConnectBar: View {
    /// 0 when disconnected, 1 when connected — the fill target.
    let fill: CGFloat
    /// True while the tunnel is draining — the wave retreats to the right.
    var draining = false
    let color: Color
    let trackColor: Color

    /// The in-flight transition: where the fill started and when. Nil at
    /// rest, so the timeline pauses and the flat track stops drawing frames.
    @State private var animFrom: CGFloat = 0
    @State private var animStart: Date?
    private let fillDuration: TimeInterval = 0.6
    private var loopSeconds: TimeInterval { 1.6 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isSettled)) { timeline in
            Canvas { context, size in
                draw(
                    in: size,
                    fill: currentFill(at: timeline.date),
                    phase: phase(at: timeline.date),
                    context: context
                )
            }
        }
        .onAppear {
            animFrom = fill
            animStart = nil
        }
        .onChange(of: fill) { target in
            animFrom = currentFill(at: Date())
            animStart = Date()
        }
        // The settled flag rides the flight's own end: after the duration
        // the timeline pauses again (the flat track is a static line).
        .task(id: fill) {
            guard animStart != nil else { return }
            try? await Task.sleep(nanoseconds: UInt64(fillDuration * 1_100_000_000) + 50_000_000)
            animStart = nil
        }
    }

    private var isSettled: Bool {
        fill < 0.001 && animStart == nil
    }

    private func currentFill(at date: Date) -> CGFloat {
        guard let start = animStart else { return fill }
        let t = min(1, date.timeIntervalSince(start) / fillDuration)
        let eased = 1 - pow(1 - t, 2)
        return animFrom + (fill - animFrom) * eased
    }

    private func phase(at date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loopSeconds) / loopSeconds)
    }

    private func draw(in size: CGSize, fill: CGFloat, phase: CGFloat, context: GraphicsContext) {
        let centerY = size.height / 2
        let stroke: CGFloat = 6
        let amplitude: CGFloat = 5
        let wavelength: CGFloat = 28
        let gap: CGFloat = 4
        let phasePx = phase * wavelength
        let inset = stroke / 2
        // The round cap reaches stroke/2 beyond the path's own end. Give the
        // wave its own side margins: the canvas paints inside its bounds, so
        // a path ending at 0 or the edge gets its cap sliced flat — exactly
        // the cut ends a full-width wave used to show. Everything draws in
        // the inset content strip; the outer canvas keeps the margin.
        let width = size.width - stroke
        var striped = context
        striped.translateBy(x: inset, y: 0)
        let wavyStroke = StrokeStyle(lineWidth: stroke, lineCap: .round)

        func wavePath(from x0: CGFloat, to x1: CGFloat, amplitude amp: CGFloat) -> Path {
            var path = Path()
            var x = x0
            // Start on the curve, not on the center line — otherwise the
            // left end bends towards the middle.
            var y = centerY + amp * CGFloat(sin(2 * .pi * (x + phasePx) / wavelength))
            path.move(to: CGPoint(x: x, y: y))
            let step = wavelength / 16
            while x < x1 {
                x = min(x + step, x1)
                y = centerY + amp * CGFloat(sin(2 * .pi * (x + phasePx) / wavelength))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            return path
        }

        func flatTrack(from x0: CGFloat, to x1: CGFloat) {
            guard x1 - x0 > inset else { return }
            var path = Path()
            path.move(to: CGPoint(x: max(x0, 0), y: centerY))
            path.addLine(to: CGPoint(x: min(x1, width), y: centerY))
            striped.stroke(path, with: .color(trackColor), style: wavyStroke)
        }

        if fill >= 0.999 {
            // All wave, all the way across.
            striped.stroke(
                wavePath(from: 0, to: width, amplitude: amplitude),
                with: .color(color),
                style: wavyStroke
            )
        } else if fill <= 0.001 {
            // Drained: the flat track alone.
            flatTrack(from: 0, to: width)
        } else if draining {
            // The wave retreats to the right and exits at the right edge.
            let left = width * (1 - fill)
            flatTrack(from: 0, to: left - gap)
            striped.stroke(
                wavePath(from: left, to: width, amplitude: amplitude),
                with: .color(color),
                style: wavyStroke
            )
        } else {
            // Filling up from the left, the track behind it.
            let right = width * fill
            flatTrack(from: right + gap, to: width)
            striped.stroke(
                wavePath(from: 0, to: right, amplitude: amplitude),
                with: .color(color),
                style: wavyStroke
            )
        }
    }
}
