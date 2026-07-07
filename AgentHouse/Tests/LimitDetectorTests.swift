import XCTest
@testable import AgentHouse

/// LimitDetector'ın mesaj sınıflandırmasını ve 5 saatlik pencereden reset tahminini doğrular.
final class LimitDetectorTests: XCTestCase {
    // MARK: - Limit mesajı tespiti

    func testKnownLimitMessagesAreDetected() {
        let messages = [
            "Claude usage limit reached. Your limit will reset at 7pm.",
            "You've hit the rate limit — try again later.",
            "5-hour limit reached ∙ resets 3am",
            "You have hit your limit for this session.",
        ]
        for message in messages {
            XCTAssertTrue(LimitDetector.isLimitNotification(message), "Tespit edilmeliydi: \(message)")
        }
    }

    func testDetectionIsCaseInsensitive() {
        XCTAssertTrue(LimitDetector.isLimitNotification("USAGE LIMIT reached"))
    }

    func testOrdinaryNotificationsAreNotLimit() {
        // Muhafazakâr tespit: emin olunmayan mesaj limit sayılmaz (state bozulmaz).
        let messages = [
            "Claude needs your permission to use Bash",
            "Claude is waiting for your input",
            "unlimited power!",
            "",
        ]
        for message in messages {
            XCTAssertFalse(LimitDetector.isLimitNotification(message), "Limit sayılmamalıydı: \(message)")
        }
        XCTAssertFalse(LimitDetector.isLimitNotification(nil))
    }

    // MARK: - Reset tahmini

    func testResetIsEndOfFirstWindowWhenStillInside() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let now = start.addingTimeInterval(2 * 3600)
        XCTAssertEqual(
            LimitDetector.estimateReset(windowStart: start, now: now),
            start.addingTimeInterval(5 * 3600)
        )
    }

    func testResetRollsForwardWhenWindowStartIsOld() {
        // Oturum 7 saattir açıksa ilk pencere geçmiştir; sonraki sınır (10. saat) dönmeli.
        let start = Date(timeIntervalSince1970: 1_000_000)
        let now = start.addingTimeInterval(7 * 3600)
        XCTAssertEqual(
            LimitDetector.estimateReset(windowStart: start, now: now),
            start.addingTimeInterval(10 * 3600)
        )
    }

    func testResetOnExactBoundaryMovesToNextWindow() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let now = start.addingTimeInterval(5 * 3600)
        XCTAssertEqual(
            LimitDetector.estimateReset(windowStart: start, now: now),
            start.addingTimeInterval(10 * 3600)
        )
    }

    func testResetIsAlwaysInTheFuture() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let now = start.addingTimeInterval(123 * 3600)
        XCTAssertGreaterThan(LimitDetector.estimateReset(windowStart: start, now: now), now)
    }
}
