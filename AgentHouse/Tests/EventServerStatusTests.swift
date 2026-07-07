import Combine
import XCTest
@testable import AgentHouse

/// EventServer'ın dinleyici durum yayınını doğrular: NWListener port çakışmasını
/// start() anında değil asenkron `.failed` state'iyle bildirir; UI bu yayına güvenir.
final class EventServerStatusTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    /// Verilen sunucunun belirtilen duruma geçmesini bekler.
    private func expectStatus(
        _ expected: EventServer.ListenerStatus,
        from server: EventServer,
        description: String
    ) -> XCTestExpectation {
        let expectation = expectation(description: description)
        server.status
            .receive(on: DispatchQueue.main)
            .sink { status in
                switch (status, expected) {
                case (.ready, .ready), (.failed, .failed), (.idle, .idle):
                    expectation.fulfill()
                default:
                    break
                }
            }
            .store(in: &cancellables)
        return expectation
    }

    func testReportsReadyThenConflictOnSamePort() throws {
        // Sabit port çakışma riskine karşı deneme başına farklı port.
        let port = UInt16.random(in: 49500...59500)

        let first = EventServer(port: port)
        let ready = expectStatus(.ready, from: first, description: "ilk sunucu ready")
        try first.start()
        wait(for: [ready], timeout: 5)
        defer { first.stop() }

        let second = EventServer(port: port)
        let failed = expectStatus(
            .failed(reason: ""),
            from: second,
            description: "ikinci sunucu failed"
        )
        try second.start()
        wait(for: [failed], timeout: 5)
        second.stop()
    }

    func testStopPublishesIdle() throws {
        let port = UInt16.random(in: 49500...59500)
        let server = EventServer(port: port)
        let ready = expectStatus(.ready, from: server, description: "sunucu ready")
        try server.start()
        wait(for: [ready], timeout: 5)

        server.stop()
        XCTAssertEqual(server.currentStatus, .idle)
    }
}
