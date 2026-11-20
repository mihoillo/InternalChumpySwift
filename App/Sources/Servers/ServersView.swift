import SwiftUI
import UIKit
import ChumpyCore

/// Servers tab, ported from the Android client's `ServersScreen` layout:
/// the subscription card with the database tile, the centered chips header
/// (total / expired / concealed / sort), and the grouped rows — one
/// continuous card, the subscription card's very shape, its rows divided
/// by the system's own hairlines; the standing row's light falls softly
/// onto its neighbors. Pull-to-refresh runs the real-ping sweep.
struct ServersView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = ServersViewModel()
    @State private var showSubscriptionChooser = false
    /// The add dialog's own state — one field, three answers.
    @State private var showAddDialog = false
    @State private var addInput = ""
    @State private var addBusy = false
    @State private var addError: String?

    var body: some View {
        ZStack {
            Group {
                if model.profiles.isEmpty && model.subscriptions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            if showAddDialog {
                addDialog
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: showAddDialog)
        .onAppear {
            model.tunnelUp = {
                appState.status == .connected || appState.status == .reasserting
            }
            model.reload()
        }
        .sheet(isPresented: $showSubscriptionChooser) {
            SubscriptionChooserSheet(model: model) {
                showAddDialog = true
            }
        }
    }

    // MARK: - List

    private var list: some View {
        EdgeScrollView(tag: "servers", onRefresh: {
            await model.pingServers()
        }) {
            VStack(spacing: 12) {
                if let error = model.error {
                    ErrorCard(message: error)
                }
                if let sub = model.selectedSubscription {
                    SubscriptionCard(subscription: sub, model: model)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // The card's own tap asks which group to show —
                            // the chooser sheet with the thick rows.
                            Haptics.poke()
                            showSubscriptionChooser = true
                        }
                }
                header
                rows
            }
            .padding(.horizontal, 16)
            .padding(.top, chumpyContentTopPadding)
            .padding(.bottom, 104)
        }
    }

    // MARK: - Header chips

    /// The centered chips row: the total (a tap runs the ping sweep), the
    /// expired badge, the concealed count (the reveal mode's door), the
    /// standing sort mode with its small menu of the four.
    private var header: some View {
        FlowStack(alignment: .center, spacing: 4) {
            if !model.profiles.isEmpty {
                InfoChip(
                    value: String(
                        format: NSLocalizedString("servers.total", bundle: .main, comment: ""),
                        model.profiles.count
                    ),
                    icon: "square.stack.3d.up",
                    animateValue: true,
                    action: {
                        Task { await model.pingServers() }
                    }
                )
                .overlay {
                    if model.isPinging {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
            if isSubscriptionExpired {
                InfoChip(
                    value: String(localized: "subscription.expired.chip", bundle: .main),
                    container: Chumpy.errorContainer,
                    content: Color.red
                )
            }
            if model.concealedCount > 0 {
                InfoChip(
                    value: "\(model.concealedCount)",
                    icon: model.includeConcealed ? "eye" : "eye.slash",
                    animateValue: true,
                    action: {
                        model.setRevealConcealed(!model.includeConcealed)
                    }
                )
            }
            if !model.profiles.isEmpty {
                Menu {
                    ForEach(ServersSort.allCases) { mode in
                        sortMenuButton(mode)
                    }
                } label: {
                    InfoChip(
                        value: NSLocalizedString(
                            model.sort.localizationKey, bundle: .main, comment: ""
                        ),
                        icon: "arrow.up.arrow.down"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sortMenuButton(_ mode: ServersSort) -> some View {
        Button {
            Haptics.poke()
            model.setSort(mode)
        } label: {
            if mode == model.sort {
                Label(
                    NSLocalizedString(mode.localizationKey, bundle: .main, comment: ""),
                    systemImage: "checkmark"
                )
            } else {
                Text(NSLocalizedString(mode.localizationKey, bundle: .main, comment: ""))
            }
        }
    }

    // MARK: - Rows

    private var rows: some View {
        let total = model.profiles.count
        // The rows butt flush — no gap between them, the way the native
        // inset lists wear their one continuous card; the seams carry
        // the hairlines instead.
        return VStack(spacing: 0) {
            ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                ServerGroupRow(
                    profile: profile,
                    isFirst: index == 0,
                    isLast: index == total - 1,
                    isSelected: isSelected(profile),
                    glowsFromTop: index > 0 && isSelected(model.profiles[index - 1]),
                    glowsFromBottom: index < total - 1 && isSelected(model.profiles[index + 1]),
                    tunnelUp: appState.status == .connected || appState.status == .reasserting,
                    onSelect: { select(profile) },
                    onDelete: { model.deleteManualProfile(profile.id) },
                    onTogglePinned: { model.togglePinned(profile) },
                    onToggleConcealed: { model.setConcealed(profile, concealed: !profile.concealed) },
                    onTest: { Task { await model.pingOne(profile) } }
                )
            }
        }
    }

    private func isSelected(_ profile: Profile) -> Bool {
        let picked = ConnectionStore.current().selectedProfileID
        if let picked { return picked == profile.id }
        return model.profiles.first?.id == profile.id
    }

    private func select(_ profile: Profile) {
        Task {
            await appState.selectProfile(id: profile.id)
            model.reload()
        }
    }

    private var isSubscriptionExpired: Bool {
        guard let sub = model.selectedSubscription, sub.expireEpochSeconds > 0 else {
            return false
        }
        return Double(sub.expireEpochSeconds) < Date().timeIntervalSince1970
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("servers.empty.title")
                .font(.headline)
            Text("servers.empty.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAddDialog = true
            } label: {
                Label("servers.add.subscription", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Chumpy.secondaryContainer))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, chumpyContentTopPadding)
        .padding(.bottom, 104)
        .frame(maxWidth: .infinity)
        // The empty page doesn't scroll, so it speaks the metrics itself:
        // no travel, nothing below the fold — both frosts stay asleep.
        .onAppear {
            ScrollReporter.shared.report(ScrollMetrics(tag: "servers"))
        }
    }

    // MARK: - The add dialog

    /// The add door: a dialog card over a dimmed veil — one text field,
    /// three answers. Add takes a subscription URL or pasted share
    /// links (the model tells them apart); paste fills the field from
    /// the clipboard; cancel folds the veil away.
    private var addDialog: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    Haptics.poke()
                    closeAddDialog()
                }

            VStack(spacing: 14) {
                Text("servers.add.subscription")
                    .font(.system(size: 16, weight: .semibold))

                TextField("servers.add.urlPlaceholder", text: $addInput)
                    .font(.system(size: 15))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Chumpy.surfaceContainerLow)
                    )

                if let addError {
                    Text(addError)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 8) {
                    Button {
                        Haptics.poke()
                        pasteFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 44, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Chumpy.secondaryContainer)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.poke()
                        closeAddDialog()
                    } label: {
                        Text("common.cancel")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Capsule().fill(Chumpy.secondaryContainer))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.poke()
                        submitAdd()
                    } label: {
                        Group {
                            if addBusy {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("common.add")
                            }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Chumpy.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Capsule().fill(Chumpy.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .opacity(!canSubmit ? 0.5 : 1)
                }
            }
            .padding(20)
            .frame(maxWidth: 340)
            .chumpyCard()
        }
    }

    private var canSubmit: Bool {
        !addBusy && !addInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The clipboard's own word into the field — appended as its own
    /// line when the field already holds one.
    private func pasteFromClipboard() {
        guard let pasted = UIPasteboard.general.string else { return }
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let field = addInput.trimmingCharacters(in: .whitespacesAndNewlines)
        addInput = field.isEmpty ? trimmed : field + "\n" + trimmed
    }

    /// The dialog's own answer: the model tells a subscription URL from
    /// pasted share links — a http(s) link fetches as a subscription,
    /// anything else lands as manual configs.
    private func submitAdd() {
        guard canSubmit else { return }
        addBusy = true
        addError = nil
        Task {
            await model.addSubscription(url: addInput) { failure in
                addBusy = false
                if let failure {
                    addError = failure
                } else {
                    closeAddDialog()
                }
            }
        }
    }

    private func closeAddDialog() {
        addError = nil
        showAddDialog = false
    }
}

// MARK: - Subscription card

/// The subscription card, the Android client's report face: the square
/// home-storage tile with the update button underneath on the left, the
/// report on the right — the name with the last-update stamp in one line,
/// then one bar for whichever runs dry first (the quota's runway over the
/// week's own pace, or the calendar's stretch), the days left under it and
/// the traffic eaten with the share left. The small chevron at the foot
/// says the card's tap asks which group to show.
private struct SubscriptionCard: View {
    let subscription: SubscriptionEntity
    @ObservedObject var model: ServersViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // The tile's own column: the square 48pt database tile with
            // the update button stacked under it — the original's
            // 48×36 stadium.
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Chumpy.secondaryContainer)
                        .frame(width: 48, height: 48)
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                updateButton
            }

            VStack(alignment: .leading, spacing: 8) {
                // The name and the last update's stamp in the same line.
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if let stamp = updatedStamp {
                        Text(stamp)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                }

                if let lastError = subscription.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                        .lineLimit(2)
                }

                if hasInfo {
                    VStack(alignment: .leading, spacing: 8) {
                        if let bar = usageBar {
                            usageBarView(bar)
                        }
                        // The days' number first, the quota's own report
                        // under it — the axis the card reads on first.
                        VStack(alignment: .leading, spacing: 2) {
                            if let daysText = expiryText {
                                Text(daysText)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.secondary)
                            }
                            if let trafficLine {
                                Text(trafficLine)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.secondary)
                                    .lineLimit(1)
                            }
                        }
                        // Clear of the chevron at the card's foot.
                        .padding(.trailing, 12)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .chumpyCard()
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 16)
                .padding(.bottom, 10)
                .allowsHitTesting(false)
        }
    }

    private var name: String {
        subscription.name.isEmpty ? subscription.url : subscription.name
    }

    private var updateButton: some View {
        let updating = model.updatingSubscriptionID == subscription.id
        return Button {
            Haptics.poke()
            Task { await model.updateSubscription(subscription.id) }
        } label: {
            ZStack {
                Capsule()
                    .fill(Chumpy.secondaryContainer)
                    .frame(width: 48, height: 36)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .rotationEffect(.degrees(updating ? 360 : 0))
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isStandaloneSelected || updating)
        .opacity(model.isStandaloneSelected ? 0.4 : 1)
        // The round-trip arrows spin slowly while the fetch runs — the
        // original's UpdateButton.
        .animation(
            updating
                ? .linear(duration: 1.4).repeatForever(autoreverses: false)
                : .default,
            value: updating
        )
    }

    private var usedBytes: Int64 {
        subscription.uploadBytes + subscription.downloadBytes
    }

    private var secondsLeft: Int64 {
        subscription.expireEpochSeconds - Int64(Date().timeIntervalSince1970)
    }

    private var hasInfo: Bool {
        subscription.totalBytes > 0 || subscription.expireEpochSeconds > 0 || usedBytes > 0
    }

    /// The tunnel's average daily burn over the week on record — the days
    /// the counters actually moved; a still day says nothing about pace.
    /// Nil until one such day stands in the store: the quota's runway
    /// can't be projected without it. Ported from the Android client's
    /// `averageDailyBytes`.
    private var averageDailyBytes: Double? {
        let days = model.week.map { $0.rx + $0.tx }.filter { $0 > 0 }
        guard !days.isEmpty else { return nil }
        return Double(days.reduce(Int64(0), +)) / Double(days.count)
    }

    /// The bar's own report — whichever runs dry first, the quota's or
    /// the calendar's: the quota's runway comes from the week's pace; a
    /// paceless quota keeps its own drain in the slot (the one reading
    /// always available), the days' stretch takes it when the panel set
    /// no quota at all or the quota would outlive the calendar. Ported
    /// from the Android client's `SubscriptionInfo`.
    private var usageBar: (progress: Double, color: Color)? {
        let bytesLeft = max(subscription.totalBytes - usedBytes, 0)
        let avg = averageDailyBytes
        let calendarFirst = subscription.expireEpochSeconds > 0 && (
            subscription.totalBytes <= 0 || (
                avg != nil && Double(secondsLeft) / 86_400 < Double(bytesLeft) / avg!
            )
        )
        if calendarFirst {
            let dayFraction = min(max(Double(secondsLeft) / (86_400 * 30), 0), 1)
            return (
                secondsLeft <= 0 ? 1 : dayFraction,
                secondsLeft <= 0 ? Color.red : usageColor(dayFraction)
            )
        }
        guard subscription.totalBytes > 0 else { return nil }
        let ratio = min(max(Double(bytesLeft) / Double(subscription.totalBytes), 0), 1)
        return (ratio, usageColor(ratio))
    }

    /// The traffic-light tiers hiddify reads off the remaining share: red
    /// under a quarter, amber under half, the accent otherwise.
    private func usageColor(_ ratio: Double) -> Color {
        if ratio < 0.25 { return .red }
        if ratio < 0.45 { return .orange }
        return Chumpy.accent
    }

    private func usageBarView(_ bar: (progress: Double, color: Color)) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                Capsule()
                    .fill(bar.color)
                    .frame(width: max(geo.size.width * CGFloat(bar.progress), 4))
            }
        }
        .frame(height: 4)
    }

    /// The days-remaining reading both the numbers share — over a year
    /// reads as never-ending, under a day as hours, the passed calendar
    /// as expired. Ported from the Android client's `daysTitle`.
    private var expiryText: String? {
        guard subscription.expireEpochSeconds > 0 else { return nil }
        let daysLeft = secondsLeft / 86_400
        if daysLeft > 365 {
            return String(localized: "servers.daysInfinite", bundle: .main)
        }
        if daysLeft >= 1 {
            return String(
                format: NSLocalizedString("servers.daysLeft", bundle: .main, comment: ""),
                Int(daysLeft)
            )
        }
        if secondsLeft > 0 {
            return String(
                format: NSLocalizedString("servers.hoursLeft", bundle: .main, comment: ""),
                Int(secondsLeft / 3_600)
            )
        }
        return String(localized: "servers.expired", bundle: .main)
    }

    /// The traffic eaten over the limit: hiddify's "used / total" — and
    /// when the panel keeps the quota to itself (total=0, the common
    /// unlimited case) the limit still shows, spelled out. The quota's
    /// share left appends itself behind a dot when the panel sets one.
    private var trafficLine: String? {
        guard usedBytes > 0 || subscription.totalBytes > 0 else { return nil }
        let total = subscription.totalBytes > 0
            ? Self.formatBytes(subscription.totalBytes)
            : String(localized: "servers.unlimited", bundle: .main)
        let consumed = "\(Self.formatBytes(usedBytes)) / \(total)"
        guard subscription.totalBytes > 0 else { return consumed }
        let left = max(subscription.totalBytes - usedBytes, 0)
        let percent = Int(min(max(Double(left) / Double(subscription.totalBytes), 0), 1) * 100)
        return "\(consumed) · \(percent)%"
    }

    /// The last update's stamp for the title line: the time of day if it
    /// was within the day, the day count in hiddify's shorthand ("2d")
    /// once it's older. Ported from the Android client's `updatedText`.
    private var updatedStamp: String? {
        guard let updated = subscription.lastUpdateSuccess else { return nil }
        let age = Date().timeIntervalSince(updated)
        if age < 86_400 {
            return String(
                format: NSLocalizedString("servers.updatedAt", bundle: .main, comment: ""),
                updated.formatted(date: .omitted, time: .shortened)
            )
        }
        return String(
            format: NSLocalizedString("servers.updatedAgo", bundle: .main, comment: ""),
            "\(Int(age / 86_400))d"
        )
    }

    /// Bytes in the panel's own units, down to whole kilobytes — the
    /// Android client's `formatBytes`.
    private static func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 B" }
        if bytes < 1024 { return "\(bytes) B" }
        let units = ["KiB", "MiB", "GiB", "TiB"]
        var value = Double(bytes)
        var unit = -1
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return String(format: "%.1f %@", value, units[unit])
    }
}

