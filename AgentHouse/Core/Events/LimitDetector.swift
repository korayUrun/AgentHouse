import Foundation

/// Notification hook mesajından best-effort rate-limit tespiti ve lokal reset tahmini.
/// Tespit muhafazakârdır: kalıba uymayan mesaj limit SAYILMAZ (emin değilsen state'i bozma).
enum LimitDetector {
    /// Claude'un kullanım penceresi süresi; reset tahmini bu pencereden hesaplanır.
    static let windowDuration: TimeInterval = 5 * 60 * 60

    // Bilinen limit mesajı kalıpları; tek başına "limit" kelimesi bilerek yeterli değil.
    private static let markers = [
        "usage limit",
        "rate limit",
        "limit reached",
        "limit will reset",
        "hit your limit",
        "5-hour limit",
    ]

    /// Mesaj bilinen limit kalıplarından birini içeriyorsa true.
    static func isLimitNotification(_ message: String?) -> Bool {
        guard let message, !message.isEmpty else { return false }
        let lowered = message.lowercased()
        return markers.contains { lowered.contains($0) }
    }

    /// Pencere başlangıcından tahmini reset anı: başlangıçtan itibaren pencere sınırları
    /// ilerletilir, `now`dan sonraki ilk sınır döner. Best-effort — "~" ile gösterilir.
    static func estimateReset(
        windowStart: Date,
        now: Date,
        window: TimeInterval = LimitDetector.windowDuration
    ) -> Date {
        guard window > 0 else { return now }
        var reset = windowStart.addingTimeInterval(window)
        while reset <= now {
            reset.addTimeInterval(window)
        }
        return reset
    }
}
