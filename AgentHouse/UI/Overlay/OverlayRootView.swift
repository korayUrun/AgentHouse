import SwiftUI

/// Overlay panelinin SwiftUI kök görünümü: aktif oturum kartlarını yatay dizer
/// ve içeriğin ideal boyutunu panele bildirir (panel içeriğe göre boyutlanır).
struct OverlayRootView: View {
    @ObservedObject var sessionManager: SessionManager
    /// Panel görünürlüğü; gizliyken maskot animasyonları durdurulur.
    @ObservedObject var visibility = OverlayContentVisibility()
    /// İçeriğin ideal boyutu değiştiğinde çağrılır; OverlayPanel bununla kendini
    /// yeniden boyutlandırır.
    var onContentSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        content
            .padding(10)
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(ContentSizePreferenceKey.self, perform: onContentSizeChange)
            .animation(
                .spring(response: 0.35, dampingFraction: 0.8),
                value: sessionManager.sessions.map(\.id)
            )
            .environment(\.mascotAnimationsPaused, !visibility.isVisible)
    }

    @ViewBuilder
    private var content: some View {
        if sessionManager.sessions.isEmpty {
            Text("Oturum bekleniyor…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(sessionManager.sessions) { session in
                    SessionCardView(session: session)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
    }
}

/// İçeriğin ideal boyutunu köke taşıyan preference anahtarı.
private struct ContentSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

#Preview("3 oturum") {
    OverlayRootView(sessionManager: .previewWithThreeSessions)
        .padding()
}

private extension SessionManager {
    /// Yalnızca SwiftUI preview'ları için üç örnek oturumlu manager.
    static var previewWithThreeSessions: SessionManager {
        let manager = SessionManager()
        for (id, cwd, event) in [
            ("a", "/Users/dev/AgentHouse", "UserPromptSubmit"),
            ("b", "/Users/dev/blog", "Notification"),
            ("c", "/Users/dev/side-project", "Stop"),
        ] {
            manager.handle(HookEvent(
                hookEventName: event,
                sessionId: id,
                transcriptPath: nil,
                cwd: cwd,
                toolName: nil,
                message: nil,
                prompt: nil,
                source: nil,
                reason: nil
            ))
        }
        return manager
    }
}
