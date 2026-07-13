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
    /// Oturumu başlatan uygulamanın bundle id'si (SessionStart/UserPromptSubmit anındaki
    /// önplan uygulamasından best-effort tespit); karta tıklayınca öne getirilir.
    var sourceBundleId: String? = nil
    /// Güncel state; geçişler yalnızca SessionStateMachine üzerinden yapılır.
    var state: SessionState
    /// Bu oturum için son event'in alındığı an.
    var lastActivity: Date
    /// 30 dk (varsayılan) event gelmediyse true; yeni event gelince sıfırlanır.
    var isStale: Bool
    /// Süregelen working turunun başladığı an (done banner eşiği için); tur bitince temizlenir.
    var workingSince: Date? = nil
    /// UsageReader'dan gelen birikmiş token/maliyet; transcript izlenemiyorsa nil.
    var usage: SessionUsage? = nil
    /// Oturum kartının oluşturulduğu an (sıralama için).
    let startedAt: Date
}

extension Session {
    /// Kalıcı proje tercihleri (maskot, küme) için anahtar: cwd (kalıcı ve benzersiz);
    /// cwd bilinmiyorsa proje adına düşer, o da yoksa nil (tercih kaydedilmez).
    var projectKey: String? {
        if let cwd, !cwd.isEmpty { return cwd }
        return projectName == "?" ? nil : projectName
    }
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

    /// Done-banner eşiğinin saklandığı UserDefaults anahtarı (yalnızca UI tercihi; kural 2).
    static let longTaskThresholdDefaultsKey = "doneBannerThresholdSeconds"

    /// Ayarlardaki done-banner eşiğini okur; yoksa veya geçersizse varsayılanı döndürür.
    static func configuredLongTaskThreshold(defaults: UserDefaults = .standard) -> TimeInterval {
        let stored = defaults.double(forKey: longTaskThresholdDefaultsKey)
        return stored > 0 ? stored : defaultLongTaskThreshold
    }

    private let doneToIdleDelay: TimeInterval
    private let staleAfter: TimeInterval
    private var longTaskThreshold: TimeInterval
    private let now: () -> Date
    private let frontmostApp: () -> String?
    private var pendingDoneWork: [String: DispatchWorkItem] = [:]
    private var staleTimer: Timer?
    private let logger = Logger(subsystem: "com.agenthouse.app", category: "SessionManager")

    /// Saat, süreler ve önplan uygulaması sorgusu testte sahteleriyle değiştirilebilsin
    /// diye init'ten enjekte edilir.
    init(
        doneToIdleDelay: TimeInterval = SessionManager.defaultDoneToIdleDelay,
        staleAfter: TimeInterval = SessionManager.defaultStaleAfter,
        longTaskThreshold: TimeInterval = SessionManager.defaultLongTaskThreshold,
        now: @escaping () -> Date = Date.init,
        frontmostApp: @escaping () -> String? = { nil }
    ) {
        self.doneToIdleDelay = doneToIdleDelay
        self.staleAfter = staleAfter
        self.longTaskThreshold = longTaskThreshold
        self.now = now
        self.frontmostApp = frontmostApp
    }

    /// Done-banner eşiğini günceller (ayarlardan değiştirilebilir); sonraki
    /// tamamlanmalara uygulanır. Ana thread'de çağrılmalı.
    func setLongTaskThreshold(_ threshold: TimeInterval) {
        longTaskThreshold = threshold
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
        // ADR-015: Claude'un kullanıcıya soru sorması; tool adı sinyali metin
        // ayrıştırmadan güvenilirdir.
        let isQuestionSignal = name == .preToolUse && event.toolName == "AskUserQuestion"
        // Oturum-ortası compact aynı session_id ile SessionStart yollar; bu bir "yeni
        // oturum" değildir, state ve tur korunur (ADR-018).
        let isContinuation = name == .sessionStart && event.source == "compact"
        // Kaynak uygulama, kullanıcının o an içinde olduğu kesin olan anlarda yakalanır;
        // tool eventlerinde kullanıcı başka uygulamaya geçmiş olabilir. Compact anında da
        // yakalanmaz — kullanıcı başka uygulamada olabilir, terminal bağı bozulmasın.
        let sourceBundleId = ((name == .sessionStart && !isContinuation) || name == .userPromptSubmit)
            ? frontmostApp()
            : nil
        var completion: LongTaskCompletion?

        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            var session = sessions[index]
            let previousState = session.state
            session.state = SessionStateMachine.apply(
                state: previousState,
                event: name,
                isLimitSignal: isLimitSignal,
                isQuestionSignal: isQuestionSignal,
                isContinuation: isContinuation
            )
            session.lastActivity = timestamp
            session.isStale = false
            if let cwd = event.cwd, !cwd.isEmpty {
                session.cwd = cwd
                session.projectName = Self.projectName(fromCwd: cwd)
            }
            if let sourceBundleId {
                session.sourceBundleId = sourceBundleId
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
                sourceBundleId: sourceBundleId,
                state: SessionStateMachine.apply(
                    state: .idle,
                    event: name,
                    isLimitSignal: isLimitSignal,
                    isQuestionSignal: isQuestionSignal,
                    isContinuation: isContinuation
                ),
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

    /// State geçişine eşlik eden takip alanlarını (workingSince) günceller;
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
        case .limit, .attention, .questioning:
            // Bekleme araları (izin/soru) turu bölmesin diye workingSince korunur.
            break
        }
        return nil
    }

    /// UsageReader'dan gelen birikmiş usage'ı oturuma yazar. Oturum yoksa yok sayılır
    /// (usage tek başına kart oluşturmaz — kartın sahibi hook akışıdır). Ana thread'de çağrılmalı.
    func updateUsage(_ usage: SessionUsage, forSession sessionId: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].usage = usage
    }

    /// UsageReader'ın canlı JSONL rate-limit izi için limit sinyali uygular
    /// (Notification tabanlı tespit handle(_:) içindedir). Ana thread'de çağrılmalı.
    func applyLimitSignal(toSession sessionId: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        cancelPendingDoneWork(for: sessionId)
        sessions[index].state = SessionStateMachine.applyLimitSignal(state: sessions[index].state)
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
