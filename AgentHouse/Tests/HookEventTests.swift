import XCTest
@testable import AgentHouse

/// HookEvent'in savunmacı decode davranışını doğrular.
final class HookEventTests: XCTestCase {
    private func decode(_ json: String) throws -> HookEvent {
        try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    }

    func testDecodesFullPayload() throws {
        let event = try decode(
            """
            {
                "hook_event_name": "PreToolUse",
                "session_id": "abc12345-6789",
                "transcript_path": "/Users/x/.claude/projects/p/abc.jsonl",
                "cwd": "/Users/x/Desktop/AgentHouse",
                "tool_name": "Bash",
                "message": "izin bekleniyor",
                "prompt": "merhaba",
                "source": "startup",
                "reason": "other"
            }
            """
        )

        XCTAssertEqual(event.hookEventName, "PreToolUse")
        XCTAssertEqual(event.name, .preToolUse)
        XCTAssertEqual(event.sessionId, "abc12345-6789")
        XCTAssertEqual(event.transcriptPath, "/Users/x/.claude/projects/p/abc.jsonl")
        XCTAssertEqual(event.cwd, "/Users/x/Desktop/AgentHouse")
        XCTAssertEqual(event.toolName, "Bash")
        XCTAssertEqual(event.message, "izin bekleniyor")
        XCTAssertEqual(event.prompt, "merhaba")
        XCTAssertEqual(event.source, "startup")
        XCTAssertEqual(event.reason, "other")
    }

    func testDecodesEmptyObject() throws {
        let event = try decode("{}")

        XCTAssertNil(event.hookEventName)
        XCTAssertNil(event.name)
        XCTAssertNil(event.sessionId)
        XCTAssertNil(event.cwd)
        XCTAssertNil(event.toolName)
    }

    func testIgnoresUnknownFields() throws {
        let event = try decode(
            """
            {
                "hook_event_name": "Stop",
                "session_id": "s1",
                "tool_input": {"command": "ls"},
                "yepyeni_alan": [1, 2, 3]
            }
            """
        )

        XCTAssertEqual(event.name, .stop)
        XCTAssertEqual(event.sessionId, "s1")
    }

    func testWrongTypedFieldBecomesNilWithoutFailingOthers() throws {
        // Hook şeması değişip `message` nesneye dönüşse bile diğer alanlar okunmaya devam etmeli.
        let event = try decode(
            """
            {
                "hook_event_name": "Notification",
                "session_id": "s2",
                "message": {"beklenmedik": "nesne"},
                "cwd": 42
            }
            """
        )

        XCTAssertEqual(event.name, .notification)
        XCTAssertEqual(event.sessionId, "s2")
        XCTAssertNil(event.message)
        XCTAssertNil(event.cwd)
    }

    func testUnknownEventNameYieldsNilName() throws {
        let event = try decode(#"{"hook_event_name": "SubagentStop"}"#)

        XCTAssertEqual(event.hookEventName, "SubagentStop")
        XCTAssertNil(event.name)
    }

    func testTopLevelGarbageThrows() {
        XCTAssertThrowsError(try decode("bu json değil"))
    }
}
