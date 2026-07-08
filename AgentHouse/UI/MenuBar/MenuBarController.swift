import AppKit
import SwiftUI

/// Menü bar ikonunu ve tıklanınca açılan popover'ı (oturum özeti + eylemler) yöneten denetleyici.
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(
        overlayCoordinator: OverlayCoordinator,
        sessionManager: SessionManager,
        openSettings: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        super.init()

        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                sessionManager: sessionManager,
                isPanelVisible: { overlayCoordinator.isAnyPanelVisible },
                togglePanel: { overlayCoordinator.toggleAllPanels() },
                gatherAllCards: { overlayCoordinator.gatherAllCards() },
                openSettings: { [weak self] in
                    self?.popover.performClose(nil)
                    openSettings()
                }
            )
        )

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "house.fill",
                accessibilityDescription: "AgentHouse"
            )
            button.target = self
            button.action = #selector(togglePopover)
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            // LSUIElement uygulamada transient popover'ın dış tıklamayla kapanması
            // için uygulamanın aktif olması gerekir.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
