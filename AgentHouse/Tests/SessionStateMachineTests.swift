import XCTest
@testable import AgentHouse

/// SessionStateMachine'in saf geçiş tablosunu tekil geçişler ve event dizisi senaryolarıyla doğrular.
final class SessionStateMachineTests: XCTestCase {
    /// Bir event dizisini baştan sona uygular ve son state'i döndürür.
    private func run(_ events: [HookEvent.Name], from initial: SessionState = .idle) -> SessionState {
        events.reduce(initial) { SessionStateMachine.apply(state: $0, event: $1) }
    }

    // MARK: - Tekil geçişler (eşleme tablosu birebir)

    func testSessionStartYieldsIdleFromEveryState() {
        for state in SessionState.allCases {
            XCTAssertEqual(SessionStateMachine.apply(state: state, event: .sessionStart), .idle)
        }
    }

    // MARK: - Oturum-ortası compact (ADR-018)

    func testCompactSessionStartPreservesState() {
        // source=compact yeni oturum değil; çalışan/soru bekleyen kart olduğu gibi kalır.
        for state in SessionState.allCases {
            XCTAssertEqual(
                SessionStateMachine.apply(state: state, event: .sessionStart, isContinuation: true),
                state
            )
        }
    }

    func testNonCompactSessionStartStillResetsToIdle() {
        // startup/clear/resume (isContinuation=false) hâlâ idle döndürür.
        XCTAssertEqual(
            SessionStateMachine.apply(state: .working, event: .sessionStart, isContinuation: false),
            .idle
        )
    }

    func testUserPromptSubmitYieldsWorkingFromEveryState() {
        for state in SessionState.allCases {
            XCTAssertEqual(SessionStateMachine.apply(state: state, event: .userPromptSubmit), .working)
        }
    }

    func testToolEventsYieldWorkingFromEveryState() {
        for state in SessionState.allCases {
            XCTAssertEqual(SessionStateMachine.apply(state: state, event: .preToolUse), .working)
            XCTAssertEqual(SessionStateMachine.apply(state: state, event: .postToolUse), .working)
        }
    }

    func testNotificationYieldsAttentionFromEveryStateExceptQuestioning() {
        for state in SessionState.allCases where state != .questioning {
            XCTAssertEqual(SessionStateMachine.apply(state: state, event: .notification), .attention)
        }
    }

    // MARK: - Questioning (ADR-015)

    func testQuestionSignalYieldsQuestioningFromEveryState() {
        for state in SessionState.allCases {
            XCTAssertEqual(
                SessionStateMachine.apply(state: state, event: .preToolUse, isQuestionSignal: true),
                .questioning
            )
        }
    }

    func testPlainNotificationWhileQuestioningKeepsQuestioning() {
        // Soru zaten "girdi bekliyor"un daha spesifik hali; bekleme hatırlatması düşürmez.
        XCTAssertEqual(
            SessionStateMachine.apply(state: .questioning, event: .notification),
            .questioning
        )
    }

    func testLimitNotificationWhileQuestioningYieldsLimit() {
        XCTAssertEqual(
            SessionStateMachine.apply(state: .questioning, event: .notification, isLimitSignal: true),
            .limit
        )
    }

    func testAnsweredQuestionReturnsToWorking() {
        // Kullanıcı cevaplayınca PostToolUse gelir → working.
        XCTAssertEqual(SessionStateMachine.apply(state: .questioning, event: .postToolUse), .working)
    }

    func testQuestionScenario() {
        // prompt → tool → soru → cevap → stop
        var state = run([.sessionStart, .userPromptSubmit, .preToolUse, .postToolUse])
        state = SessionStateMachine.apply(state: state, event: .preToolUse, isQuestionSignal: true)
        XCTAssertEqual(state, .questioning)
        state = SessionStateMachine.apply(state: state, event: .postToolUse)
        XCTAssertEqual(state, .working)
        XCTAssertEqual(SessionStateMachine.apply(state: state, event: .stop), .done)
    }

