import Combine
import XCTest
@testable import AgentHouse

/// SessionManager'ın oturum yaşam döngüsünü (oluşturma, state güncelleme, done→idle,
/// stale, silme) enjekte edilmiş saat ve kısa gecikmelerle doğrular.
final class SessionManagerTests: XCTestCase {
    /// Testlerin ilerletebildiği sahte saat.
    private var currentDate = Date(timeIntervalSince1970: 1_000_000)

    private func makeManager(
        doneToIdleDelay: TimeInterval = 0.05,
        longTaskThreshold: TimeInterval = SessionManager.defaultLongTaskThreshold
    ) -> SessionManager {
        SessionManager(
            doneToIdleDelay: doneToIdleDelay,
            longTaskThreshold: longTaskThreshold,
            now: { self.currentDate }
        )
    }

    private func event(
        _ name: String,
        session: String? = "s1",
        cwd: String? = nil,
        message: String? = nil,
        toolName: String? = nil,
        source: String? = nil
    ) -> HookEvent {
        var fields: [String: Any] = ["hook_event_name": name]
        fields["session_id"] = session
        fields["cwd"] = cwd
        fields["message"] = message
        fields["tool_name"] = toolName
        fields["source"] = source
        let data = try! JSONSerialization.data(withJSONObject: fields)
        return try! JSONDecoder().decode(HookEvent.self, from: data)
    }

    // MARK: - Questioning sinyali (ADR-015)

    func testAskUserQuestionToolYieldsQuestioningState() {
        let manager = makeManager()
        manager.handle(event("UserPromptSubmit"))
        manager.handle(event("PreToolUse", toolName: "AskUserQuestion"))

        XCTAssertEqual(manager.sessions.first?.state, .questioning)

        // Cevap gelince (PostToolUse) working'e döner; tur bölünmemiştir.
        manager.handle(event("PostToolUse", toolName: "AskUserQuestion"))
        XCTAssertEqual(manager.sessions.first?.state, .working)
        XCTAssertNotNil(manager.sessions.first?.workingSince)
    }

    func testOtherToolsDoNotYieldQuestioning() {
        let manager = makeManager()
        manager.handle(event("PreToolUse", toolName: "Bash"))

        XCTAssertEqual(manager.sessions.first?.state, .working)
    }

    // MARK: - Oturum-ortası compact (ADR-018)

    func testCompactSessionStartDoesNotResetWorkingSession() {
        let manager = makeManager()
        manager.handle(event("UserPromptSubmit"))
        XCTAssertEqual(manager.sessions[0].state, .working)
        let workingSince = manager.sessions[0].workingSince
        XCTAssertNotNil(workingSince)

        // Auto-compact aynı session_id ile SessionStart(source: compact) yollar; çalışan
        // kart idle'a düşmemeli ve workingSince (done-banner eşiği) sıfırlanmamalı.
        manager.handle(event("SessionStart", source: "compact"))
        XCTAssertEqual(manager.sessions[0].state, .working)
        XCTAssertEqual(manager.sessions[0].workingSince, workingSince)
    }

    func testNormalSessionStartStillResetsToIdle() {
        let manager = makeManager()
        manager.handle(event("UserPromptSubmit"))
        // source=startup (veya alan yok) yeni tur başlangıcıdır; idle'a döner.
        manager.handle(event("SessionStart", source: "startup"))
        XCTAssertEqual(manager.sessions[0].state, .idle)
    }

    func testCompactSessionStartDoesNotOverwriteSourceApp() {
        // Compact anında kullanıcı başka uygulamada olabilir; terminal bağı bozulmamalı.
        var frontmost: String? = "com.apple.Terminal"
        let manager = makeManager(frontmostApp: { frontmost })
        manager.handle(event("SessionStart"))
        manager.handle(event("UserPromptSubmit"))

        frontmost = "com.apple.Safari"
        manager.handle(event("SessionStart", source: "compact"))
        XCTAssertEqual(manager.sessions[0].sourceBundleId, "com.apple.Terminal")
    }

    // MARK: - Oturum oluşturma ve proje adı

