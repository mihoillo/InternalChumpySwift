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
                Haptics.poke()
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
                        Haptics.poke()
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
                Haptics.poke()
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
/// one the original client opens the settings on: the colors card
/// (the theme tiles and the accent row), the app icon row, and the
/// haptic gate.
struct InterfaceView: View {
    /// The app's theme word, the ChumpyApp root reads it and hands the
    /// platform its color scheme: 0 — the system's own, 1 — always
    /// light, 2 — always dark.
    @AppStorage("themeMode") private var themeMode: Int = 0
    /// The accent's own word — the hex the root reads and the whole
    /// app wears. The picker writes it; the root's environment pick
    /// makes every `Color.accentColor` follow live.
    @AppStorage("accentHex") private var accentHex: String = ChumpyAccent.defaultHex
    /// The haptic gate — every poke in the app answers to it.
    @AppStorage("hapticFeedback") private var hapticFeedback: Bool = true
    /// The icon the home screen wears now — the platform's own word,
    /// mirrored here so the picker's ring lands the moment the swap
    /// does. Nil is the icon the app was born with.
    @State private var currentIcon: String?
    /// The word the platform says when a swap refuses — kept here so
    /// the failure stops dying in silence: the ring must not move for a
    /// swap that never happened, and the reason deserves to be read.
    @State private var iconSwapError: String?
    /// The custom accent's own picking sheet — the swatch's tap opens
    /// it, the pick writes the accent.
    @State private var showCustomAccent = false

    /// The error alert's own presence — true while a refusal is being
    /// shown, clearing the word as the alert folds away.
    private var iconSwapErrorShown: Binding<Bool> {
        Binding(
            get: { iconSwapError != nil },
            set: { if !$0 { iconSwapError = nil } }
        )
    }

    var body: some View {
        EdgeScrollView(tag: "interface") {
            VStack(spacing: 12) {
                themeCard
                iconCard
                hapticsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, chumpyContentTopPadding)
            .padding(.bottom, 104)
        }
        .onAppear {
            currentIcon = UIApplication.shared.alternateIconName
        }
        .alert(isPresented: iconSwapErrorShown) {
            Alert(
                title: Text("settings.icon.errorTitle"),
                message: Text(iconSwapError ?? "")
            )
        }
        .sheet(isPresented: $showCustomAccent) {
            CustomAccentSheet(accentHex: $accentHex)
        }
    }

    // MARK: - Theme

    /// The theme card: three tiles — system, light, dark — the picked
    /// one wearing the accent, and the accent row under them — the
    /// original client's own Colors group, one pick under the other.
    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartHeader(icon: "paintpalette", title: "settings.colors")

            HStack(spacing: 8) {
                themeTile(0, icon: "circle.lefthalf.filled", title: "settings.theme.system")
                themeTile(1, icon: "sun.max.fill", title: "settings.theme.light")
                themeTile(2, icon: "moon.fill", title: "settings.theme.dark")
            }

            accentRow
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
            Haptics.poke()
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

    // MARK: - Accent

