import AppKit
import SwiftUI
import os

/// Şeffaf, her zaman önde duran, odak çalmayan ve sürüklenebilir overlay paneli.
/// Boyutu, SwiftUI içeriğinin ideal boyutuna göre otomatik ayarlanır.
final class OverlayPanel: NSPanel {
    private static let topLeftDefaultsKey = "overlayPanelTopLeft"
    // Faz 1-3'te alt-sol origin saklanıyordu; ilk açılışta üst-sol kayda taşınır.
    private static let legacyOriginDefaultsKey = "overlayPanelOrigin"
    private static let defaultSize = NSSize(width: 320, height: 140)

    private let logger = Logger(subsystem: "com.agenthouse.app", category: "OverlayPanel")
    private let contentVisibility = OverlayContentVisibility()

    init(
        sessionManager: SessionManager,
        onSessionActivate: @escaping (Session) -> Void = { _ in }
    ) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none

        let hostingView = NSHostingView(
            rootView: OverlayRootView(
                sessionManager: sessionManager,
                visibility: contentVisibility,
                onContentSizeChange: { [weak self] size in
                    self?.resizeToFit(size)
                },
                onSessionActivate: onSessionActivate
            )
        )
        contentView = hostingView

        restorePosition()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistPosition),
            name: NSWindow.didMoveNotification,
            object: self
        )
        // Panel gizlenince/örtülünce maskot animasyonları durdurulur (CPU tasarrufu).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(occlusionStateChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // Odak çalmama garantisi: panel hiçbir zaman key/main pencere olmaz.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Paneli, uygulamayı aktive etmeden öne getirir.
    func show() {
        orderFrontRegardless()
    }

    /// Paneli gizler.
    func hide() {
        orderOut(nil)
    }

    /// Paneli varsayılan köşesine döndürür, yeni pozisyonu kaydeder ve gösterir
    /// (ayarlardaki "pozisyonu sıfırla" butonu için).
    func resetPosition() {
        moveToDefaultPosition()
        persistPosition()
        show()
    }

    /// Görünürlüğü değiştirir ve yeni görünürlük durumunu döndürür.
    @discardableResult
    func toggleVisibility() -> Bool {
        if isVisible {
            hide()
        } else {
            show()
        }
        return isVisible
    }

    // MARK: - Görünürlük → animasyon durdurma

    @objc private func occlusionStateChanged() {
        contentVisibility.isVisible = occlusionState.contains(.visible)
    }

    // MARK: - İçeriğe göre boyutlanma

    /// Paneli, üst-sol köşesi sabit kalacak şekilde içeriğin ideal boyutuna getirir.
    private func resizeToFit(_ contentSize: CGSize) {
        guard contentSize.width >= 1, contentSize.height >= 1 else { return }
        let current = frame
        guard
            abs(current.width - contentSize.width) > 0.5
                || abs(current.height - contentSize.height) > 0.5
        else { return }

        let newFrame = NSRect(
            x: current.origin.x,
            y: current.maxY - contentSize.height,
            width: contentSize.width,
            height: contentSize.height
        )
        setFrame(newFrame, display: true)
    }

    // MARK: - Pozisyon kalıcılığı

    // Boyut içerikle değiştiği için origin (alt-sol) yerine üst-sol köşe saklanır;
    // böylece panel büyüyüp küçülürken ekrandaki yeri sabit algılanır.
    @objc private func persistPosition() {
        let topLeft = NSPoint(x: frame.origin.x, y: frame.maxY)
        UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: Self.topLeftDefaultsKey)
    }

    private func restorePosition() {
        guard let topLeft = storedTopLeft() else {
            moveToDefaultPosition()
            return
        }

        let origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        let restoredFrame = NSRect(origin: origin, size: frame.size)

        // Kaydedilen pozisyon artık hiçbir ekranla kesişmiyorsa (ekran söküldü,
        // çözünürlük değişti) varsayılana dön.
        let intersectsAnyScreen = NSScreen.screens.contains {
            $0.visibleFrame.intersects(restoredFrame)
        }
        guard intersectsAnyScreen else {
            logger.info("Kaydedilen panel pozisyonu ekran dışında; varsayılana dönülüyor.")
            moveToDefaultPosition()
            return
        }

        setFrameOrigin(origin)
    }

    /// Kaydedilmiş üst-sol köşeyi döndürür; yalnızca eski alt-sol kayıt varsa
    /// eski varsayılan boyut üzerinden üst-sola çevirir.
    private func storedTopLeft() -> NSPoint? {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Self.topLeftDefaultsKey) {
            return NSPointFromString(stored)
        }
        if let legacy = defaults.string(forKey: Self.legacyOriginDefaultsKey) {
            let origin = NSPointFromString(legacy)
            return NSPoint(x: origin.x, y: origin.y + Self.defaultSize.height)
        }
        return nil
    }

    private func moveToDefaultPosition() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 24
        let origin = NSPoint(
            x: visible.maxX - frame.width - margin,
            y: visible.maxY - frame.height - margin
        )
        setFrameOrigin(origin)
    }
}

/// Panel içeriğinin ekranda görünür olup olmadığını SwiftUI tarafına taşıyan model;
/// OverlayRootView bunu maskot animasyonlarını durdurmak için kullanır.
final class OverlayContentVisibility: ObservableObject {
    @Published var isVisible = true
}
