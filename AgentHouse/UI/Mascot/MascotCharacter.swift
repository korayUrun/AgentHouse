import Foundation

/// Kullanılabilir maskot karakterleri (ADR-014). Yeni karakter yalnızca yeni bir
/// çizim ekler; state fiziği (MascotPose) tüm karakterlerde ortaktır.
enum MascotCharacter: String, CaseIterable, Identifiable {
    case house
    case lighthouse
    case rocket
    // Jenerik yarış arabası; bilinçli olarak hiçbir markanın/karakterin
    // ayırt edici öğesini taşımaz (telif).
    case raceCar

    /// Yeni projelerin başladığı varsayılan karakter.
    static let `default` = MascotCharacter.house

    var id: String { rawValue }

    /// Kullanıcıya görünen ad (kart menüsünde).
    var displayName: String {
        switch self {
        case .house: return String(localized: "House")
        case .lighthouse: return String(localized: "Lighthouse")
        case .rocket: return String(localized: "Rocket")
        case .raceCar: return String(localized: "Race Car")
        }
    }
}
