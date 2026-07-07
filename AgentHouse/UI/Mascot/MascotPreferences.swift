import Combine
import Foundation

/// Proje (cwd) → maskot karakteri tercihini UserDefaults'ta tutan depo (ADR-014).
/// Yalnızca bir UI tercihi saklar (kural 2 ile uyumlu); oturum verisi içermez.
/// Ana thread'de kullanılmalıdır.
final class MascotPreferences: ObservableObject {
    /// Tercih sözlüğünün saklandığı UserDefaults anahtarı (proje yolu → karakter id).
    static let defaultsKey = "mascotCharacterByProject"

    @Published private(set) var characterByProject: [String: MascotCharacter]

    private let defaults: UserDefaults

    /// Testte sahte UserDefaults geçirilebilsin diye enjekte edilir.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        // Bilinmeyen id'ler (eski sürümden vb.) sessizce varsayılana düşer.
        characterByProject = stored.compactMapValues(MascotCharacter.init(rawValue:))
    }

    /// Projenin karakteri; kayıtlı tercih yoksa varsayılan.
    func character(forProject projectKey: String?) -> MascotCharacter {
        guard let projectKey, let choice = characterByProject[projectKey] else {
            return .default
        }
        return choice
    }

    /// Tercihi kaydeder. Varsayılana dönüş kaydı siler ki sözlük süresiz büyümesin
    /// (kayıt yokluğu zaten varsayılan demektir).
    func setCharacter(_ character: MascotCharacter, forProject projectKey: String?) {
        guard let projectKey, !projectKey.isEmpty else { return }
        if character == .default {
            characterByProject.removeValue(forKey: projectKey)
        } else {
            characterByProject[projectKey] = character
        }
        defaults.set(characterByProject.mapValues(\.rawValue), forKey: Self.defaultsKey)
    }
}
