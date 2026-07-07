import AppKit
import SwiftUI

// NOT: Bu dosyanın tamamı Faz 2'ye özgü GEÇİCİ debug arayüzüdür; Faz 4'te
// ayarlardaki gizli "debug log" seçeneğine taşınıp buradan kaldırılacak.

/// Gelen hook eventlerini debug amaçlı tutan geçici store.
final class EventLogStore: ObservableObject {
    /// Tek bir log satırı.
    struct Entry: Identifiable {
        let id = UUID()
        let receivedAt: Date
        let event: HookEvent
    }

    @Published private(set) var entries: [Entry] = []

    private let maxEntries = 500

    /// Yeni bir eventi log'a ekler; kapasite aşılırsa en eski satırlar düşer. Ana thread'de çağrılmalı.
    func append(_ event: HookEvent) {
        entries.append(Entry(receivedAt: Date(), event: event))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    /// Tüm logu temizler.
    func clear() {
        entries.removeAll()
    }
}

/// Debug event log penceresini yöneten geçici denetleyici.
final class EventLogWindowController {
    private let store: EventLogStore
    private let sessionManager: SessionManager
    private var window: NSWindow?

    init(store: EventLogStore, sessionManager: SessionManager) {
        self.store = store
        self.sessionManager = sessionManager
    }

    /// Pencereyi (gerekirse oluşturup) öne getirir.
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AgentHouse — Event Log (Debug)"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: EventLogView(store: store, sessionManager: sessionManager)
        )
        window.center()
        return window
    }
}

/// Gelen eventleri ve canlı oturum state'lerini gösteren geçici debug görünümü.
struct EventLogView: View {
    @ObservedObject var store: EventLogStore
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            SessionDebugListView(sessions: sessionManager.sessions)

            Divider()

            HStack {
                Text("\(store.entries.count) event")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Temizle") {
                    store.clear()
                }
            }
            .padding(10)

            Divider()

            ScrollViewReader { proxy in
                List(store.entries) { entry in
                    EventLogRow(entry: entry)
                        .id(entry.id)
                }
                .listStyle(.plain)
                .onChange(of: store.entries.count) {
                    if let last = store.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 320)
    }
}

/// Event Log'daki tek satır.
private struct EventLogRow: View {
    let entry: EventLogStore.Entry

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Self.timeFormatter.string(from: entry.receivedAt))
                .foregroundStyle(.secondary)
            Text(entry.event.hookEventName ?? "?")
                .fontWeight(.semibold)
                .frame(width: 130, alignment: .leading)
            Text(sessionShortId)
                .foregroundStyle(.secondary)
            Text(detail)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private var sessionShortId: String {
        entry.event.sessionId.map { String($0.prefix(8)) } ?? "--------"
    }

    private var detail: String {
        entry.event.toolName
            ?? entry.event.message
            ?? entry.event.prompt
            ?? entry.event.cwd
            ?? ""
    }
}

/// Aktif oturumları ve canlı state'lerini listeleyen geçici debug bölümü.
private struct SessionDebugListView: View {
    let sessions: [Session]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sessions.isEmpty ? "Oturum yok" : "\(sessions.count) oturum")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(sessions) { session in
                HStack(spacing: 10) {
                    Circle()
                        .fill(color(for: session.state))
                        .frame(width: 8, height: 8)
                    Text(session.projectName)
                        .fontWeight(.semibold)
                    Text(session.state.rawValue + (session.isStale ? " (stale)" : ""))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(session.id.prefix(8)))
                        .foregroundStyle(.tertiary)
                }
                .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for state: SessionState) -> Color {
        switch state {
        case .idle: return .gray
        case .working: return .blue
        case .attention: return .orange
        case .done: return .green
        case .limit: return .purple
        }
    }
}
