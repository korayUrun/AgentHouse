import SwiftUI

/// Overlay panelinin SwiftUI kök görünümü; Faz 1'de yarı saydam bir placeholder gösterir.
struct OverlayRootView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
            )
            .overlay(
                Text("AgentHouse")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            )
            .padding(8)
    }
}

#Preview {
    OverlayRootView()
        .frame(width: 320, height: 140)
}
