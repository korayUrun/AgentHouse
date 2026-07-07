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

    func testNotificationYieldsAttentionFromEveryState() {
        for state in SessionState.allCases {
            XCTAssertEqual(SessionStateMachine.apply(state: state, event: .notification), .attention)
        }
    }

    func testStopYieldsDoneFromEveryState() {
        for state in SessionState.allCases {
            XCTAssertEqual(SessionStateMachine.apply(state: state, event: .stop), .done)
        }
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
}
