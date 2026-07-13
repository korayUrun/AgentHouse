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

    /// Küme içi kart sırasının saklandığı anahtar (küme id → proje yolu listesi).
    static let orderDefaultsKey = "cardOrderByCluster"

    @Published private(set) var clusterByProject: [String: String]
    /// Kullanıcının sürükle-bırakla belirlediği kart sırası; listede olmayan
    /// kartlar oluşturulma sırasıyla sona gelir.
    @Published private(set) var orderByCluster: [String: [String]]

    private let defaults: UserDefaults

    /// Testte sahte UserDefaults geçirilebilsin diye enjekte edilir.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        clusterByProject = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        orderByCluster = defaults.dictionary(forKey: Self.orderDefaultsKey) as? [String: [String]] ?? [:]
    }

    /// Oturumları kümenin kayıtlı kart sırasına göre dizer (kayıtsızlar oluşturulma
    /// sırasıyla sona). View ve koordinatör AYNI sırayı bu fonksiyondan okur.
    func orderedSessions(_ sessions: [Session], inCluster clusterId: String) -> [Session] {
        let order = orderByCluster[clusterId] ?? []
        guard !order.isEmpty else { return sessions }
        return sessions.enumerated().sorted { lhs, rhs in
            let lhsIndex = lhs.element.projectKey.flatMap { order.firstIndex(of: $0) } ?? Int.max
            let rhsIndex = rhs.element.projectKey.flatMap { order.firstIndex(of: $0) } ?? Int.max
            return lhsIndex == rhsIndex ? lhs.offset < rhs.offset : lhsIndex < rhsIndex
        }.map(\.element)
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
        removeFromOrders(projectKey)
        persist()
        return clusterId
    }

    /// Projeyi ana kümeye döndürür.
    func returnToMain(project projectKey: String?) {
        guard let projectKey else { return }
        clusterByProject.removeValue(forKey: projectKey)
        removeFromOrders(projectKey)
        persist()
    }

    /// Verilen projeleri hedef kümeye taşır (sürükle-bırak birleşmesi). Kaynak küme
    /// TARANMAZ; çağıran taşınacak projeleri açıkça verir — böylece ana küme (üyeleri
    /// `clusterByProject`'te tutulmaz) hem kaynak hem hedef olabilir. Hedef ana küme ise
    /// üyeler haritadan çıkarılır (ana kümeye dönüş). `order` verilirse hedefin kart
    /// sırası bununla değişir; `sourceId`'nin sıra kaydı temizlenir (kaynak dağılır).
    func merge(projects movedKeys: [String], from sourceId: String, into targetId: String, order: [String]? = nil) {
        guard sourceId != targetId else { return }
        for projectKey in movedKeys {
            if targetId == Self.mainClusterId {
                clusterByProject.removeValue(forKey: projectKey)
            } else {
                clusterByProject[projectKey] = targetId
            }
        }
        if let order {
            orderByCluster[targetId] = order
        }
        orderByCluster.removeValue(forKey: sourceId)
        persist()
    }

    /// Tüm kartları ana panelde toplar (sıra kayıtları da sıfırlanır).
    func gatherAll() {
        guard !clusterByProject.isEmpty || !orderByCluster.isEmpty else { return }
        clusterByProject.removeAll()
        orderByCluster.removeAll()
        persist()
    }

    private func removeFromOrders(_ projectKey: String) {
        for (clusterId, order) in orderByCluster where order.contains(projectKey) {
            orderByCluster[clusterId] = order.filter { $0 != projectKey }
        }
    }

    private func persist() {
        defaults.set(clusterByProject, forKey: Self.defaultsKey)
        defaults.set(orderByCluster, forKey: Self.orderDefaultsKey)
    }
}