// MARK: - Server group row

/// The group card's own slice: the card's shape — the very shape the
/// subscription card wears, the platform's own 28pt continuous corner —
/// drawn in a rect grown past the row toward the group's inside, past
/// the corner construction's whole reach, then cut back to the row's
/// own bounds. The outer corners are the card's own genuine ones —
/// never the mixed-radius corner the platform deforms to fit a short
/// row, which the tile stopped nesting into — and the inner seam is a
/// straight cut: the rows butt flush into one continuous card, the
/// seam hidden under the hairline.
private struct CardSliceShape: Shape {
    /// The card's rounded top end lives inside this row's rect.
    var top: Bool
    /// The card's rounded bottom end lives inside this row's rect.
    var bottom: Bool
    /// How far past the row the card's shape extends toward the
    /// group's inside — well past the corner construction's whole
    /// reach, so the grown end never bends back into view.
    private static let reach: CGFloat = 72

    func path(in rect: CGRect) -> Path {
        var grown = rect
        if !top {
            grown.origin.y -= Self.reach
            grown.size.height += Self.reach
        }
        if !bottom {
            grown.size.height += Self.reach
        }
        return Path(roundedRect: grown, cornerRadius: Chumpy.cardRadius, style: .continuous)
    }
}

/// The system's own divider — the hairline the native inset lists wear
/// between their rows: half a point of primary at a tenth, set in from
/// the leading edge past the tile (the text's own 16 + 40 + 16 inset)
/// and from the trailing one by the card's own margin. It rides above
/// the seam and stays deaf to touches.
private var rowHairline: some View {
    Color.primary.opacity(0.1)
        .frame(height: 0.5)
        .padding(.leading, 72)
        .padding(.trailing, 16)
        .allowsHitTesting(false)
}

