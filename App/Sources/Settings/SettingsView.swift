import SwiftUI
import ChumpyCore

/// Settings tab. Connection section writes directly to the shared defaults
/// consumed by the tunnel on next connect; richer sections arrive in M3.
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

    var body: some View {
        NavHost {
            Form {
                Section("settings.connection") {
                    Picker("settings.routing", selection: $routingMode) {
                        ForEach(RoutingMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.localizationKey))
                                .tag(mode.rawValue)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("settings.testURL")
                        TextField("https://…", text: $testURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(.secondary)
                    }
                }

                Section("settings.tunnel") {
                    LabeledRow2(label: "settings.status", value: statusText)
                    Button("settings.reinstallProfile", role: .destructive) {
                        Task {
                            try? await appState.removeFromPreferences()
                            await appState.reload()
                        }
                    }
                }

                Section("settings.about") {
                    LabeledRow2(
                        label: "settings.appVersion",
                        value: appVersion
                    )
                    LabeledRow2(
                        label: "settings.coreVersion",
                        value: "Xray (libXray-apple v26.3.27)"
                    )
                }
            }
            .navigationTitle("tab.settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusText: String {
        switch appState.status {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .reasserting: return "Reasserting…"
        default: return "Disconnected"
        }
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
        return "\(short ?? "?") (\(build ?? "?"))"
    }
}

private struct LabeledRow2: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