    func testStopYieldsDoneFromEveryStateExceptLimit() {
        for state in SessionState.allCases where state != .limit {
            XCTAssertEqual(SessionStateMachine.apply(state: state, event: .stop), .done)
        }
    }

    func testStopWhileLimitedStaysLimit() {
        // Limitteki oturumun turu limit yüzünden bitmiştir; done (kutlama) gösterilmez.
        XCTAssertEqual(SessionStateMachine.apply(state: .limit, event: .stop), .limit)
    }

    func testSessionEndLeavesStateUntouched() {
        // sessionEnd bir geçiş değildir (oturum silme SessionManager'ın işi).
        for state in SessionState.allCases {
            XCTAssertEqual(SessionStateMachine.apply(state: state, event: .sessionEnd), state)
        }
    }

    // MARK: - done→idle zaman aşımı

    func testDoneTimeoutMovesDoneToIdle() {
        XCTAssertEqual(SessionStateMachine.applyDoneTimeout(state: .done), .idle)
    }

    func testDoneTimeoutLeavesOtherStatesUntouched() {
        for state in SessionState.allCases where state != .done {
            XCTAssertEqual(SessionStateMachine.applyDoneTimeout(state: state), state)
        }
    }

    // MARK: - Senaryolar (event dizileri)

    func testTypicalTurnScenario() {
        // start → prompt → tool → notification → tool → stop
        XCTAssertEqual(run([.sessionStart]), .idle)
        XCTAssertEqual(run([.sessionStart, .userPromptSubmit]), .working)
        XCTAssertEqual(run([.sessionStart, .userPromptSubmit, .preToolUse]), .working)
        XCTAssertEqual(run([.sessionStart, .userPromptSubmit, .preToolUse, .notification]), .attention)
        XCTAssertEqual(run([.sessionStart, .userPromptSubmit, .preToolUse, .notification, .preToolUse]), .working)
        XCTAssertEqual(run([.sessionStart, .userPromptSubmit, .preToolUse, .notification, .preToolUse, .stop]), .done)
    }

    func testPermissionApprovedInTerminalSyncsBackToWorking() {
        // İzin bekleyen oturum (attention), terminalden onay sonrası gelen ilk
        // PreToolUse ile kendiliğinden working'e dönmeli.
        let state = run([.userPromptSubmit, .preToolUse, .notification])
        XCTAssertEqual(state, .attention)
        XCTAssertEqual(SessionStateMachine.apply(state: state, event: .preToolUse), .working)
    }

    func testNewPromptAfterDoneStartsWorkingAgain() {
        XCTAssertEqual(run([.userPromptSubmit, .stop, .userPromptSubmit]), .working)
    }

    func testToolOnlyTurnWithoutNotification() {
        XCTAssertEqual(run([.userPromptSubmit, .preToolUse, .postToolUse, .preToolUse, .postToolUse, .stop]), .done)
    }

    // MARK: - Limit sinyali

    func testLimitSignalNotificationYieldsLimitFromEveryState() {
        for state in SessionState.allCases {
            XCTAssertEqual(
                SessionStateMachine.apply(state: state, event: .notification, isLimitSignal: true),
                .limit
            )
        }
    }

    func testPlainNotificationStillYieldsAttention() {
        XCTAssertEqual(
            SessionStateMachine.apply(state: .working, event: .notification, isLimitSignal: false),
            .attention
        )
    }

    func testWorkResumingAfterLimitYieldsWorking() {
        // Kullanıcı devam edebiliyorsa limit fiilen kalkmıştır.
        XCTAssertEqual(SessionStateMachine.apply(state: .limit, event: .userPromptSubmit), .working)
        XCTAssertEqual(SessionStateMachine.apply(state: .limit, event: .preToolUse), .working)
    }

    func testLimitScenario() {
        // working sırasında limit bildirimi gelir, ardından Stop; kart limitte kalmalı.
        var state = run([.sessionStart, .userPromptSubmit, .preToolUse])
        state = SessionStateMachine.apply(state: state, event: .notification, isLimitSignal: true)
        XCTAssertEqual(state, .limit)
        XCTAssertEqual(SessionStateMachine.apply(state: state, event: .stop), .limit)
    }
}