/// The ping's own answer as one equatable word — the measured number
/// and the moment it landed — so a sweep's update animates and pokes
/// once, not once per field.
private struct PingStamp: Hashable {
    let delay: Int64?
    let at: Date?

    var isMeasured: Bool { delay != nil || at != nil }
}

/// One row of the grouped list: the 72pt-min body, the round 40pt tile
/// (tonal, accent when picked) with the flag or the globe, the title with
/// its "· N ms" tail (accent from 150 ms), the protocol/host supporting
/// line — the whole row's paint lerps by selection. Ported from the
/// Android client's `ServerGroupRow` / `ServerRow`.
private struct ServerGroupRow: View {
    let profile: Profile
    let isFirst: Bool
    let isLast: Bool
    let isSelected: Bool
    /// The neighbor above stands selected: its light falls onto this
    /// row's own top edge.
    var glowsFromTop: Bool = false
    /// The neighbor below stands selected: its light falls onto this
    /// row's own bottom edge.
    var glowsFromBottom: Bool = false
    let tunnelUp: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onTogglePinned: () -> Void
    var onToggleConcealed: () -> Void
    var onTest: () -> Void

    /// True once this row has composed its first ping answer — the
    /// first reading is its own, not a change, so it stays silent.
    @State private var hasSeenPing = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            rowContent
                .background(
                    ZStack {
                        rowFill
                        glow
                    }
                )
                .overlay(alignment: .bottom) {
                    // The native lists never end a group with a divider:
                    // the hairline lives only between the rows, never on
                    // the card's own last edge.
                    if !isLast { rowHairline }
                }
                .contextMenu { menu }
                .onAppear { hasSeenPing = pingStamp.isMeasured }
                .onChange(of: pingStamp) { _ in announcePingChange() }
            if profile.pinned {
                // The pin at the row's top-right corner, rotated the way the
                // Android client wears it — over the group's edge.
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Chumpy.onAccent : Color.accentColor)
                    .rotationEffect(.degrees(30))
                    .offset(x: 14, y: -11)
                    .padding(.trailing, 10)
            }
        }
        .opacity(profile.concealed ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    /// The row's own paint, riding behind the content as its background —
    /// its slice of the group's one card: the card's own shape (the
    /// subscription card's very shape) grown toward the group's inside
    /// and cut back to the row's bounds. The resting row wears the flat
    /// quiet fill — the frost is gone from the rows, for the material
    /// carries its own white gradient sheen that read as a glow over
    /// every row's top; the rows stay flat. The selected one wears the
    /// accent's own solid plate — never a transparent wash. The layers
    /// crossfade, for a style swap animates between styles that don't
    /// blend and renders black.
    private var rowFill: some View {
        ZStack {
            rowSlice.fill(Chumpy.surfaceContainerLow)
            rowSlice.fill(Chumpy.accent)
                .opacity(isSelected ? 1 : 0)
        }
        .clipped()
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    private var rowSlice: CardSliceShape {
        CardSliceShape(top: isFirst, bottom: isLast)
    }

    /// The standing neighbor's own light, fallen onto this row: a soft
    /// accent wash fading in from the seam the selected row sits
    /// against — the leak the frost once bled across the gap, now an
    /// intentional effect the flush rows carry. It rides behind the
    /// content with the fill, never takes a touch, and fades with the
    /// same ease the selection itself does.
    private var glow: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Chumpy.accent.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)
            .opacity(glowsFromTop ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: glowsFromTop)
            Spacer(minLength: 0)
            LinearGradient(
                colors: [Chumpy.accent.opacity(0.08), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 20)
            .opacity(glowsFromBottom ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: glowsFromBottom)
        }
        .allowsHitTesting(false)
    }

    /// A sweep's fresh answer taps the soft poke — a dozen rows answer
    /// in a couple of seconds, and the full tap amplitude would
    /// machine-gun on a good motor. The row's first composition stays
    /// quiet: its reading is its own, not a change.
    private func announcePingChange() {
        if hasSeenPing { Haptics.softPoke() }
        hasSeenPing = true
    }

    /// The ping's whole answer — the number and the moment it was
    /// measured — as one word, so a sweep's single update speaks once,
    /// not once per field.
    private var pingStamp: PingStamp {
        PingStamp(delay: profile.testDelayMillis, at: profile.lastTestAt)
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            tile

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? Chumpy.onAccent : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // The last real ping, with the sweep's hand-over:
                    // the old number fades out, the new one flies in
                    // from the right — the rows trade their numbers one
                    // by one as the sweep answers each of them.
                    if let pingText {
                        Text("  ·  \(pingText)")
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundStyle(pingColor)
                            .id(pingStamp)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                    }
                }
                .animation(
                    .spring(response: 0.35, dampingFraction: 0.85),
                    value: pingStamp
                )
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Chumpy.onAccent.opacity(0.78) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if profile.concealed {
                Image(systemName: "eye.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Chumpy.onAccent : Color.secondary)
            }
        }
        .padding(16)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .onTapGesture {
            // A concealed row stands where it always stood but stays out
            // of play: the menu's own "reveal" is its way back. The
            // standing row's tap is silence too — the pick already
            // speaks, the Android client's own law.
            guard !profile.concealed, !isSelected else { return }
            Haptics.poke()
            onSelect()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                Haptics.poke()
            }
        )
    }

    /// The square 40pt tile with a 12pt corner, concentric with the
    /// group's own 28pt one: the 16pt inset on every side puts the
    /// tile's corner center exactly on the group corner's own center,
    /// and 28 − 16 = 12 keeps the gap between the two curves even all
    /// the way round — the iOS nesting law. White-tinted over the
    /// accent plate, tonal at rest. The flag rides the slot, names
    /// without one keep the globe, balancers keep the explore compass.
    private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Chumpy.onAccent.opacity(0.16) : Chumpy.secondaryContainer)
                .frame(width: 40, height: 40)
            if let flag = leadingFlagEmoji {
                Text(flag)
                    .font(.system(size: 20))
            } else if profile.type == .balancer {
                Image(systemName: "safari")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Chumpy.onAccent : Color.accentColor)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isSelected ? Chumpy.onAccent : Color.accentColor)
            }
        }
    }

    private var title: String {
        let raw = profile.remarks.isEmpty ? profile.server : profile.remarks
        // The flag the panel put at the front of the name rides the tile
        // instead; the title keeps the rest.
        if let flag = leadingFlagEmoji, raw.hasPrefix(flag) {
            return String(raw.dropFirst(flag.count)).trimmingCharacters(in: .whitespaces)
        }
        return raw
    }

    private var leadingFlagEmoji: String? {
        let scalars = Array((profile.remarks.isEmpty ? profile.server : profile.remarks)
            .unicodeScalars.prefix(2))
        guard scalars.count == 2,
              (0x1F1E6...0x1F1FF).contains(scalars[0].value),
              (0x1F1E6...0x1F1FF).contains(scalars[1].value)
        else { return nil }
        return "\(scalars[0])\(scalars[1])"
    }

    /// "· N ms" or the offline tail — only once the row has ever answered a
    /// test; never-measured rows stay quiet.
    private var pingText: String? {
        guard profile.type != .balancer,
              profile.testDelayMillis != nil || profile.lastTestAt != nil
        else { return nil }
        guard let delay = profile.testDelayMillis, delay >= 0 else {
            return NSLocalizedString("servers.offline", bundle: .main, comment: "")
        }
        return String(
            format: NSLocalizedString("servers.pingMs", bundle: .main, comment: ""),
            Int(delay)
        )
    }

    /// 150 ms is where the server starts feeling far away: from there the
    /// tail takes the accent tone — the original's HIGH_PING_MILLIS.
    /// On the selected plate the tail rides white, like all the row's
    /// ink.
    private var pingColor: Color {
        if isSelected {
            return Chumpy.onAccent.opacity(0.85)
        }
        if let delay = profile.testDelayMillis, delay >= 150 {
            return Color.accentColor
        }
        return .secondary
    }

    private var subtitle: String {
        // The balancer's own line: how wide it picks, and how — the
        // original's balancer rows instead of an endpoint they don't own.
        if profile.type == .balancer {
            let members = String(
                format: NSLocalizedString("servers.balancer.members", bundle: .main, comment: ""),
                profile.balancerMemberKeys.count
            )
            return [members, balancerStrategyLabel].joined(separator: "  ·  ")
        }
        let host = "\(profile.server):\(profile.serverPort)"
        let proto: String?
        switch profile.type {
        case .balancer: proto = nil
        default: proto = profile.type.rawValue.lowercased()
        }
        return [proto, host].compactMap { $0 }.joined(separator: "  ·  ")
    }

    /// How the core picks the balancer's member of the moment — the
    /// parser normalizes the strategy name, anything odd falls back to
    /// random, matching the Android label table.
    private var balancerStrategyLabel: String {
        let key: String
        switch profile.balancerStrategy {
        case "roundrobin": key = "servers.balancer.roundRobin"
        case "leastping": key = "servers.balancer.leastPing"
        case "leastload": key = "servers.balancer.leastLoad"
        default: key = "servers.balancer.random"
        }
        return NSLocalizedString(key, bundle: .main, comment: "")
    }

    /// The row's own asks: the pin, the hide, the test — the delete stands
    /// only for the loose configs that own themselves, the copy hands the
    /// link out.
    @ViewBuilder
    private var menu: some View {
        Button {
            Haptics.poke()
            onTogglePinned()
        } label: {
            if profile.pinned {
                Label("servers.row.unpin", systemImage: "pin.slash")
            } else {
                Label("servers.row.pin", systemImage: "pin")
            }
        }
        if profile.concealed {
            Button {
                Haptics.poke()
                onToggleConcealed()
            } label: {
                Label("servers.row.reveal", systemImage: "eye")
            }
        } else {
            Button {
                Haptics.poke()
                onToggleConcealed()
            } label: {
                Label("servers.row.hide", systemImage: "eye.slash")
            }
        }
        Button {
            Haptics.poke()
            onTest()
        } label: {
            Label("servers.row.test", systemImage: "bolt.horizontal")
        }
        if profile.subscriptionID == nil {
            // The loose configs own themselves: the link they were born
            // from rides the menu for the copying, dim when there's none —
            // the Android row menu's own ask.
            Button {
                Haptics.poke()
                UIPasteboard.general.string = profile.sourceLink
            } label: {
                Label("servers.row.copyURL", systemImage: "doc.on.doc")
            }
            .disabled(profile.sourceLink == nil)
            Button(role: .destructive) {
                Haptics.poke()
                onDelete()
            } label: {
                Label("servers.delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Subscription chooser sheet

/// The groups' own chooser: the subscription card's tap opens it — the
/// same grouped list the servers page wears: one continuous card, the
/// subscription card's very shape, its rows divided by the system's
/// own hairlines, the standing row on the accent's solid plate with
/// its white check. A long-press asks the delete, the same context
/// menu the server rows wear; the add row closes the group.
private struct SubscriptionChooserSheet: View {
    @ObservedObject var model: ServersViewModel
    var onAddSubscription: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavHost {
            ScrollView {
                // The rows butt flush, the servers list's own law: one
                // continuous card, the seams carrying the hairlines.
                VStack(spacing: 0) {
                    let hasStandalone = model.manualProfileCount > 0
                    if hasStandalone {
                        groupRow(
                            id: standaloneSubscriptionID,
                            name: String(localized: "servers.standalone", bundle: .main),
                            subtitle: String(
                                format: NSLocalizedString(
                                    "servers.standalone.subtitle", bundle: .main, comment: ""
                                ),
                                model.manualProfileCount
                            ),
                            isFirst: true
                        )
                    }
                    ForEach(Array(model.subscriptions.enumerated()), id: \.element.id) { index, sub in
                        groupRow(
                            id: sub.id,
                            name: sub.name.isEmpty ? sub.url : sub.name,
                            subtitle: sub.url,
                            isFirst: !hasStandalone && index == 0
                        )
                    }
                    addRow
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .navigationTitle("servers.subscriptions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
    }

    /// One group row, the servers list's own anatomy: the 40pt tile, the
    /// name over the host, the checkmark on the standing one — a tap
    /// stands it, a long-press asks its delete.
    private func groupRow(id: String, name: String, subtitle: String, isFirst: Bool) -> some View {
        let isSelected = model.selectedSubscriptionID == id

        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Chumpy.onAccent.opacity(0.16) : Chumpy.secondaryContainer)
                    .frame(width: 40, height: 40)
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSelected ? Chumpy.onAccent : Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Chumpy.onAccent : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Chumpy.onAccent.opacity(0.78) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Chumpy.onAccent)
            }
        }
        .padding(16)
        .frame(minHeight: 72)
        .background(rowFill(isFirst: isFirst, isLast: false, isSelected: isSelected))
        .overlay(alignment: .bottom) {
            // The add row always stands below this one, so the seam
            // always carries the hairline.
            rowHairline
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.poke()
            model.selectSubscription(id)
            dismiss()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                Haptics.poke()
            }
        )
        .contextMenu {
            Button(role: .destructive) {
                Haptics.poke()
                model.deleteSubscription(id)
                dismiss()
            } label: {
                Label("servers.deleteSubscription", systemImage: "trash")
            }
        }
    }

    /// The add row — the dialog's door, and the group's own closing row.
    private var addRow: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Chumpy.secondaryContainer)
                    .frame(width: 40, height: 40)
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            Text("servers.add.subscription")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minHeight: 72)
        .background(
            rowFill(
                isFirst: model.manualProfileCount == 0 && model.subscriptions.isEmpty,
                isLast: true,
                isSelected: false
            )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.poke()
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                onAddSubscription()
            }
        }
    }

    /// The row's own paint — its slice of the group's one card: the
    /// card's own shape (the subscription card's very shape) grown
    /// toward the group's inside and cut back to the row's bounds. The
    /// flat quiet fill at rest — no frost, no gradient sheen — the
    /// accent's solid plate when standing.
    private func rowFill(isFirst: Bool, isLast: Bool, isSelected: Bool) -> some View {
        ZStack {
            CardSliceShape(top: isFirst, bottom: isLast).fill(Chumpy.surfaceContainerLow)
            CardSliceShape(top: isFirst, bottom: isLast).fill(Chumpy.accent)
                .opacity(isSelected ? 1 : 0)
        }
        .clipped()
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}
