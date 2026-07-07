import SwiftUI

/// Maskot implementasyonlarının ortak sözleşmesi: oturum state'ini ve karakteri
/// alır, o state'e uygun animasyonu oynatır (ADR-008 protokol soyutlaması,
/// ADR-014 çoklu karakter).
///
/// Animasyonların duraklatılması `\.mascotAnimationsPaused` environment değeriyle
/// yapılır; panel gizlendiğinde OverlayPanel bu değeri true'ya çeker ve maskot
/// hiç CPU harcamaz.
protocol MascotAnimating: View {
    init(state: SessionState, character: MascotCharacter)
}

/// Kartlarda kullanılan aktif maskot implementasyonu. Rive maskotu hazır
/// olduğunda (ADR-009) yalnızca bu satır RiveMascotView'a çevrilir.
typealias ActiveMascot = PlaceholderMascotView

private struct MascotAnimationsPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// true iken maskot (ve karta bağlı diğer süreğen) animasyonlar tamamen durur.
    var mascotAnimationsPaused: Bool {
        get { self[MascotAnimationsPausedKey.self] }
        set { self[MascotAnimationsPausedKey.self] = newValue }
    }
}
