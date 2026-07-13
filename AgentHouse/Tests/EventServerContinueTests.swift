import Combine
import XCTest
@testable import AgentHouse

/// EventServer'ın `Expect: 100-continue` davranışını GERÇEK curl ile uçtan uca doğrular
/// (bulgu #1): sunucu interim `100 Continue` dönmezse curl gövdeyi ~1 sn geciktirir ve
/// `--max-time 1` ile çakışıp isteği keser → event kaybolur. Bu test, >1KB gövdeli bir
/// hook isteğinin yine de `--max-time 1` içinde sunucuya ulaştığını gösterir.
final class EventServerContinueTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testLargeExpectContinuePostArrivesWithinMaxTime() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/curl") else {
            throw XCTSkip("curl bulunamadı; entegrasyon testi atlandı")
        }

        let port = UInt16.random(in: 49500...59500)
        let server = EventServer(port: port)

        let ready = expectation(description: "sunucu ready")
        server.status
            .receive(on: DispatchQueue.main)
            .sink { if $0 == .ready { ready.fulfill() } }
            .store(in: &cancellables)
        try server.start()
        wait(for: [ready], timeout: 5)
        defer { server.stop() }

        let received = expectation(description: "büyük event alındı")
        server.events
            .receive(on: DispatchQueue.main)
            .sink { event in
                if event.name == .postToolUse, event.sessionId == "itest" {
                    received.fulfill()
                }
            }
            .store(in: &cancellables)

        // >1KB gövde: curl otomatik Expect: 100-continue yollar; başlığı ayrıca açıkça da
        // ekliyoruz ki davranış curl sürümünden bağımsız deterministik olsun.
        let bigText = String(repeating: "x", count: 2048)
        let body = #"{"hook_event_name":"PostToolUse","session_id":"itest","tool_input":""#
            + bigText + #""}"#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-s", "--max-time", "1", "-X", "POST",
            "http://127.0.0.1:\(port)/event",
            "-H", "Content-Type: application/json",
            "-H", "Expect: 100-continue",
            "-d", "@-",
        ]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        stdin.fileHandleForWriting.write(Data(body.utf8))
        try stdin.fileHandleForWriting.close()

        wait(for: [received], timeout: 5)
        process.waitUntilExit()
    }
}
