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
    /// Tüm panellerin paylaştığı tek maskot tercihleri örneği (ADR-014).
    private let mascotPreferences: MascotPreferences
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
        mascotPreferences: MascotPreferences,
        onSessionActivate: @escaping (Session) -> Void
    ) {
        self.sessionManager = sessionManager
        self.clusterStore = clusterStore
        self.mascotPreferences = mascotPreferences
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
                    // Küme ataması tamamen kalktıysa (birleşme/topla/ana'ya dönüş) pozisyon
                    // kaydı da çöptür; yalnızca boşalan ama HÂLÂ atanmış kümede korunur
                    // (kalıcı yerleşim sonraki oturumlarda kaybolmasın).
                    if !clusterStore.clusterByProject.values.contains(clusterId) {
                        panel.clearStoredPosition()
                    }
                    panels.removeValue(forKey: clusterId)
                }
            }
        }
    }

    private func makePanel(clusterId: String) -> OverlayPanel {
        OverlayPanel(
            sessionManager: sessionManager,
            clusterStore: clusterStore,
            mascotPreferences: mascotPreferences,
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

    /// Sürüklenen panelin üzerinde durduğu hedefi işaretler ve imleç konumunu hedef
    /// panelin içerik uzayına çevirip iletir (kartların aralanması için); diğer
    /// vurguları temizler.
    private func highlightMergeTarget(for moved: OverlayPanel) {
        let target = mergeTarget(for: moved)
        for panel in panels.values {
            let isTarget = panel === target
            if panel.mergeHighlight.isTargeted != isTarget {
                panel.mergeHighlight.isTargeted = isTarget
            }
            if isTarget {
                // Ekran (alt-sol) → pencere → içerik uzayı (üst-sol origin).
                let inWindow = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
                panel.mergeHighlight.hoverPoint = CGPoint(
                    x: inWindow.x,
                    y: panel.frame.height - inWindow.y
                )
            } else if panel.mergeHighlight.hoverPoint != nil {
                panel.mergeHighlight.hoverPoint = nil
            }
        }
    }

    private func clearMergeHighlights() {
        for panel in panels.values {
            panel.mergeHighlight.isTargeted = false
            panel.mergeHighlight.hoverPoint = nil
        }
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

    /// Bırakılan panel bir hedefin üzerindeyse kümeleri, kartlar bırakılan konuma
    /// girecek şekilde birleştirir.
    private func mergeIfDropped(_ moved: OverlayPanel) {
        defer { clearMergeHighlights() }
        guard let target = mergeTarget(for: moved) else { return }

        // Hedefin ve taşınanın o anki görüntü sırası; taşınan kartlar boşluğun
        // açıldığı indekse girer.
        let targetKeys = orderedProjectKeys(inCluster: target.clusterId)
        let movedKeys = orderedProjectKeys(inCluster: moved.clusterId)
        var newOrder = targetKeys
        let index = min(max(target.mergeHighlight.insertionIndex ?? targetKeys.count, 0), targetKeys.count)
        newOrder.insert(contentsOf: movedKeys, at: index)

        logger.info("Panel bırakıldı; kümeler birleştiriliyor: \(moved.clusterId, privacy: .public) → \(target.clusterId, privacy: .public) @\(index)")
        moved.clearStoredPosition()
        clusterStore.merge(projects: movedKeys, from: moved.clusterId, into: target.clusterId, order: newOrder)
    }

    /// Kümenin görüntü sırasındaki proje anahtarları (view ile aynı sıralamayı kullanır).
    private func orderedProjectKeys(inCluster clusterId: String) -> [String] {
        let sessions = sessionManager.sessions.filter {
            clusterStore.clusterId(forProject: $0.projectKey) == clusterId
        }
        return clusterStore.orderedSessions(sessions, inCluster: clusterId)
            .compactMap(\.projectKey)
    }
}
