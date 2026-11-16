import SwiftUI
import ChumpyCore

/// Servers tab, ported from the Android client's `ServersScreen` layout:
/// the subscription card with the database tile, the centered chips header
/// (total / expired / concealed / sort), and the grouped rows wearing the
/// outer 28dp corners at the group's own edges and the small 4dp ones
/// inside.
struct ServersView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = ServersViewModel()
    @State private var showAddSubscription = false
    @State private var showPasteLinks = false
    @State private var showSubscriptionChooser = false

    var body: some View {
        NavHost {
            Group {
                if model.profiles.isEmpty && model.subscriptions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("tab.servers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { addMenu }
            }
        }
        .onAppear {
            model.tunnelUp = {
                appState.status == .connected || appState.status == .reasserting
            }
            model.reload()
        }
        .sheet(isPresented: $showAddSubscription) {
            AddSubscriptionSheet(model: model)
        }
        .sheet(isPresented: $showPasteLinks) {
            PasteLinksSheet(model: model)
        }
        .sheet(isPresented: $showSubscriptionChooser) {
            SubscriptionChooserSheet(model: model) {
                showAddSubscription = true
            } showPasteLinks: {
                showPasteLinks = true
            }
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
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
            .padding(.top, 8)
            .padding(.bottom, 16)
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
        VStack(spacing: 2) {
            ForEach(model.profiles) { profile in
                ServerGroupRow(
                    profile: profile,
                    isSelected: isSelected(profile),
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
                showAddSubscription = true
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
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar

    private var addMenu: some View {
        Menu {
            Button {
                showAddSubscription = true
            } label: {
                Label("servers.add.subscription", systemImage: "link.badge.plus")
            }
            Button {
                showPasteLinks = true
            } label: {
                Label("servers.add.paste", systemImage: "doc.on.clipboard")
            }
        } label: {
            Image(systemName: "plus")
        }
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

/// One row of the grouped list: the 72pt-min body, the round 40pt tile
/// (tonal, accent when picked) with the flag or the globe, the title with
/// its "· N ms" tail (accent from 200 ms), the protocol/host supporting
/// line — the whole row's paint lerps by selection. Ported from the
/// Android client's `ServerGroupRow` / `ServerRow`.
private struct ServerGroupRow: View {
    let profile: Profile
    let isSelected: Bool
    let tunnelUp: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onTogglePinned: () -> Void
    var onToggleConcealed: () -> Void
    var onTest: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            rowContent
                .background(rowFill)
                .contextMenu { menu }
            if profile.pinned {
                // The pin at the row's top-right corner, rotated the way the
                // Android client wears it — over the group's edge.
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .rotationEffect(.degrees(30))
                    .offset(x: 14, y: -11)
                    .padding(.trailing, 10)
            }
        }
        .opacity(profile.concealed ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    /// The row's own paint, riding behind the content as its background —
    /// a plain square-cut plate, the way the user wears the list.
    private var rowFill: some View {
        Rectangle()
            .fill(isSelected ? Chumpy.primaryContainer : Chumpy.surfaceContainer)
            .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            tile

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
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
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if profile.concealed {
                Image(systemName: "eye.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .onTapGesture {
            // A concealed row stands where it always stood but stays out
            // of play: the menu's own "reveal" is its way back.
            if !profile.concealed { onSelect() }
        }
    }

    /// The round 40pt tile: tonal, the accent's own fill when picked — the
    /// flag rides the slot, names without one keep the globe, balancers
    /// keep the explore compass.
    private var tile: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Chumpy.accent : Chumpy.secondaryContainer)
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
    private var pingColor: Color {
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

/// The groups' own chooser: the subscription card's tap opens it, and every
/// option stands as a thick Chumpy row — the database tile, the name, the
/// host under it, the checkmark on the standing one — with the auto-update
/// switch, the add actions and the delete at the bottom.
private struct SubscriptionChooserSheet: View {
    @ObservedObject var model: ServersViewModel
    var onAddSubscription: () -> Void
    var showPasteLinks: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavHost {
            ScrollView {
                VStack(spacing: 8) {
                    if model.manualProfileCount > 0 {
                        row(
                            id: standaloneSubscriptionID,
                            name: String(localized: "servers.standalone", bundle: .main),
                            subtitle: String(
                                format: NSLocalizedString(
                                    "servers.standalone.subtitle", bundle: .main, comment: ""
                                ),
                                model.manualProfileCount
                            )
                        )
                    }
                    ForEach(model.subscriptions) { sub in
                        row(
                            id: sub.id,
                            name: sub.name.isEmpty ? sub.url : sub.name,
                            subtitle: sub.url
                        )
                    }

                    if let sub = model.selectedSubscription,
                       sub.id != standaloneSubscriptionID {
                        autoUpdateRow(sub)
                        deleteRow(sub)
                    }

                    addActionRow(
                        titleKey: "servers.add.subscription",
                        icon: "link.badge.plus",
                        action: {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                onAddSubscription()
                            }
                        }
                    )
                    addActionRow(
                        titleKey: "servers.add.paste",
                        icon: "doc.on.clipboard",
                        action: {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                showPasteLinks()
                            }
                        }
                    )
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

    /// One thick group row: 64pt minimum, the tile, the name over the host,
    /// the standing one painted tonal with its checkmark.
    private func row(id: String, name: String, subtitle: String) -> some View {
        let isSelected = model.selectedSubscriptionID == id

        return Button {
            model.selectSubscription(id)
            dismiss()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Chumpy.accent : Chumpy.secondaryContainer)
                        .frame(width: 40, height: 40)
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(16)
            .frame(minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Chumpy.primaryContainer : Chumpy.surfaceContainer)
            )
        }
        .buttonStyle(.plain)
    }

    /// The standing subscription's own background refresh switch.
    private func autoUpdateRow(_ sub: SubscriptionEntity) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Chumpy.secondaryContainer)
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            Text("servers.autoUpdate")
                .font(.system(size: 16, weight: .medium))
            Spacer()
            Toggle(
                isOn: Binding(
                    get: { sub.autoUpdate },
                    set: { model.setSubscriptionAutoUpdate(id: sub.id, enabled: $0) }
                )
            ) {}
            .labelsHidden()
            .tint(Chumpy.accent)
        }
        .padding(16)
        .frame(minHeight: 72)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Chumpy.surfaceContainer)
        )
    }

    /// The group's own delete — the whole subscription with everything it
    /// brought in, or the standalone group.
    private func deleteRow(_ sub: SubscriptionEntity) -> some View {
        Button {
            model.deleteSubscription(sub.id)
            dismiss()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.red)
                }
                Text("servers.deleteSubscription")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.red)
                Spacer()
            }
            .padding(16)
            .frame(minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Chumpy.surfaceContainer)
            )
        }
        .buttonStyle(.plain)
    }

    private func addActionRow(titleKey: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Chumpy.secondaryContainer)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                Text(titleKey)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
            .padding(16)
            .frame(minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Chumpy.surfaceContainer)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheets

private struct AddSubscriptionSheet: View {
    @ObservedObject var model: ServersViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavHost {
            Form {
                Section {
                    TextField("servers.add.urlPlaceholder", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("servers.add.url")
                }
                Section {
                    TextField("servers.add.namePlaceholder", text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("servers.add.name")
                } footer: {
                    Text("servers.add.nameFooter")
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("servers.add.subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.add") {
                        busy = true
                        Task {
                            await model.addSubscription(url: url, name: name) { failure in
                                busy = false
                                error = failure
                                if failure == nil { dismiss() }
                            }
                        }
                    }
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
            }
        }
    }
}

private struct PasteLinksSheet: View {
    @ObservedObject var model: ServersViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavHost {
            VStack(spacing: 12) {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .frame(maxHeight: .infinity)
                    .padding(8)
                    .chumpyCard(radius: 12)
                    .padding(.horizontal)
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }
                Button {
                    model.addManualProfiles(text) { failure in
                        error = failure
                        if failure == nil { dismiss() }
                    }
                } label: {
                    Text("servers.add.import")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Chumpy.secondaryContainer))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("servers.add.paste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
    }
}
