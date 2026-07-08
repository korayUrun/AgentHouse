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

        // @Published willSet anında yayınlar; store/manager'ı GÜNCEL haliyle okumak
        // için teslimat ana kuyruğun bir sonraki tik'ine ertelenir.
        sessionManager.$sessions
            .map { Set($0.map(\.id)) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcilePanels() }
            .store(in: &cancellables)
        clusterStore.$clusterByProject
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
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

        var freshPanels: [OverlayPanel] = []
        for clusterId in neededClusterIds where panels[clusterId] == nil {
            let panel = makePanel(clusterId: clusterId)
            panels[clusterId] = panel
            // Yeni ayrılan küme, kaydı yoksa ana panelin altında belirir.
            if !panel.hasStoredPosition, let main = panels[ClusterStore.mainClusterId] {
                panel.placeTopLeft(NSPoint(
                    x: main.frame.origin.x + 36,
                    y: main.frame.minY - 16
                ))
                freshPanels.append(panel)
            }
        }

        for (clusterId, panel) in panels {
            if neededClusterIds.contains(clusterId), !userHidAllPanels {
                if freshPanels.contains(where: { $0 === panel }) {
                    revealWithSlide(panel)
                } else {
                    panel.show()
                }
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

    /// Yeni ayrılan paneli yukarıdan hafifçe süzülerek ve solarak-belirerek gösterir
    /// (ayırma "pat diye" değil, akışkan hissettirsin).
    private func revealWithSlide(_ panel: OverlayPanel) {
        var start = panel.frame
        start.origin.y += 18
        panel.alphaValue = 0
        panel.setFrame(start, display: false)
        panel.show()
        var end = start
        end.origin.y -= 18
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(end, display: true)
        }
    }

    // MARK: - Sürükle-bırak birleşmesi

    @objc private func panelDidMove(_ notification: Notification) {
        guard
            let moved = notification.object as? OverlayPanel,
            panels[moved.clusterId] === moved
        else { return }
        // Sürükleme boyunca olası hedefi canlı vurgula (birleşeceği belli olsun);
        // fare bırakılana kadar bekleyip birleşme kararını tek seferde ver.
        highlightMergeTarget(for: moved)
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

    /// Sürüklenen panelin üzerinde durduğu hedefi işaretler; diğer vurguları temizler.
    private func highlightMergeTarget(for moved: OverlayPanel) {
        let target = mergeTarget(for: moved)
        for panel in panels.values {
            panel.mergeHighlight.isTargeted = (panel === target)
        }
    }

    private func clearMergeHighlights() {
        panels.values.forEach { $0.mergeHighlight.isTargeted = false }
    }

    /// Sürüklenen panelle yeterince (küçük olanın >%25'i) çakışan paneller arasından
    /// EN ÇOK çakışanı seçer — kullanıcının üzerine bıraktığı panel kazanır.
    private func mergeTarget(for moved: OverlayPanel) -> OverlayPanel? {
        guard moved.isVisible else { return nil }
        var best: (panel: OverlayPanel, ratio: CGFloat)?
        for panel in panels.values
        where panel !== moved && panel.isVisible && moved.frame.intersects(panel.frame) {
            let overlap = moved.frame.intersection(panel.frame)
            let smallerArea = min(
                moved.frame.width * moved.frame.height,
                panel.frame.width * panel.frame.height
            )
            guard smallerArea > 0 else { continue }
            let ratio = (overlap.width * overlap.height) / smallerArea
            if ratio > 0.25, ratio > (best?.ratio ?? 0) {
                best = (panel, ratio)
            }
        }
        return best?.panel
    }

    /// Bırakılan panel bir hedefin üzerindeyse kümeleri birleştirir.
    private func mergeIfDropped(_ moved: OverlayPanel) {
        defer { clearMergeHighlights() }
        guard let target = mergeTarget(for: moved) else { return }
        logger.info("Panel bırakıldı; kümeler birleştiriliyor: \(moved.clusterId, privacy: .public) → \(target.clusterId, privacy: .public)")
        moved.clearStoredPosition()
        clusterStore.merge(cluster: moved.clusterId, into: target.clusterId)
    }
}
