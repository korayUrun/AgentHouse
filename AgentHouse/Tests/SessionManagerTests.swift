import XCTest
@testable import AgentHouse

/// SessionManager'ın oturum yaşam döngüsünü (oluşturma, state güncelleme, done→idle,
/// stale, silme) enjekte edilmiş saat ve kısa gecikmelerle doğrular.
final class SessionManagerTests: XCTestCase {
    /// Testlerin ilerletebildiği sahte saat.
    private var currentDate = Date(timeIntervalSince1970: 1_000_000)

    private func makeManager(doneToIdleDelay: TimeInterval = 0.05) -> SessionManager {
        SessionManager(doneToIdleDelay: doneToIdleDelay, now: { self.currentDate })
    }

    private func event(_ name: String, session: String? = "s1", cwd: String? = nil) -> HookEvent {
        var fields: [String: Any] = ["hook_event_name": name]
        fields["session_id"] = session
        fields["cwd"] = cwd
        let data = try! JSONSerialization.data(withJSONObject: fields)
        return try! JSONDecoder().decode(HookEvent.self, from: data)
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
}
