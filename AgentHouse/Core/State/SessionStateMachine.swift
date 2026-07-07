import Foundation

/// Oturum state geçişlerinin TEK karar noktası. Saf fonksiyonlardan oluşur (girdi→çıktı,
/// yan etkisiz); timer kurma ve oturum ekleme/silme gibi yan etkiler SessionManager'dadır.
enum SessionStateMachine {
    /// CLAUDE.md'deki hook eşleme tablosunu birebir uygular: verilen event, mevcut state'i
    /// hangi state'e taşır? `sessionEnd` bir geçiş değil oturum silmedir; state'i değiştirmez.
    static func apply(state: SessionState, event: HookEvent.Name) -> SessionState {
        switch event {
        case .sessionStart:
            return .idle
        case .userPromptSubmit:
            return .working
        // attention→working senkronizasyonu buradan gelir: terminalden izin onaylanınca
        // ilk PreToolUse eventi state'i kendiliğinden working'e çeker.
        case .preToolUse, .postToolUse:
            return .working
        case .notification:
            return .attention
        case .stop:
            return .done
        case .sessionEnd:
            return state
        }
    }

    /// done→idle gecikmesi dolduğunda uygulanacak geçiş. Timer beklerken başka bir event
    /// state'i değiştirdiyse (artık done değilse) hiçbir şey yapmaz.
    static func applyDoneTimeout(state: SessionState) -> SessionState {
        state == .done ? .idle : state
    }
}
