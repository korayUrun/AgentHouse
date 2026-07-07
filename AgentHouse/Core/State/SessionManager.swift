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
    /// Süregelen working turunun başladığı an (done banner eşiği için); tur bitince temizlenir.
    var workingSince: Date? = nil
    /// limit state'indeyken tahmini reset anı; çalışma devam edince temizlenir.
    var limitResetAt: Date? = nil
    /// Oturum kartının oluşturulduğu an (sıralama ve limit penceresi tahmini için).
    let startedAt: Date
}

/// Eşiği aşan bir işin bittiği bilgisi; DoneBanner ve isteğe bağlı sistem bildirimi bunu dinler.
struct LongTaskCompletion: Identifiable, Equatable {
    let id = UUID()
    let sessionId: String
    let projectName: String
    /// working'in başından Stop'a kadar geçen süre (sn).
    let duration: TimeInterval
}

/// Oturumların tek doğruluk kaynağı: event akışını session_id başına Session'a çevirir,
/// done→idle gecikmesini ve stale işaretlemesini yönetir. Ana thread'de kullanılmalıdır.
final class SessionManager: ObservableObject {
    /// Aktif oturumlar, oluşturulma sırasına göre.
    @Published private(set) var sessions: [Session] = []

    /// Eşiği aşan bir working süresinin ardından iş bittiğinde yayınlanır.
    let longTaskCompleted = PassthroughSubject<LongTaskCompletion, Never>()

    /// Stale saymak için gereken inaktivite süresi (sn).
    static let defaultStaleAfter: TimeInterval = 30 * 60

    /// done state'inin idle'a dönmeden önce ekranda kaldığı süre (sn).
    static let defaultDoneToIdleDelay: TimeInterval = 5

    /// Banner/bildirim tetiklemek için gereken minimum working süresi (sn).
    static let defaultLongTaskThreshold: TimeInterval = 30

    private let doneToIdleDelay: TimeInterval
    private let staleAfter: TimeInterval
    private let longTaskThreshold: TimeInterval
    private let now: () -> Date
    private var pendingDoneWork: [String: DispatchWorkItem] = [:]
    private var staleTimer: Timer?
    private let logger = Logger(subsystem: "com.agenthouse.app", category: "SessionManager")

    /// Saat ve süreler testte sahteleriyle değiştirilebilsin diye init'ten enjekte edilir.
    init(
        doneToIdleDelay: TimeInterval = SessionManager.defaultDoneToIdleDelay,
        staleAfter: TimeInterval = SessionManager.defaultStaleAfter,
        longTaskThreshold: TimeInterval = SessionManager.defaultLongTaskThreshold,
        now: @escaping () -> Date = Date.init
    ) {
        self.doneToIdleDelay = doneToIdleDelay
        self.staleAfter = staleAfter
        self.longTaskThreshold = longTaskThreshold
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
        let isLimitSignal = name == .notification && LimitDetector.isLimitNotification(event.message)
        var completion: LongTaskCompletion?

        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            var session = sessions[index]
            let previousState = session.state
            session.state = SessionStateMachine.apply(state: previousState, event: name, isLimitSignal: isLimitSignal)
            session.lastActivity = timestamp
            session.isStale = false
            if let cwd = event.cwd, !cwd.isEmpty {
                session.cwd = cwd
                session.projectName = Self.projectName(fromCwd: cwd)
            }
            completion = updateTracking(&session, previousState: previousState, timestamp: timestamp)
            sessions[index] = session
        } else {
            // Uygulama oturum ortasında açıldıysa SessionStart kaçırılmış olabilir;
            // kart yine de oluşturulur (gözlem best-effort).
            var session = Session(
                id: sessionId,
                projectName: Self.projectName(fromCwd: event.cwd),
                cwd: event.cwd,
                state: SessionStateMachine.apply(state: .idle, event: name, isLimitSignal: isLimitSignal),
                lastActivity: timestamp,
                isStale: false,
                startedAt: timestamp
            )
            completion = updateTracking(&session, previousState: .idle, timestamp: timestamp)
            sessions.append(session)
        }

        if sessions.first(where: { $0.id == sessionId })?.state == .done {
            scheduleDoneToIdle(for: sessionId)
        }
        if let completion {
            longTaskCompleted.send(completion)
        }
    }

    /// State geçişine eşlik eden takip alanlarını (workingSince, limitResetAt) günceller;
    /// eşiği aşan bir iş bittiyse yayınlanacak LongTaskCompletion'ı döndürür.
    private func updateTracking(
        _ session: inout Session,
        previousState: SessionState,
        timestamp: Date
    ) -> LongTaskCompletion? {
        switch session.state {
        case .working:
            // attention arası (izin bekleme) turu bölmesin diye workingSince korunur.
            if session.workingSince == nil {
                session.workingSince = timestamp
            }
            session.limitResetAt = nil
        case .limit:
            if previousState != .limit, session.limitResetAt == nil {
                session.limitResetAt = LimitDetector.estimateReset(windowStart: session.startedAt, now: timestamp)
            }
        case .done:
            defer { session.workingSince = nil }
            if let since = session.workingSince, timestamp.timeIntervalSince(since) >= longTaskThreshold {
                return LongTaskCompletion(
                    sessionId: session.id,
                    projectName: session.projectName,
                    duration: timestamp.timeIntervalSince(since)
                )
            }
        case .idle:
            session.workingSince = nil
            session.limitResetAt = nil
        case .attention:
            break
        }
        return nil
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
