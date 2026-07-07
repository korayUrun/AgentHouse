import Foundation

/// Bir Claude Code oturumunun panelde gösterilen durumu; stale ayrı bir bayraktır (`Session.isStale`).
enum SessionState: String, Equatable, CaseIterable {
    /// Oturum açık ama şu an bir iş yapmıyor.
    case idle
    /// Claude aktif çalışıyor (prompt işleniyor veya tool koşuyor).
    case working
    /// Kullanıcıdan izin/girdi bekliyor.
    case attention
    /// Claude, AskUserQuestion ile kullanıcıya soru sordu; cevap bekliyor (ADR-015).
    case questioning
    /// İş yeni bitti; kısa süre sonra idle'a döner.
    case done
    /// Rate limit'e takıldı (tespit best-effort, Faz 6/7'de bağlanır).
    case limit
}
