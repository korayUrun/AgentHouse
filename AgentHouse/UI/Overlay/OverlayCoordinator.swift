import AppKit
import Combine
import os

/// Küme başına bir OverlayPanel'in yaşam döngüsünü yöneten koordinatör (ADR-017):
/// oturum ve küme atamaları değiştikçe panelleri açar/gizler, yeni ayrılan kümeyi
/// kaynağının yanına yerleştirir, sürüklenen panel başka bir panelin üzerine
/// bırakılınca kümeleri birleştirir. Ana thread'de yaşar.
final class OverlayCoordinator {
    private let sessionManager: SessionManager
    private let clusterStore: ClusterStore
    private let onSessionActivate: (Session) -> Void

    private var panels: [String: OverlayPanel] = [:]
    private var cancellables = Set<AnyCancellable>()
    /// Menü bardan "paneli gizle" seçildiyse true; yeni oturum gelince sıfırlanır.
    private var userHidAllPanels = false
    private var pendingMergeCheck: DispatchWorkItem?
    private let logger = Logger(subsystem: "com.agenthouse.app", category: "OverlayCoordinator")

    init(
        sessionManager: SessionManager,
        clusterStore: ClusterStore,
        onSessionActivate: @escaping (Session) -> Void
    ) {
        self.sessionManager = sessionManager
        self.clusterStore = clusterStore
        self.onSessionActivate = onSessionActivate

        // Ana panel her zaman var olur (boşken gizlenir); menü bar toggle'ı için çıpa.
        panels[ClusterStore.mainClusterId] = makePanel(clusterId: ClusterStore.mainClusterId)

        sessionManager.$sessions
            .map { $0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] _ in self?.reconcilePanels() }
            .store(in: &cancellables)
        sessionManager.$sessions
            .map { Set($0.map(\.id)) }
            .removeDuplicates()
            .sink { [weak self] _ in self?.reconcilePanels() }
            .store(in: &cancellables)
        clusterStore.$clusterByProject
            .removeDuplicates()
            .sink { [weak self] _ in self?.reconcilePanels() }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Menü bar eylemleri

    /// En az bir panel görünür mü?
    var isAnyPanelVisible: Bool {
        panels.values.contains(where: \.isVisible)
    }

    /// Tüm panelleri gizler/gösterir (menü bar "Hide/Show Panel").
    func toggleAllPanels() {
        if isAnyPanelVisible {
            userHidAllPanels = true
            panels.values.forEach { $0.hide() }
        } else {
            userHidAllPanels = false
            reconcilePanels()
            // Hiç oturum yoksa "bekliyor" kapsülüyle ana paneli göster.
            if sessionManager.sessions.isEmpty {
                panels[ClusterStore.mainClusterId]?.show()
            }
        }
    }

    /// Tüm kartları ana panelde toplar (menü bar "Gather all cards").
    func gatherAllCards() {
        clusterStore.gatherAll()
    }

    /// Ana paneli varsayılan köşeye döndürür ve tüm kartları orada toplar (Ayarlar).
    func resetLayout() {
        clusterStore.gatherAll()
        panels[ClusterStore.mainClusterId]?.resetPosition()
    }

    // MARK: - Panel yaşam döngüsü

    /// Oturum/küme durumuna göre panel setini eşitler: dolu kümelerin paneli
    /// görünür, boşalanlar gizlenir; ayrık boş paneller yıkılır.
    private func reconcilePanels() {
        let sessions = sessionManager.sessions
        var neededClusterIds = Set<String>()
        for session in sessions {
            neededClusterIds.insert(clusterStore.clusterId(forProject: session.projectKey))
        }
        if !sessions.isEmpty {
            userHidAllPanels = false
        }

        for clusterId in neededClusterIds where panels[clusterId] == nil {
            let panel = makePanel(clusterId: clusterId)
            panels[clusterId] = panel
            // Yeni ayrılan küme, kaydı yoksa ana panelin yanında belirir.
            if !panel.hasStoredPosition, let main = panels[ClusterStore.mainClusterId] {
                panel.placeTopLeft(NSPoint(
                    x: main.frame.origin.x + 36,
                    y: main.frame.maxY - main.frame.height - 24
                ))
            }
        }

        for (clusterId, panel) in panels {
            if neededClusterIds.contains(clusterId), !userHidAllPanels {
                panel.show()
            } else {
                panel.hide()
                if clusterId != ClusterStore.mainClusterId {
                    panels.removeValue(forKey: clusterId)
                }
            }
        }
    }

    private func makePanel(clusterId: String) -> OverlayPanel {
        OverlayPanel(
            sessionManager: sessionManager,
            clusterStore: clusterStore,
            clusterId: clusterId,
            onSessionActivate: onSessionActivate
        )
    }

    // MARK: - Sürükle-bırak birleşmesi

    @objc private func panelDidMove(_ notification: Notification) {
        guard
            let moved = notification.object as? OverlayPanel,
            panels[moved.clusterId] === moved
        else { return }
        // didMove sürükleme boyunca akar; fare bırakılana kadar bekleyip tek karar ver.
        pendingMergeCheck?.cancel()
        let work = DispatchWorkItem { [weak self, weak moved] in
            guard let self, let moved else { return }
            if NSEvent.pressedMouseButtons != 0 {
                self.panelDidMove(Notification(name: NSWindow.didMoveNotification, object: moved))
                return
            }
            self.mergeIfDropped(moved)
        }
        pendingMergeCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Bırakılan panel başka bir panelle belirgin şekilde çakışıyorsa kümeleri birleştirir.
    private func mergeIfDropped(_ moved: OverlayPanel) {
        guard moved.isVisible else { return }
        for (targetId, target) in panels
        where target !== moved && target.isVisible && moved.frame.intersects(target.frame) {
            let overlap = moved.frame.intersection(target.frame)
            let smallerArea = min(
                moved.frame.width * moved.frame.height,
                target.frame.width * target.frame.height
            )
            guard smallerArea > 0, (overlap.width * overlap.height) / smallerArea > 0.25 else { continue }
            logger.info("Panel bırakıldı; kümeler birleştiriliyor: \(moved.clusterId, privacy: .public) → \(targetId, privacy: .public)")
            moved.clearStoredPosition()
            clusterStore.merge(cluster: moved.clusterId, into: targetId)
            return
        }
    }
}
