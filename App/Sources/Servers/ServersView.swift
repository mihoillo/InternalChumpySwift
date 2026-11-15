import SwiftUI
import ChumpyCore

/// Servers tab: the subscription card, the group's server list and the
/// add/refresh/delete actions. Ported from the Android client's
/// `ServersScreen`, in the native iOS idiom.
struct ServersView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = ServersViewModel()
    @State private var showAddSubscription = false
    @State private var showPasteLinks = false

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
                ToolbarItem(placement: .navigationBarLeading) { subscriptionMenu }
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
    }

    // MARK: - List

    private var list: some View {
        List {
            if let sub = model.selectedSubscription {
                Section {
                    SubscriptionCard(subscription: sub, model: model)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }

            Section {
                ForEach(model.profiles) { profile in
                    ServerRow(profile: profile, isSelected: isSelected(profile))
                        .contentShape(Rectangle())
                        .onTapGesture { select(profile) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if model.isStandaloneSelected {
                                Button(role: .destructive) {
                                    model.deleteManualProfile(profile.id)
                                } label: {
                                    Label("servers.delete", systemImage: "trash")
                                }
                            }
                        }
                }
            } header: {
                HStack {
                    Text("servers.group.title")
                    if model.isPinging {
                        Spacer()
                        ProgressView()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await model.pingServers()
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
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar

    private var subscriptionMenu: some View {
        Menu {
            if model.manualProfileCount > 0 {
                subscriptionPickerRow(
                    id: standaloneSubscriptionID,
                    name: String(localized: "servers.standalone", bundle: .main)
                )
            }
            ForEach(model.subscriptions) { sub in
                subscriptionPickerRow(
                    id: sub.id,
                    name: sub.name.isEmpty ? sub.url : sub.name
                )
            }
            autoUpdateToggle
        } label: {
            Image(systemName: "rectangle.stack")
        }
    }

    /// The per-subscription auto-update switch, inside the dropdown — the
    /// Android client's own arrangement.
    @ViewBuilder
    private var autoUpdateToggle: some View {
        if let id = model.selectedSubscriptionID, !model.isStandaloneSelected,
           let sub = model.subscriptions.first(where: { $0.id == id }) {
            Divider()
            Button {
                model.setSubscriptionAutoUpdate(id: id, enabled: !sub.autoUpdate)
            } label: {
                if sub.autoUpdate {
                    Label {
                        Text("servers.autoUpdate")
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                } else {
                    Text("servers.autoUpdate")
                }
            }
        }
    }

    private func subscriptionPickerRow(id: String, name: String) -> some View {
        Button {
            model.selectSubscription(id)
        } label: {
            if model.selectedSubscriptionID == id {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
    }

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

private struct SubscriptionCard: View {
    let subscription: SubscriptionEntity
    @ObservedObject var model: ServersViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(subscription.name.isEmpty ? subscription.url : subscription.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !model.isStandaloneSelected {
                    if model.updatingSubscriptionID == subscription.id {
                        ProgressView()
                    } else {
                        Button {
                            Task { await model.updateSubscription(subscription.id) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if subscription.lastError != nil {
                Text(subscription.lastError ?? "")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if subscription.totalBytes > 0 {
                traffic
            }

            if let updated = subscription.lastUpdateSuccess {
                Text(String(
                    format: NSLocalizedString("servers.updated", bundle: .main, comment: ""),
                    updated.formatted(date: .abbreviated, time: .shortened)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if subscription.expireEpochSeconds > 0 {
                Text(expiryText)
                    .font(.caption)
                    .foregroundStyle(isExpired ? .red : .secondary)
            }
        }
        .padding(16)
        .chumpyGlassCard()
    }

    private var traffic: some View {
        let used = subscription.uploadBytes + subscription.downloadBytes
        let ratio = subscription.totalBytes > 0
            ? Double(used) / Double(subscription.totalBytes) : 0
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: min(max(ratio, 0), 1))
                .tint(ratio > 0.9 ? .red : Chumpy.accent)
            Text("\(ByteCountFormatter.string(fromByteCount: used, countStyle: .binary)) / "
                + ByteCountFormatter.string(fromByteCount: subscription.totalBytes, countStyle: .binary))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isExpired: Bool {
        subscription.expireEpochSeconds > 0
            && Double(subscription.expireEpochSeconds) < Date().timeIntervalSince1970
    }

    private var expiryText: String {
        let secondsLeft = Double(subscription.expireEpochSeconds) - Date().timeIntervalSince1970
        if secondsLeft <= 0 {
            return String(localized: "servers.expired", bundle: .main)
        }
        let days = Int(secondsLeft / 86_400)
        return String(
            format: NSLocalizedString("servers.expiresInDays", bundle: .main, comment: ""),
            days
        )
    }
}

// MARK: - Server row

private struct ServerRow: View {
    let profile: Profile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Chumpy.accent : Color.secondary.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.remarks.isEmpty ? profile.server : profile.remarks)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(profile.endpoint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(protocolLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            Spacer()
            if let delay = profile.testDelayMillis, delay > 0 {
                Text("\(delay) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(delayColor(delay))
            }
        }
        .padding(.vertical, 2)
    }

    private var protocolLabel: String {
        switch profile.type {
        case .balancer:
            return strategyLabel
        default:
            return profile.type.rawValue
        }
    }

    private var strategyLabel: String {
        switch profile.balancerStrategy {
        case "leastping": return "PING"
        case "leastload": return "LOAD"
        case "roundrobin": return "RR"
        default: return "AUTO"
        }
    }

    private func delayColor(_ delay: Int64) -> Color {
        if delay < 200 { return .green }
        if delay < 500 { return .orange }
        return .red
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
                    .chumpyGlassCard(cornerRadius: 12)
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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
