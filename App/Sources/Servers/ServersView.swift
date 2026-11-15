import SwiftUI

/// Servers tab: subscriptions and manual profiles.
/// M0 placeholder — filled in M1/M3 with the real profile list.
struct ServersView: View {
    var body: some View {
        NavHost {
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
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("tab.servers")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
