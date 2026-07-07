import AppKit

/// Menü bar ikonunu ve menüsünü yöneten denetleyici.
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let overlayPanel: OverlayPanel
    private let togglePanelItem: NSMenuItem

    init(overlayPanel: OverlayPanel) {
        self.overlayPanel = overlayPanel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        togglePanelItem = NSMenuItem(title: "Paneli Gizle", action: nil, keyEquivalent: "p")
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "house.fill",
                accessibilityDescription: "AgentHouse"
            )
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        togglePanelItem.target = self
        togglePanelItem.action = #selector(togglePanel)
        menu.addItem(togglePanelItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "AgentHouse'u Kapat",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        return menu
    }

    @objc private func togglePanel() {
        overlayPanel.toggleVisibility()
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        togglePanelItem.title = overlayPanel.isVisible ? "Paneli Gizle" : "Paneli Göster"
    }
}
