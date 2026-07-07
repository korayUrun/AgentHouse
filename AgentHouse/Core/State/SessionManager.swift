import Combine
import Foundation
import os

/// Tek bir Claude Code oturumunun uygulama içinde tutulan anlık görünümü.
struct Session: Identifiable, Equatable {
    /// Claude Code'un session_id'si.
    let id: String
    /// cwd'nin son klasör adından türetilen görünen ad.
    var projectName: String
    /// Oturumun çalışma dizini (payload'da geldiyse).
    var cwd: String?
    /// Güncel state; geçişler yalnızca SessionStateMachine üzerinden yapılır.
    var state: SessionState
    /// Bu oturum için son event'in alındığı an.
    var lastActivity: Date
    /// 30 dk (varsayılan) event gelmediyse true; yeni event gelince sıfırlanır.
    var isStale: Bool
    /// Oturum kartının oluşturulduğu an (sıralama için).
    let startedAt: Date
}

/// Oturumların tek doğruluk kaynağı: event akışını session_id başına Session'a çevirir,
/// done→idle gecikmesini ve stale işaretlemesini yönetir. Ana thread'de kullanılmalıdır.
final class SessionManager: ObservableObject {
    /// Aktif oturumlar, oluşturulma sırasına göre.
    @Published private(set) var sessions: [Session] = []

    /// Stale saymak için gereken inaktivite süresi (sn).
    static let defaultStaleAfter: TimeInterval = 30 * 60

    /// done state'inin idle'a dönmeden önce ekranda kaldığı süre (sn).
    static let defaultDoneToIdleDelay: TimeInterval = 5

    private let doneToIdleDelay: TimeInterval
    private let staleAfter: TimeInterval
    private let now: () -> Date
    private var pendingDoneWork: [String: DispatchWorkItem] = [:]
    private var staleTimer: Timer?
    private let logger = Logger(subsystem: "com.agenthouse.app", category: "SessionManager")

    /// Saat ve süreler testte sahteleriyle değiştirilebilsin diye init'ten enjekte edilir.
    init(
        doneToIdleDelay: TimeInterval = SessionManager.defaultDoneToIdleDelay,
        staleAfter: TimeInterval = SessionManager.defaultStaleAfter,
        now: @escaping () -> Date = Date.init
    ) {
        self.doneToIdleDelay = doneToIdleDelay
        self.staleAfter = staleAfter
        self.now = now
    }

    deinit {
        staleTimer?.invalidate()
        pendingDoneWork.values.forEach { $0.cancel() }
    }

    /// Stale kontrolünü periyodik çalıştıran timer'ı kurar (uygulama tarafında bir kez çağrılır).
    func startStaleMonitoring(interval: TimeInterval = 60) {
        staleTimer?.invalidate()
        staleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshStaleness()
        }
    }

    /// Gelen hook eventini ilgili oturuma uygular. Ana thread'de çağrılmalı.
    func handle(_ event: HookEvent) {
        guard let name = event.name else {
            logger.debug("Bilinmeyen event adı yok sayıldı: \(event.hookEventName ?? "nil", privacy: .public)")
            return
        }
        guard let sessionId = event.sessionId, !sessionId.isEmpty else {
            logger.debug("session_id'siz event yok sayıldı: \(name.rawValue, privacy: .public)")
            return
        }

        // Yeni bir event, bekleyen done→idle geçişini geçersiz kılar.
        cancelPendingDoneWork(for: sessionId)

        guard name != .sessionEnd else {
            sessions.removeAll { $0.id == sessionId }
            return
        }

        let timestamp = now()
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            var session = sessions[index]
            session.state = SessionStateMachine.apply(state: session.state, event: name)
            session.lastActivity = timestamp
            session.isStale = false
            if let cwd = event.cwd, !cwd.isEmpty {
                session.cwd = cwd
                session.projectName = Self.projectName(fromCwd: cwd)
            }
            sessions[index] = session
        } else {
            // Uygulama oturum ortasında açıldıysa SessionStart kaçırılmış olabilir;
            // kart yine de oluşturulur (gözlem best-effort).
            sessions.append(Session(
                id: sessionId,
                projectName: Self.projectName(fromCwd: event.cwd),
                cwd: event.cwd,
                state: SessionStateMachine.apply(state: .idle, event: name),
                lastActivity: timestamp,
                isStale: false,
                startedAt: timestamp
            ))
        }

        if sessions.first(where: { $0.id == sessionId })?.state == .done {
            scheduleDoneToIdle(for: sessionId)
        }
    }

    /// lastActivity'si eşiği aşan oturumları stale işaretler. Timer ve testler çağırır.
    func refreshStaleness() {
        let threshold = now().addingTimeInterval(-staleAfter)
        for index in sessions.indices where !sessions[index].isStale {
            if sessions[index].lastActivity < threshold {
                sessions[index].isStale = true
            }
        }
    }

    /// cwd'nin son klasör adını görünen proje adına çevirir; cwd yoksa "?".
    static func projectName(fromCwd cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "?" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    // MARK: - done→idle gecikmesi

    private func scheduleDoneToIdle(for sessionId: String) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingDoneWork.removeValue(forKey: sessionId)
            if let index = self.sessions.firstIndex(where: { $0.id == sessionId }) {
                self.sessions[index].state = SessionStateMachine.applyDoneTimeout(state: self.sessions[index].state)
            }
        }
        pendingDoneWork[sessionId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + doneToIdleDelay, execute: work)
    }

    private func cancelPendingDoneWork(for sessionId: String) {
        pendingDoneWork.removeValue(forKey: sessionId)?.cancel()
    }
}
