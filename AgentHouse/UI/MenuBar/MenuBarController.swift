import AppKit

/// Menü bar ikonunu ve menüsünü yöneten denetleyici.
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let overlayPanel: OverlayPanel
    private let togglePanelItem: NSMenuItem
    private let installHooksItem: NSMenuItem
    private let systemNotificationsItem: NSMenuItem

    private let showEventLog: () -> Void
    private let installHooks: () -> Void
    private let uninstallHooks: () -> Void
    private let hooksInstalled: () -> Bool
    private let systemNotificationsEnabled: () -> Bool
    private let setSystemNotificationsEnabled: (Bool) -> Void

    init(
        overlayPanel: OverlayPanel,
        showEventLog: @escaping () -> Void,
        installHooks: @escaping () -> Void,
        uninstallHooks: @escaping () -> Void,
        hooksInstalled: @escaping () -> Bool,
        systemNotificationsEnabled: @escaping () -> Bool,
        setSystemNotificationsEnabled: @escaping (Bool) -> Void
    ) {
        self.overlayPanel = overlayPanel
        self.showEventLog = showEventLog
        self.installHooks = installHooks
        self.uninstallHooks = uninstallHooks
        self.hooksInstalled = hooksInstalled
        self.systemNotificationsEnabled = systemNotificationsEnabled
        self.setSystemNotificationsEnabled = setSystemNotificationsEnabled
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        togglePanelItem = NSMenuItem(title: "Paneli Gizle", action: nil, keyEquivalent: "p")
        installHooksItem = NSMenuItem(title: "Hook'ları Kur", action: nil, keyEquivalent: "")
        systemNotificationsItem = NSMenuItem(title: "Bitince Sistem Bildirimi", action: nil, keyEquivalent: "")
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

        // Gizli debug girdisi: menü açıkken Option'a basılınca panel girdisinin
        // yerinde belirir. Faz 8'de SettingsView'daki gizli "debug log" seçeneğine taşınacak.
        let eventLogItem = NSMenuItem(
            title: "Event Log (Debug)",
            action: #selector(openEventLog),
            keyEquivalent: "p"
        )
        eventLogItem.keyEquivalentModifierMask = [.command, .option]
        eventLogItem.isAlternate = true
        eventLogItem.target = self
        menu.addItem(eventLogItem)

        menu.addItem(.separator())

        installHooksItem.target = self
        installHooksItem.action = #selector(runInstallHooks)
        menu.addItem(installHooksItem)

        let uninstallItem = NSMenuItem(
            title: "Hook'ları Kaldır",
            action: #selector(runUninstallHooks),
            keyEquivalent: ""
        )
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        systemNotificationsItem.target = self
        systemNotificationsItem.action = #selector(toggleSystemNotifications)
        menu.addItem(systemNotificationsItem)

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

    @objc private func openEventLog() {
        showEventLog()
    }

    @objc private func runInstallHooks() {
        installHooks()
    }

    @objc private func runUninstallHooks() {
        uninstallHooks()
    }

    @objc private func toggleSystemNotifications() {
        setSystemNotificationsEnabled(!systemNotificationsEnabled())
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        togglePanelItem.title = overlayPanel.isVisible ? "Paneli Gizle" : "Paneli Göster"
        installHooksItem.state = hooksInstalled() ? .on : .off
        systemNotificationsItem.state = systemNotificationsEnabled() ? .on : .off
    }
}
