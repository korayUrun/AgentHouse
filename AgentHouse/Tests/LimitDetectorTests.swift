import XCTest
@testable import AgentHouse

/// LimitDetector'ın mesaj sınıflandırmasını doğrular (reset tahmini ADR-016 ile kaldırıldı).
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
}
