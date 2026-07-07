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
    private var window: NSWindow?

    init(store: EventLogStore) {
        self.store = store
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
        window.contentViewController = NSHostingController(rootView: EventLogView(store: store))
        window.center()
        return window
    }
}

/// Gelen eventleri satır satır listeleyen geçici debug görünümü.
struct EventLogView: View {
    @ObservedObject var store: EventLogStore

    var body: some View {
        VStack(spacing: 0) {
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
