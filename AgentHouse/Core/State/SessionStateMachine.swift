import Foundation

/// Oturum state geçişlerinin TEK karar noktası. Saf fonksiyonlardan oluşur (girdi→çıktı,
/// yan etkisiz); timer kurma ve oturum ekleme/silme gibi yan etkiler SessionManager'dadır.
enum SessionStateMachine {
    /// CLAUDE.md'deki hook eşleme tablosunu birebir uygular: verilen event, mevcut state'i
    /// hangi state'e taşır? `sessionEnd` bir geçiş değil oturum silmedir; state'i değiştirmez.
    /// `isLimitSignal`, Notification içeriğinin limit belirttiğini söyler (LimitDetector karar verir).
    static func apply(state: SessionState, event: HookEvent.Name, isLimitSignal: Bool = false) -> SessionState {
        switch event {
        case .sessionStart:
            return .idle
        case .userPromptSubmit:
            return .working
        // attention→working senkronizasyonu buradan gelir: terminalden izin onaylanınca
        // ilk PreToolUse eventi state'i kendiliğinden working'e çeker. Aynı kural limitten
        // çıkışı da sağlar: kullanıcı devam edebiliyorsa limit fiilen kalkmıştır.
        case .preToolUse, .postToolUse:
            return .working
        case .notification:
            return isLimitSignal ? .limit : .attention
        case .stop:
            // Limitteki oturumun turu limit yüzünden bitmiştir; done (kutlama) gösterilmez.
            return state == .limit ? .limit : .done
        case .sessionEnd:
            return state
        }
    }

    /// done→idle gecikmesi dolduğunda uygulanacak geçiş. Timer beklerken başka bir event
    /// state'i değiştirdiyse (artık done değilse) hiçbir şey yapmaz.
    static func applyDoneTimeout(state: SessionState) -> SessionState {
        state == .done ? .idle : state
    }

    /// Hook dışı bir kaynaktan (UsageReader'ın canlı JSONL rate-limit izi) gelen limit
    /// sinyalinin geçişi: her state limit'e taşınır. Limitten çıkış yine hook
    /// eventleriyle olur (yeni prompt/tool → working).
    static func applyLimitSignal(state: SessionState) -> SessionState {
        .limit
    }
}