    func testSessionStartCreatesIdleSessionWithProjectName() {
        let manager = makeManager()
        manager.handle(event("SessionStart", cwd: "/Users/x/Desktop/AgentHouse"))

        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.sessions[0].id, "s1")
        XCTAssertEqual(manager.sessions[0].state, .idle)
        XCTAssertEqual(manager.sessions[0].projectName, "AgentHouse")
        XCTAssertFalse(manager.sessions[0].isStale)
    }

    func testTwoSessionsInDifferentFoldersShowAsSeparateCards() {
        let manager = makeManager()
        manager.handle(event("SessionStart", session: "s1", cwd: "/Users/x/proje-a"))
        manager.handle(event("SessionStart", session: "s2", cwd: "/Users/x/proje-b"))
        manager.handle(event("UserPromptSubmit", session: "s2"))

        XCTAssertEqual(manager.sessions.map(\.projectName), ["proje-a", "proje-b"])
        XCTAssertEqual(manager.sessions.map(\.state), [.idle, .working])
    }

    func testEventWithoutPriorSessionStartStillCreatesCard() {
        // Uygulama oturum ortasında açılırsa SessionStart kaçmış olabilir.
        let manager = makeManager()
        manager.handle(event("PreToolUse", cwd: "/Users/x/proje"))

        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.sessions[0].state, .working)
        XCTAssertEqual(manager.sessions[0].projectName, "proje")
    }

    func testLaterEventWithCwdFillsMissingProjectName() {
        let manager = makeManager()
        manager.handle(event("UserPromptSubmit"))
        XCTAssertEqual(manager.sessions[0].projectName, "?")

        manager.handle(event("PreToolUse", cwd: "/Users/x/proje"))
        XCTAssertEqual(manager.sessions[0].projectName, "proje")
    }

    func testProjectNameDerivation() {
        XCTAssertEqual(SessionManager.projectName(fromCwd: "/Users/x/Desktop/AgentHouse"), "AgentHouse")
        XCTAssertEqual(SessionManager.projectName(fromCwd: "/"), "/")
        XCTAssertEqual(SessionManager.projectName(fromCwd: nil), "?")
        XCTAssertEqual(SessionManager.projectName(fromCwd: ""), "?")
    }

    // MARK: - Geçersiz eventler

    func testEventWithoutSessionIdIsIgnored() {
        let manager = makeManager()
        manager.handle(event("SessionStart", session: nil))
        XCTAssertTrue(manager.sessions.isEmpty)
    }

    func testUnknownEventNameIsIgnored() {
        let manager = makeManager()
        manager.handle(event("SubagentStop"))
        XCTAssertTrue(manager.sessions.isEmpty)
    }

    // MARK: - Yaşam döngüsü

    func testAttentionThenToolUseSyncsBackToWorking() {
        let manager = makeManager()
        manager.handle(event("SessionStart"))
        manager.handle(event("UserPromptSubmit"))
        manager.handle(event("Notification"))
        XCTAssertEqual(manager.sessions[0].state, .attention)

        manager.handle(event("PreToolUse"))
        XCTAssertEqual(manager.sessions[0].state, .working)
    }

    func testSessionEndRemovesCard() {
        let manager = makeManager()
        manager.handle(event("SessionStart", session: "s1"))
        manager.handle(event("SessionStart", session: "s2"))
        manager.handle(event("SessionEnd", session: "s1"))

        XCTAssertEqual(manager.sessions.map(\.id), ["s2"])
    }

    // MARK: - done → idle gecikmesi

    func testStopBecomesDoneThenIdleAfterDelay() {
        let manager = makeManager(doneToIdleDelay: 0.05)
        manager.handle(event("SessionStart"))
        manager.handle(event("UserPromptSubmit"))
        manager.handle(event("Stop"))
        XCTAssertEqual(manager.sessions[0].state, .done)

        let idle = expectation(description: "done → idle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if manager.sessions.first?.state == .idle { idle.fulfill() }
        }
        wait(for: [idle], timeout: 1)
    }

    func testNewPromptCancelsPendingDoneToIdle() {
        let manager = makeManager(doneToIdleDelay: 0.05)
        manager.handle(event("SessionStart"))
        manager.handle(event("Stop"))
        manager.handle(event("UserPromptSubmit"))
        XCTAssertEqual(manager.sessions[0].state, .working)

        let stillWorking = expectation(description: "gecikme dolunca hâlâ working")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if manager.sessions.first?.state == .working { stillWorking.fulfill() }
        }
        wait(for: [stillWorking], timeout: 1)
    }

    // MARK: - Stale

    func testSessionBecomesStaleAfterInactivityAndRecoversOnNewEvent() {
        let manager = makeManager()
        manager.handle(event("SessionStart"))

        // 31 dk ilerlet: stale işaretlenmeli.
        currentDate = currentDate.addingTimeInterval(31 * 60)
        manager.refreshStaleness()
        XCTAssertTrue(manager.sessions[0].isStale)

        // Yeni event stale'i temizlemeli.
        manager.handle(event("UserPromptSubmit"))
        XCTAssertFalse(manager.sessions[0].isStale)
    }

    func testSessionIsNotStaleBeforeThreshold() {
        let manager = makeManager()
        manager.handle(event("SessionStart"))

        currentDate = currentDate.addingTimeInterval(29 * 60)
        manager.refreshStaleness()
        XCTAssertFalse(manager.sessions[0].isStale)
    }

    // MARK: - Uzun iş bildirimi (done banner)

    /// Yayınlanan tamamlamaları toplayarak verilen senaryoyu koşturur.
    private func collectCompletions(
        from manager: SessionManager,
        during scenario: () -> Void
    ) -> [LongTaskCompletion] {
        var completions: [LongTaskCompletion] = []
        let cancellable = manager.longTaskCompleted.sink { completions.append($0) }
        scenario()
        cancellable.cancel()
        return completions
    }

    func testLongTaskPublishesCompletionOnStop() {
        let manager = makeManager(longTaskThreshold: 30)
        let completions = collectCompletions(from: manager) {
            manager.handle(event("SessionStart", cwd: "/Users/x/proje"))
            manager.handle(event("UserPromptSubmit"))
            currentDate = currentDate.addingTimeInterval(45)
            manager.handle(event("Stop"))
        }

        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.sessionId, "s1")
        XCTAssertEqual(completions.first?.projectName, "proje")
        XCTAssertEqual(completions.first?.duration ?? 0, 45, accuracy: 0.001)
    }

    func testShortTaskDoesNotPublishCompletion() {
        let manager = makeManager(longTaskThreshold: 30)
        let completions = collectCompletions(from: manager) {
            manager.handle(event("SessionStart"))
            manager.handle(event("UserPromptSubmit"))
            currentDate = currentDate.addingTimeInterval(10)
            manager.handle(event("Stop"))
        }

        XCTAssertTrue(completions.isEmpty)
    }

    func testAttentionPauseDoesNotSplitWorkingDuration() {
        // İzin bekleme (attention) turu bölmez: süre ilk working'den Stop'a ölçülür.
        let manager = makeManager(longTaskThreshold: 30)
        let completions = collectCompletions(from: manager) {
            manager.handle(event("SessionStart"))
            manager.handle(event("UserPromptSubmit"))
            currentDate = currentDate.addingTimeInterval(10)
            manager.handle(event("Notification", message: "Claude needs your permission"))
            currentDate = currentDate.addingTimeInterval(15)
            manager.handle(event("PreToolUse"))
            currentDate = currentDate.addingTimeInterval(15)
            manager.handle(event("Stop"))
        }

        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.duration ?? 0, 40, accuracy: 0.001)
    }

    func testNextTurnMeasuresFromItsOwnPromptNotThePreviousOne() {
        let manager = makeManager(longTaskThreshold: 30)
        let completions = collectCompletions(from: manager) {
            manager.handle(event("SessionStart"))
            manager.handle(event("UserPromptSubmit"))
            currentDate = currentDate.addingTimeInterval(60)
            manager.handle(event("Stop"))

            // İkinci kısa tur: önceki turun süresi taşınmamalı.
            manager.handle(event("UserPromptSubmit"))
            currentDate = currentDate.addingTimeInterval(5)
            manager.handle(event("Stop"))
        }

        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.duration ?? 0, 60, accuracy: 0.001)
    }

    // MARK: - Limit tespiti

    func testLimitNotificationMovesSessionToLimit() {
        let manager = makeManager()
        manager.handle(event("SessionStart"))
        manager.handle(event("UserPromptSubmit"))
        currentDate = currentDate.addingTimeInterval(3600)
        manager.handle(event("Notification", message: "Claude usage limit reached."))

        XCTAssertEqual(manager.sessions[0].state, .limit)
    }

    func testStopAfterLimitKeepsLimitStateAndDoesNotCelebrate() {
        let manager = makeManager(longTaskThreshold: 30)
        let completions = collectCompletions(from: manager) {
            manager.handle(event("SessionStart"))
            manager.handle(event("UserPromptSubmit"))
            currentDate = currentDate.addingTimeInterval(60)
            manager.handle(event("Notification", message: "You've hit the rate limit"))
            manager.handle(event("Stop"))
        }

        XCTAssertEqual(manager.sessions[0].state, .limit)
        XCTAssertTrue(completions.isEmpty)
    }

    func testResumingWorkExitsLimit() {
        let manager = makeManager()
        manager.handle(event("SessionStart"))
        manager.handle(event("Notification", message: "Claude usage limit reached."))
        XCTAssertEqual(manager.sessions[0].state, .limit)

        manager.handle(event("UserPromptSubmit"))
        XCTAssertEqual(manager.sessions[0].state, .working)
    }

    func testOrdinaryNotificationStillYieldsAttention() {
        let manager = makeManager()
        manager.handle(event("SessionStart"))
        manager.handle(event("Notification", message: "Claude needs your permission to use Bash"))

        XCTAssertEqual(manager.sessions[0].state, .attention)
    }

    // MARK: - Usage entegrasyonu (Faz 7)

    func testUpdateUsageSetsUsageOnExistingSession() {
        let manager = makeManager()
        manager.handle(event("SessionStart"))

        var usage = SessionUsage()
        usage.add(UsageDelta(model: "claude-opus-4-8", inputTokens: 100, outputTokens: 200))
        manager.updateUsage(usage, forSession: "s1")

        XCTAssertEqual(manager.sessions[0].usage?.totalTokens, 300)
    }

    func testUpdateUsageForUnknownSessionDoesNotCreateCard() {
        let manager = makeManager()
        manager.updateUsage(SessionUsage(), forSession: "hayalet")
        XCTAssertTrue(manager.sessions.isEmpty)
    }

    func testApplyLimitSignalMovesSessionToLimit() {
        let manager = makeManager()
        manager.handle(event("SessionStart"))
        manager.handle(event("UserPromptSubmit"))

        currentDate = currentDate.addingTimeInterval(3600)
        manager.applyLimitSignal(toSession: "s1")

        XCTAssertEqual(manager.sessions[0].state, .limit)
    }

    func testApplyLimitSignalForUnknownSessionIsIgnored() {
        let manager = makeManager()
        manager.applyLimitSignal(toSession: "hayalet")
        XCTAssertTrue(manager.sessions.isEmpty)
    }

    // MARK: - Kaynak uygulama tespiti (Faz 8)

    private func makeManager(frontmostApp: @escaping () -> String?) -> SessionManager {
        SessionManager(now: { self.currentDate }, frontmostApp: frontmostApp)
    }

    func testSessionStartCapturesFrontmostAppAsSource() {
        let manager = makeManager(frontmostApp: { "com.apple.Terminal" })
        manager.handle(event("SessionStart"))

        XCTAssertEqual(manager.sessions[0].sourceBundleId, "com.apple.Terminal")
    }

    func testUserPromptSubmitUpdatesSourceApp() {
        // Uygulama oturum ortasında açıldıysa SessionStart kaçmıştır; sonraki
        // prompt'ta kaynak yine de yakalanmalı ve güncel kalmalı.
        var frontmost: String? = nil
        let manager = makeManager(frontmostApp: { frontmost })
        manager.handle(event("SessionStart"))
        XCTAssertNil(manager.sessions[0].sourceBundleId)

        frontmost = "com.microsoft.VSCode"
        manager.handle(event("UserPromptSubmit"))
        XCTAssertEqual(manager.sessions[0].sourceBundleId, "com.microsoft.VSCode")
    }

    func testToolEventsDoNotOverwriteSourceApp() {
        // Tool eventleri sırasında kullanıcı başka uygulamada olabilir; kaynak bozulmamalı.
        var frontmost: String? = "com.apple.Terminal"
        let manager = makeManager(frontmostApp: { frontmost })
        manager.handle(event("SessionStart"))

        frontmost = "com.apple.Safari"
        manager.handle(event("PreToolUse"))
        manager.handle(event("PostToolUse"))
        XCTAssertEqual(manager.sessions[0].sourceBundleId, "com.apple.Terminal")
    }

    // MARK: - Banner eşiği güncelleme (Faz 8)

    func testUpdatedLongTaskThresholdAppliesToNextCompletion() {
        let manager = makeManager(longTaskThreshold: 30)
        manager.setLongTaskThreshold(120)

        let completions = collectCompletions(from: manager) {
            manager.handle(event("SessionStart"))
            manager.handle(event("UserPromptSubmit"))
            currentDate = currentDate.addingTimeInterval(60)
            manager.handle(event("Stop"))
        }

        XCTAssertTrue(completions.isEmpty)
    }
}
