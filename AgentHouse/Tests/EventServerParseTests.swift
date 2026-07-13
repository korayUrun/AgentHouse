import XCTest
@testable import AgentHouse

/// EventServer'ın minimal HTTP ayrıştırıcısını doğrular.
final class EventServerParseTests: XCTestCase {
    private func request(
        method: String = "POST",
        path: String = "/event",
        body: String = "{}"
    ) -> Data {
        let head = "\(method) \(path) HTTP/1.1\r\n"
            + "Host: 127.0.0.1:48756\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "\r\n"
        return Data((head + body).utf8)
    }

    func testParsesCompletePostEvent() {
        let body = #"{"hook_event_name":"Stop"}"#
        let result = EventServer.parseRequest(request(body: body))

        XCTAssertEqual(result, .complete(body: Data(body.utf8)))
    }

    func testIncompleteHeadersNeedMoreData() {
        let partial = Data("POST /event HTTP/1.1\r\nContent-Le".utf8)

        XCTAssertEqual(EventServer.parseRequest(partial), .needMoreData)
    }

    func testIncompleteBodyNeedsMoreData() {
        let full = request(body: #"{"hook_event_name":"Stop"}"#)
        let truncated = full.prefix(full.count - 5)

        XCTAssertEqual(EventServer.parseRequest(Data(truncated)), .needMoreData)
    }

    func testRejectsWrongMethod() {
        let result = EventServer.parseRequest(request(method: "GET"))

        XCTAssertEqual(result, .rejected(status: 405, reason: "Method Not Allowed"))
    }

    func testRejectsWrongPath() {
        let result = EventServer.parseRequest(request(path: "/baska"))

        XCTAssertEqual(result, .rejected(status: 404, reason: "Not Found"))
    }

    func testRejectsMissingContentLength() {
        let raw = Data("POST /event HTTP/1.1\r\nHost: x\r\n\r\n{}".utf8)

        XCTAssertEqual(EventServer.parseRequest(raw), .rejected(status: 400, reason: "Bad Request"))
    }

    func testRejectsOversizedBody() {
        let raw = Data("POST /event HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n".utf8)

        XCTAssertEqual(EventServer.parseRequest(raw), .rejected(status: 413, reason: "Payload Too Large"))
    }

    // MARK: - Expect: 100-continue (büyük event kaybını önleyen interim yanıt)

    func testExpectsContinueDetectsHeader() {
        let raw = Data(
            "POST /event HTTP/1.1\r\nContent-Length: 5000\r\nExpect: 100-continue\r\n\r\n".utf8
        )
        XCTAssertTrue(EventServer.expectsContinue(in: raw))
    }

    func testExpectsContinueIsCaseInsensitive() {
        let raw = Data(
            "POST /event HTTP/1.1\r\nexpect: 100-Continue\r\n\r\n".utf8
        )
        XCTAssertTrue(EventServer.expectsContinue(in: raw))
    }

    func testExpectsContinueFalseWithoutHeader() {
        let raw = Data("POST /event HTTP/1.1\r\nContent-Length: 5\r\n\r\n".utf8)
        XCTAssertFalse(EventServer.expectsContinue(in: raw))
    }

    func testExpectsContinueFalseBeforeHeadersComplete() {
        // Header bloğu daha bitmemişken interim yanıt gönderilmemeli.
        let raw = Data("POST /event HTTP/1.1\r\nExpect: 100-cont".utf8)
        XCTAssertFalse(EventServer.expectsContinue(in: raw))
    }

    func testCompletePostEventWithExpectHeaderStillParses() {
        // Expect başlıklı tam istek yine .complete döner (interim yanıt ayrıştırmadan bağımsız).
        let body = #"{"hook_event_name":"Stop"}"#
        let raw = Data((
            "POST /event HTTP/1.1\r\n"
                + "Content-Type: application/json\r\n"
                + "Expect: 100-continue\r\n"
                + "Content-Length: \(body.utf8.count)\r\n\r\n"
                + body
        ).utf8)
        XCTAssertEqual(EventServer.parseRequest(raw), .complete(body: Data(body.utf8)))
    }
}