    /// The accent row, ported from the Android client's `AccentRow`: a
    /// run of round swatches — the seven rainbow hues plus the born sky —
    /// and the custom one at the end, the paint roller over it. The pick's
    /// mark is the accent's own ring, a breath off the color; the custom
    /// swatch opens its own picking sheet.
    private var accentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(AccentPreset.allCases) { preset in
                    accentSwatch(
                        color: preset.color,
                        label: preset.titleKey,
                        isSelected: accentHex.caseInsensitiveCompare(preset.hex) == .orderedSame
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            accentHex = preset.hex
                        }
                    }
                }
                accentSwatch(
                    color: ChumpyAccent.color(hex: accentHex),
                    label: "settings.accent.custom",
                    isSelected: !AccentPreset.allCases.contains { preset in
                        accentHex.caseInsensitiveCompare(preset.hex) == .orderedSame
                    },
                    marksCustom: true
                ) {
                    showCustomAccent = true
                }
            }
            .padding(.vertical, 6)
        }
    }

    /// One swatch: the 48pt color in a 60pt wrapper, the pick's ring a
    /// breath off it — never touching — while the color itself yields a
    /// little under the ring, so the marked swatch reads no bigger than
    /// its neighbors. The custom one wears the paint roller over its
    /// color, in the color's own opposite.
    private func accentSwatch(
        color: Color,
        label: LocalizedStringKey,
        isSelected: Bool,
        marksCustom: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.poke()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 48, height: 48)
                    .scaleEffect(isSelected ? 0.85 : 1)
                if marksCustom {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ChumpyAccent.isLight(color) ? Color.black : Color.white)
                }
                if isSelected {
                    Circle()
                        .stroke(Chumpy.accent, lineWidth: 3)
                        .frame(width: 54, height: 54)
                }
            }
            .frame(width: 60, height: 60)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
            .accessibilityLabel(Text(label))
        }
        .buttonStyle(.plain)
    }

    // MARK: - App icon

    /// The app icon card, the original client's own row: the setting's
    /// name over the picked variant's on the left, the two faces the app
    /// wears on the home screen beside each other on the right — no
    /// tiles under them, the previews alone. A pick asks the platform
    /// to swap the icon; the platform answers with its own confirmation
    /// dialog, the one word iOS never lets an app skip.
    private var iconCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("settings.appIcon")
                    .font(.system(size: 15))
                Text(selectedIconTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                iconPreview(
                    name: nil,
                    preview: "icon-preview-chumpy"
                )
                iconPreview(
                    name: "AppIconInverted",
                    preview: "icon-preview-inverted"
                )
            }
        }
        .padding(16)
        .chumpyCard()
    }

    /// The picked variant's own name, under the setting's.
    private var selectedIconTitle: LocalizedStringKey {
        currentIcon == nil ? "settings.icon.chumpy" : "settings.icon.inverted"
    }

    /// One icon preview: the face cut to the home screen's own corner
    /// radius — a fifth of the side, the continuous curve the mask
    /// itself wears — the picked one ringed in the accent, a breath off
    /// the icon. The platform does the swap; nil rides back to the icon
    /// the app was born with.
    private func iconPreview(name: String?, preview: String) -> some View {
        let isPicked = currentIcon == name
        let radius = 56 * 0.2237
        let title: LocalizedStringKey = name == nil
            ? "settings.icon.chumpy"
            : "settings.icon.inverted"

        return Button {
            Haptics.poke()
            UIApplication.shared.setAlternateIconName(name) { error in
                // A refusal keeps the ring where it was and speaks its
                // reason instead — the old way swallowed the error and
                // moved the ring anyway, wearing a face the home screen
                // never put on.
                if let error {
                    iconSwapError = error.localizedDescription
                    return
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    currentIcon = UIApplication.shared.alternateIconName
                }
            }
        } label: {
            ZStack {
                Image(preview)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .scaleEffect(isPicked ? 0.9 : 1)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                if isPicked {
                    RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                        .stroke(Chumpy.accent, lineWidth: 2)
                        .frame(width: 62, height: 62)
                }
            }
            .frame(width: 64, height: 64)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPicked)
            .accessibilityLabel(Text(title))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Haptics

    /// The haptic gate's own card — the original client's own block,
    /// right under the interface's other words.
    private var hapticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { hapticFeedback },
                set: { enabled in
                    // The poke runs before the gate flips: turning off
                    // still feels the last poke, turning on stays silent.
                    Haptics.poke()
                    hapticFeedback = enabled
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.haptics")
                        .font(.system(size: 15))
                    Text("settings.haptics.hint")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
            }
            .tint(Chumpy.accent)
        }
        .padding(16)
        .chumpyCard()
    }
}

