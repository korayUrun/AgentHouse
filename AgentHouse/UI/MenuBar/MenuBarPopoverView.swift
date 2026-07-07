import SwiftUI

/// Menü bar popover içeriği: aktif oturum özeti ve usage dökümü (ADR-013 gereği
/// usage burada gösterilir, kartta değil) + panel/ayarlar/çıkış eylemleri.
struct MenuBarPopoverView: View {
    @ObservedObject var sessionManager: SessionManager
    /// Panelin o anki görünürlüğü; buton etiketi popover her açılışında tazelenir.
    var isPanelVisible: () -> Bool = { true }
    var togglePanel: () -> Void = {}
    var openSettings: () -> Void = {}

    @State private var panelVisible = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AgentHouse")
                .font(.headline)

            Divider()

            if sessionManager.sessions.isEmpty {
                Text("Aktif oturum yok")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sessionManager.sessions) { session in
                        sessionRow(session)
                    }
                }
            }

            Divider()

            actionButton(
                panelVisible ? "Paneli Gizle" : "Paneli Göster",
                systemImage: panelVisible ? "eye.slash" : "eye"
            ) {
                togglePanel()
                panelVisible = isPanelVisible()
            }
            actionButton("Ayarlar…", systemImage: "gearshape") {
                openSettings()
            }
            actionButton("AgentHouse'u Kapat", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { panelVisible = isPanelVisible() }
    }

    private func sessionRow(_ session: Session) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(session.state.tint)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }

            VStack(alignment: .leading, spacing: 1) {
                Text(session.projectName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(session.state.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(session.state.tint)
            }

            Spacer(minLength: 8)

            // Usage dökümü; transcript izlenemiyorsa satır usage'sız kalır (best-effort).
            if let usage = session.usage {
                Text(usage.compactDisplayText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(session.isStale ? 0.45 : 1)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.callout)
    }
}

#Preview {
    MenuBarPopoverView(sessionManager: SessionManager())
}
