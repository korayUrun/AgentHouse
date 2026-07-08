import Foundation

/// Notification hook mesajından best-effort rate-limit tespiti.
/// Tespit muhafazakârdır: kalıba uymayan mesaj limit SAYILMAZ (emin değilsen state'i bozma).
/// Reset saati TAHMİN EDİLMEZ (ADR-016): pencere başlangıcı lokal olarak bilinemediği
/// için tahmin yanıltıcıydı; state gösterilir, saat gösterilmez.
enum LimitDetector {
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
}