/// The fixed accents, the Android client's own rainbow hues — the sky
/// among them, the app's born one. The wallpaper seeds, adaptive and
/// rainbow have no iOS counterpart and stay home.
private enum AccentPreset: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, sky, blue, indigo, violet

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .red: return "#D8625A"
        case .orange: return "#D8995A"
        case .yellow: return "#D8C75A"
        case .green: return "#5AD88E"
        case .sky: return "#6FACED"
        case .blue: return "#5A8AD8"
        case .indigo: return "#6B5AD8"
        case .violet: return "#B95AD8"
        }
    }

    var color: Color {
        ChumpyAccent.color(hex: hex)
    }

    /// The swatch's own name, spoken to accessibility — the Android
    /// client's content description.
    var titleKey: LocalizedStringKey {
        switch self {
        case .red: return "settings.accent.red"
        case .orange: return "settings.accent.orange"
        case .yellow: return "settings.accent.yellow"
        case .green: return "settings.accent.green"
        case .sky: return "settings.accent.sky"
        case .blue: return "settings.accent.blue"
        case .indigo: return "settings.accent.indigo"
        case .violet: return "settings.accent.violet"
        }
    }
}

/// The custom accent's own sheet: the platform's color picker over a
/// hex field — the wheel and the word, the Android dialog's two halves.
/// The pick writes the accent; cancel leaves everything as it was.
private struct CustomAccentSheet: View {
    @Binding var accentHex: String
    @Environment(\.dismiss) private var dismiss

    @State private var color: Color
    @State private var hexText: String

    init(accentHex: Binding<String>) {
        _accentHex = accentHex
        let initial = ChumpyAccent.color(hex: accentHex.wrappedValue)
        _color = State(initialValue: initial)
        _hexText = State(initialValue: initial.hexString)
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("settings.accent.customTitle")
                .font(.system(size: 16, weight: .semibold))

            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .frame(height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text("settings.accent.customHex")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                TextField("#6FACED", text: $hexText)
                    .font(.system(size: 15, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Chumpy.surfaceContainerLow)
                    )
            }

            HStack(spacing: 8) {
                Button {
                    Haptics.poke()
                    dismiss()
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
                    accentHex = color.hexString
                    dismiss()
                } label: {
                    Text("settings.accent.customPick")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Chumpy.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Capsule().fill(Chumpy.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .onChange(of: color) { hexText = $0.hexString }
        .onChange(of: hexText) { text in
            if let picked = Color(hex: text) { color = picked }
        }
    }
}

/// The About page — the settings deck's last leaf, and the one the
/// gear lands on: the original client's own welcome hero turned
/// upright — the app's icon big at the top, its name under it, the
/// tagline under that — then the build's own numbers and the
/// project's two homes.
struct AboutView: View {
    var body: some View {
        EdgeScrollView(tag: "about") {
            VStack(alignment: .leading, spacing: 16) {
                hero
                    .padding(.bottom, 8)
                versionsCard
                linksCard
            }
            .padding(.horizontal, 16)
            .padding(.top, chumpyContentTopPadding)
            .padding(.bottom, 104)
        }
    }

    // MARK: - Hero

    /// The mark, the name, the one-liner — bare on the page, the way
    /// the original client's hero stands.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(currentIconPreview)
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 96 * 0.2237, style: .continuous))
                .padding(.bottom, 12)
            Text("Chumpy")
                .font(.system(size: 34, weight: .bold))
            Text("settings.about.tagline")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }

    /// The hero wears the icon the home screen currently wears.
    private var currentIconPreview: String {
        UIApplication.shared.alternateIconName == "AppIconInverted"
            ? "icon-preview-inverted"
            : "icon-preview-chumpy"
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

    // MARK: - The project's homes

    /// The project's two homes, the original client's own link rows:
    /// the brand's own glyph beside the title and the handle — the
    /// row goes out, nothing unfolds here.
    private var linksCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            linkRow(
                title: "settings.about.telegram",
                handle: "t.me/ChumpyXray",
                icon: "brand-telegram",
                url: "https://t.me/ChumpyXray"
            )
            linkRow(
                title: "settings.about.github",
                handle: "github.com/ChumpyXray/Chumpy",
                icon: "brand-github",
                url: "https://github.com/ChumpyXray/Chumpy"
            )
        }
        .padding(16)
        .chumpyCard()
    }

    private func linkRow(title: LocalizedStringKey, handle: String, icon: String, url: String) -> some View {
        Button {
            Haptics.poke()
            if let link = URL(string: url) { UIApplication.shared.open(link) }
        } label: {
            HStack(spacing: 12) {
                Image(icon)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Chumpy.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Text(handle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
