import SwiftUI
import UIKit
import ChumpyCore

/// The Connection settings page — the settings deck's middle leaf, the
/// one the old single settings screen was: the connection card, the
/// subscriptions card, the tunnel card, 28dp tonal cards in the Chumpy
/// card language, the connection section writing straight to the shared
/// defaults the tunnel reads on the next connect. The page's own title
/// in the header already says "Connection", so the connection card
/// doesn't repeat it — the card speaks its rows alone.
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
        EdgeScrollView(tag: "connection") {
            VStack(spacing: 12) {
                connectionCard
                if !subscriptions.isEmpty {
                    subscriptionsCard
                }
                tunnelCard
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

    /// The connection card — no header of its own: the page's title in
    /// the header strip already speaks the word, and the card's rows
    /// carry the rest.
    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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
}

/// The Interface settings page — the settings deck's first leaf, the
/// one the original client opens the settings on: for now the theme
/// card alone, the app's whole look answering one pick — the system's
/// own word, or always light, or always dark.
struct InterfaceView: View {
    /// The app's theme word, the ChumpyApp root reads it and hands the
    /// platform its color scheme: 0 — the system's own, 1 — always
    /// light, 2 — always dark.
    @AppStorage("themeMode") private var themeMode: Int = 0
    /// The icon the home screen wears now — the platform's own word,
    /// mirrored here so the picker's ring lands the moment the swap
    /// does. Nil is the icon the app was born with.
    @State private var currentIcon: String?

    var body: some View {
        EdgeScrollView(tag: "interface") {
            VStack(spacing: 12) {
                themeCard
                iconCard
            }
            .padding(.horizontal, 16)
            .padding(.top, chumpyContentTopPadding)
            .padding(.bottom, 104)
        }
        .onAppear {
            currentIcon = UIApplication.shared.alternateIconName
        }
    }

    // MARK: - Theme

    /// The theme card: three tiles — system, light, dark — the picked
    /// one wearing the accent, the way the original client's own
    /// interface page picks its words.
    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartHeader(icon: "paintpalette", title: "settings.theme")

            HStack(spacing: 8) {
                themeTile(0, icon: "circle.lefthalf.filled", title: "settings.theme.system")
                themeTile(1, icon: "sun.max.fill", title: "settings.theme.light")
                themeTile(2, icon: "moon.fill", title: "settings.theme.dark")
            }
        }
        .padding(16)
        .chumpyCard()
    }

    /// One theme tile: the icon over the word, the picked one wearing
    /// the accent's own tint and fill, the rest the quiet surface.
    private func themeTile(
        _ mode: Int,
        icon: String,
        title: LocalizedStringKey
    ) -> some View {
        let isPicked = themeMode == mode

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                themeMode = mode
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isPicked ? Chumpy.accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isPicked ? Chumpy.accent.opacity(0.12) : Chumpy.surfaceContainerLow)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - App icon

    /// The app icon card, the original client's own picker: the two
    /// faces the app wears on the home screen — Chumpy's blue and the
    /// inverted one — as previews cut to the home screen's own corner,
    /// the picked one ringed in the accent. A pick asks the platform to
    /// swap the icon; the platform answers with its own confirmation
    /// dialog, the one word iOS never lets an app skip.
    private var iconCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartHeader(icon: "square.grid.2x2", title: "settings.appIcon")

            HStack(spacing: 12) {
                iconTile(
                    name: nil,
                    preview: "icon-preview-chumpy",
                    title: "settings.icon.chumpy"
                )
                iconTile(
                    name: "AppIconInverted",
                    preview: "icon-preview-inverted",
                    title: "settings.icon.inverted"
                )
            }
        }
        .padding(16)
        .chumpyCard()
    }

    /// One icon tile: the preview cut to the home screen's own corner
    /// radius — a fifth of the side, the continuous curve the mask
    /// itself wears — the picked one ringed in the accent, both named
    /// under. The platform does the swap; nil rides back to the icon
    /// the app was born with.
    private func iconTile(
        name: String?,
        preview: String,
        title: LocalizedStringKey
    ) -> some View {
        let isPicked = currentIcon == name
        let radius = 56 * 0.2237

        return Button {
            UIApplication.shared.setAlternateIconName(name) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    currentIcon = UIApplication.shared.alternateIconName
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(preview)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                isPicked ? Chumpy.accent : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isPicked ? Chumpy.accent : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isPicked ? Chumpy.accent.opacity(0.12) : Chumpy.surfaceContainerLow)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The About page — the settings deck's last leaf: the app's own word
/// on itself, the two versions — the app's and the core's — alone on
/// the card, the page's title in the header already speaking the
/// "About" the old card's header used to carry.
struct AboutView: View {
    var body: some View {
        EdgeScrollView(tag: "about") {
            VStack(spacing: 12) {
                versionsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, chumpyContentTopPadding)
            .padding(.bottom, 104)
        }
    }

    // MARK: - Versions

    private var versionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
        return "\(short ?? "?") (\(build ?? "?"))"
    }
}
