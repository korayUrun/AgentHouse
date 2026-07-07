import AppKit
import SwiftUI
import os

/// Şeffaf, her zaman önde duran, odak çalmayan ve sürüklenebilir overlay paneli.
final class OverlayPanel: NSPanel {
    private static let originDefaultsKey = "overlayPanelOrigin"
    private static let defaultSize = NSSize(width: 320, height: 140)

    private let logger = Logger(subsystem: "com.agenthouse.app", category: "OverlayPanel")

    init() {
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

        let hostingView = NSHostingView(rootView: OverlayRootView())
        contentView = hostingView

        restorePosition()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistPosition),
            name: NSWindow.didMoveNotification,
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

    // MARK: - Pozisyon kalıcılığı

    @objc private func persistPosition() {
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: Self.originDefaultsKey)
    }

    private func restorePosition() {
        guard
            let stored = UserDefaults.standard.string(forKey: Self.originDefaultsKey)
        else {
            moveToDefaultPosition()
            return
        }

        let origin = NSPointFromString(stored)
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
