import SwiftUI

/// Rive maskotu gelene kadar kartta duran boş daire placeholder; Faz 5'te
/// RiveMascotView ile değiştirilecek (ADR-009).
struct PlaceholderMascotView: View {
    let state: SessionState

    var body: some View {
        ZStack {
            Circle()
                .fill(state.tint.opacity(0.18))
            Circle()
                .strokeBorder(state.tint.opacity(0.5), lineWidth: 1.5)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(SessionState.allCases, id: \.self) { state in
            PlaceholderMascotView(state: state)
                .frame(width: 48, height: 48)
        }
    }
    .padding()
}
