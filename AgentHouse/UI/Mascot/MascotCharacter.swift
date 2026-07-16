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
    // Pixel art stili; heykelin kendisi kamu malı (1886).
    case statueOfLiberty
    // Jenerik gülen yüz; belirli bir emoji setinin çizimini kopyalamaz.
    case smiley
    // Pixel art stili jenerik robot.
    case robot
    // Pixel art stili, mor saçlı jenerik anime kızı; belirli bir eserin
    // karakterini kopyalamaz.
    case luna

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
        case .statueOfLiberty: return String(localized: "Statue of Liberty")
        case .smiley: return String(localized: "Smiley")
        case .robot: return String(localized: "Robot")
        case .luna: return String(localized: "Luna")
        }
    }
}
