import SwiftUI
import ChumpyCore

/// Settings tab, in the Chumpy card language: the connection card, the
/// tunnel card, the about card — 28dp tonal cards with icon'd headers,
/// the connection section writing straight to the shared defaults the
/// tunnel reads on the next connect.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(
        ChumpyConstant.Keys.routingMode,
        store: ChumpyConstant.sharedDefaults
    ) private var routingMode: RoutingMode.RawValue = RoutingMode.global.rawValue
    @AppStorage(
        ChumpyConstant.Keys.testURL,
        store: ChumpyConstant.sharedDefaults
    ) private var testURL: String = "https://www.gstatic.com/generate_204"
    /// The subscriptions' own word, re-read from the store on every
    /// appear — the auto-update card's rows.
    @State private var subscriptions: [SubscriptionEntity] = []

    /// The store the subscriptions live in — file-backed, the same one
    /// the servers screen writes through.
    private let store = ProfileStore()

    var body: some View {
        EdgeScrollView(tag: "settings") {
            VStack(spacing: 12) {
                connectionCard
                if !subscriptions.isEmpty {
                    subscriptionsCard
                }
                tunnelCard
                aboutCard
            }
            .padding(.horizontal, 16)
            .padding(.top, chumpyContentTopPadding)
            .padding(.bottom, 104)
        }
        .onAppear {
            subscriptions = store.subscriptions().sorted { $0.createdAt < $1.createdAt }
        }
    }

    // MARK: - Subscriptions

    /// The auto-update law, per subscription — where the original
    /// client keeps it: in the settings, not in the groups' chooser.
    private var subscriptionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartHeader(icon: "arrow.triangle.2.circlepath", title: "settings.subscriptions")

            ForEach(subscriptions) { sub in
                Toggle(isOn: autoUpdateBinding(sub)) {
                    Text(sub.name.isEmpty ? sub.url : sub.name)
                        .font(.system(size: 15))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .tint(Chumpy.accent)
            }
        }
        .padding(16)
        .chumpyCard()
    }

    /// The toggle's own write: the store answers, the background
    /// schedule re-arms itself with the new set of due dates, and the
    /// rows re-read what the store now says.
    private func autoUpdateBinding(_ sub: SubscriptionEntity) -> Binding<Bool> {
        Binding(
            get: { sub.autoUpdate },
            set: { enabled in
                store.setSubscriptionAutoUpdate(id: sub.id, enabled: enabled)
                SubscriptionAutoUpdate.schedule()
                subscriptions = store.subscriptions().sorted { $0.createdAt < $1.createdAt }
            }
        )
    }

    // MARK: - Connection

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartHeader(icon: "arrow.triangle.branch", title: "settings.connection")

            Menu {
                ForEach(RoutingMode.allCases) { mode in
                    Button {
                        routingMode = mode.rawValue
                    } label: {
                        if mode.rawValue == routingMode {
                            Label(
                                LocalizedStringKey(mode.localizationKey),
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(LocalizedStringKey(mode.localizationKey))
                        }
                    }
                }
            } label: {
                rowLabel(
                    title: LocalizedStringKey(
                        RoutingMode(rawValue: routingMode)?.localizationKey ?? "routing.global"
                    ),
                    subtitle: "settings.routing"
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("settings.testURL")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                TextField("https://…", text: $testURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Chumpy.surfaceContainerLow)
                    )
            }
        }
        .padding(16)
        .chumpyCard()
    }

    // MARK: - Tunnel

    private var tunnelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartHeader(icon: "shield.lefthalf.filled", title: "settings.tunnel")

            HStack {
                Text("settings.status")
                Spacer()
                Text(statusText)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 15))

            Button(role: .destructive) {
                Task {
                    try? await appState.removeFromPreferences()
                    await appState.reload()
                }
            } label: {
                Label("settings.reinstallProfile", systemImage: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.red.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .chumpyCard()
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartHeader(icon: "info.circle", title: "settings.about")
            HStack {
                Text("settings.appVersion")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 15))
            HStack {
                Text("settings.coreVersion")
                Spacer()
                Text("Xray (libXray-apple v26.3.27)")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 15))
        }
        .padding(16)
        .chumpyCard()
    }

    private func rowLabel(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Chumpy.surfaceContainerLow)
        )
        .contentShape(Rectangle())
    }

    private var statusText: String {
        switch appState.status {
        case .connected: return NSLocalizedString("home.state.up", bundle: .main, comment: "")
        case .connecting, .reasserting:
            return NSLocalizedString("home.state.connecting", bundle: .main, comment: "")
        case .disconnecting:
            return NSLocalizedString("home.state.disconnecting", bundle: .main, comment: "")
        default: return NSLocalizedString("home.state.down", bundle: .main, comment: "")
        }
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
        return "\(short ?? "?") (\(build ?? "?"))"
    }
}
