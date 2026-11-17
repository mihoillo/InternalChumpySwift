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
                .onTapGesture { closeAddDialog() }

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
                        .foregroundStyle(.white)
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

/// The subscription card: the database tile on its square backing over the
/// report — the name, the usage bar, the consumed line, the days left, the
/// update stamp — with the reload button at its side. Ported from the
/// Android client's `SubscriptionCard` report face.
private struct SubscriptionCard: View {
    let subscription: SubscriptionEntity
    @ObservedObject var model: ServersViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Chumpy.secondaryContainer)
                    .frame(width: 40, height: 40)
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)

                if subscription.lastError != nil {
                    Text(subscription.lastError ?? "")
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                        .lineLimit(2)
                }

                if subscription.totalBytes > 0 {
                    usage
                    consumedLine
                }
                if let daysText = expiryText {
                    Text(daysText)
                        .font(.system(size: 12))
                        .foregroundStyle(isExpired ? Color.red : Color.secondary)
                }
                if let updated = subscription.lastUpdateSuccess {
                    Text(String(
                        format: NSLocalizedString("servers.updatedAt", bundle: .main, comment: ""),
                        updated.formatted(date: .abbreviated, time: .shortened)
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            updateButton
        }
        .padding(16)
        .chumpyCard()
    }

    private var name: String {
        subscription.name.isEmpty ? subscription.url : subscription.name
    }

    private var updateButton: some View {
        Group {
            if model.updatingSubscriptionID == subscription.id {
                ZStack {
                    Circle()
                        .fill(Chumpy.surfaceContainerLow)
                        .frame(width: 40, height: 40)
                    ProgressView()
                        .scaleEffect(0.8)
                }
            } else {
                Button {
                    Task { await model.updateSubscription(subscription.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Chumpy.surfaceContainerLow))
                }
                .buttonStyle(.plain)
                .disabled(model.isStandaloneSelected)
                .opacity(model.isStandaloneSelected ? 0.4 : 1)
            }
        }
    }

    /// The panel's usage bar: the consumed share of what the panel allows.
    private var usage: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Chumpy.secondaryContainer)
                Capsule()
                    .fill(usedRatio > 0.9 ? Color.red : Chumpy.accent)
                    .frame(width: max(geo.size.width * usedRatio, 4))
            }
        }
        .frame(height: 4)
    }

    private var usedRatio: CGFloat {
        guard subscription.totalBytes > 0 else { return 0 }
        let used = subscription.uploadBytes + subscription.downloadBytes
        return min(max(Double(used) / Double(subscription.totalBytes), 0), 1)
    }

    private var consumedLine: some View {
        let used = subscription.uploadBytes + subscription.downloadBytes
        return Text(
            "\(ByteCountFormatter.string(fromByteCount: used, countStyle: .binary)) / "
                + ByteCountFormatter.string(fromByteCount: subscription.totalBytes, countStyle: .binary)
        )
        .font(.system(size: 12))
        .foregroundStyle(Color.secondary)
    }

    private var isExpired: Bool {
        subscription.expireEpochSeconds > 0
            && Double(subscription.expireEpochSeconds) < Date().timeIntervalSince1970
    }

    private var expiryText: String? {
        guard subscription.expireEpochSeconds > 0 else { return nil }
        let secondsLeft = Double(subscription.expireEpochSeconds) - Date().timeIntervalSince1970
        if secondsLeft <= 0 {
            return String(localized: "servers.expired", bundle: .main)
        }
        let days = Int(secondsLeft / 86_400)
        return String(
            format: NSLocalizedString("servers.daysLeft", bundle: .main, comment: ""),
            days
        )
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

/// One row of the grouped list: the 72pt-min body, the round 40pt tile
/// (tonal, accent when picked) with the flag or the globe, the title with
/// its "· N ms" tail (accent from 200 ms), the protocol/host supporting
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
            if profile.pinned {
                // The pin at the row's top-right corner, rotated the way the
                // Android client wears it — over the group's edge.
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
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
    /// and cut back to the row's bounds. The resting row wears the
    /// native frost; the selected one the accent's own solid plate —
    /// never a transparent wash. The layers crossfade, for a style swap
    /// animates between styles that don't blend and renders black.
    private var rowFill: some View {
        ZStack {
            rowSlice.fill(.regularMaterial)
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
                colors: [Chumpy.accent.opacity(0.14), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            .opacity(glowsFromTop ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: glowsFromTop)
            Spacer(minLength: 0)
            LinearGradient(
                colors: [Chumpy.accent.opacity(0.14), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 24)
            .opacity(glowsFromBottom ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: glowsFromBottom)
        }
        .allowsHitTesting(false)
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            tile

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let pingText {
                        Text("  ·  \(pingText)")
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundStyle(pingColor)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if profile.concealed {
                Image(systemName: "eye.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
            }
        }
        .padding(16)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .onTapGesture {
            // A concealed row stands where it always stood but stays out
            // of play: the menu's own "reveal" is its way back.
            if !profile.concealed { onSelect() }
        }
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
                .fill(isSelected ? Color.white.opacity(0.16) : Chumpy.secondaryContainer)
                .frame(width: 40, height: 40)
            if let flag = leadingFlagEmoji {
                Text(flag)
                    .font(.system(size: 20))
            } else if profile.type == .balancer {
                Image(systemName: "safari")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
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

    /// 200 ms is where the server starts feeling far away: from there the
    /// tail takes the accent tone, matching the home ping chip's law.
    /// On the selected plate the tail rides white, like all the row's
    /// ink.
    private var pingColor: Color {
        if isSelected {
            return Color.white.opacity(0.85)
        }
        if let delay = profile.testDelayMillis, delay >= 200 {
            return Color.accentColor
        }
        return .secondary
    }

    private var subtitle: String {
        let host = "\(profile.server):\(profile.serverPort)"
        let proto: String?
        switch profile.type {
        case .balancer: proto = nil
        default: proto = profile.type.rawValue.lowercased()
        }
        return [proto, host].compactMap { $0 }.joined(separator: "  ·  ")
    }

    /// The row's own asks: the pin, the hide, the test — the delete stands
    /// only for the loose configs that own themselves, the copy hands the
    /// link out.
    @ViewBuilder
    private var menu: some View {
        Button {
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
                onToggleConcealed()
            } label: {
                Label("servers.row.reveal", systemImage: "eye")
            }
        } else {
            Button {
                onToggleConcealed()
            } label: {
                Label("servers.row.hide", systemImage: "eye.slash")
            }
        }
        Button {
            onTest()
        } label: {
            Label("servers.row.test", systemImage: "bolt.horizontal")
        }
        if profile.subscriptionID == nil {
            Button(role: .destructive) {
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
                    .fill(isSelected ? Color.white.opacity(0.16) : Chumpy.secondaryContainer)
                    .frame(width: 40, height: 40)
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
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
            model.selectSubscription(id)
            dismiss()
        }
        .contextMenu {
            Button(role: .destructive) {
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
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                onAddSubscription()
            }
        }
    }

    /// The row's own paint — its slice of the group's one card: the
    /// card's own shape (the subscription card's very shape) grown
    /// toward the group's inside and cut back to the row's bounds. The
    /// native frost at rest, the accent's solid plate when standing.
    private func rowFill(isFirst: Bool, isLast: Bool, isSelected: Bool) -> some View {
        ZStack {
            CardSliceShape(top: isFirst, bottom: isLast).fill(.regularMaterial)
            CardSliceShape(top: isFirst, bottom: isLast).fill(Chumpy.accent)
                .opacity(isSelected ? 1 : 0)
        }
        .clipped()
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}
