import Combine
import Foundation

/// Kartların hangi overlay panelinde (kümede) yaşadığını tutan depo (ADR-017).
/// Varsayılan küme "main"dir; kullanıcı bir projeyi ayırınca proje → küme ataması
/// UserDefaults'a yazılır ve projenin sonraki oturumları da aynı kümede açılır
/// (yalnızca UI tercihi; kural 2 ile uyumlu). Ana thread'de kullanılmalıdır.
final class ClusterStore: ObservableObject {
    /// Varsayılan (ana) kümenin kimliği.
    static let mainClusterId = "main"

    /// Atama sözlüğünün saklandığı UserDefaults anahtarı (proje yolu → küme id).
    static let defaultsKey = "clusterByProject"

    @Published private(set) var clusterByProject: [String: String]

    private let defaults: UserDefaults

    /// Testte sahte UserDefaults geçirilebilsin diye enjekte edilir.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        clusterByProject = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    /// Projenin kümesi; ataması yoksa ana küme.
    func clusterId(forProject projectKey: String?) -> String {
        guard let projectKey, let clusterId = clusterByProject[projectKey] else {
            return Self.mainClusterId
        }
        return clusterId
    }

    /// Projeyi kendi yeni panelinde ayırır; yeni kümenin id'sini döndürür.
    /// Anahtarsız proje ayrılamaz (nil döner).
    @discardableResult
    func detach(project projectKey: String?) -> String? {
        guard let projectKey, !projectKey.isEmpty else { return nil }
        let clusterId = UUID().uuidString
        clusterByProject[projectKey] = clusterId
        persist()
        return clusterId
    }

    /// Projeyi ana kümeye döndürür.
    func returnToMain(project projectKey: String?) {
        guard let projectKey else { return }
        clusterByProject.removeValue(forKey: projectKey)
        persist()
    }

    /// Bir kümenin tüm projelerini hedef kümeye taşır (sürükle-bırak birleşmesi).
    func merge(cluster sourceId: String, into targetId: String) {
        guard sourceId != targetId else { return }
        for (projectKey, clusterId) in clusterByProject where clusterId == sourceId {
            if targetId == Self.mainClusterId {
                clusterByProject.removeValue(forKey: projectKey)
            } else {
                clusterByProject[projectKey] = targetId
            }
        }
        persist()
    }

    /// Tüm kartları ana panelde toplar.
    func gatherAll() {
        guard !clusterByProject.isEmpty else { return }
        clusterByProject.removeAll()
        persist()
    }

    private func persist() {
        defaults.set(clusterByProject, forKey: Self.defaultsKey)
    }
}
