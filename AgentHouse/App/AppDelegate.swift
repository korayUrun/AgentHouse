import AppKit
import Combine
import os

/// Uygulama yaşam döngüsünü yöneten delegate; overlay paneli, event sunucusunu ve
/// menü bar denetleyicisini ayağa kaldırır.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayPanel: OverlayPanel?
    private var menuBarController: MenuBarController?
    private var eventServer: EventServer?
    private var sessionManager: SessionManager?
    private var eventLogStore: EventLogStore?
    private var eventLogWindowController: EventLogWindowController?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.agenthouse.app", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit testler bu uygulamayı host olarak başlatır; test sırasında UI ve sunucu kurulmaz.
        guard NSClassFromString("XCTestCase") == nil else { return }

        let manager = SessionManager()
        manager.startStaleMonitoring()
        sessionManager = manager

        let panel = OverlayPanel(sessionManager: manager)
        overlayPanel = panel

        let logStore = EventLogStore()
        eventLogStore = logStore
        let logWindowController = EventLogWindowController(store: logStore, sessionManager: manager)
        eventLogWindowController = logWindowController

        let server = EventServer(port: EventServer.configuredPort())
        eventServer = server
        server.events
            .receive(on: DispatchQueue.main)
            .sink { event in
                logStore.append(event)
                manager.handle(event)
            }
            .store(in: &cancellables)
        do {
            try server.start()
        } catch {
            logger.error("EventServer başlatılamadı: \(error.localizedDescription, privacy: .public)")
        }

        menuBarController = MenuBarController(
            overlayPanel: panel,
            showEventLog: { logWindowController.show() },
            installHooks: { [weak self] in self?.installHooks() },
            uninstallHooks: { [weak self] in self?.uninstallHooks() },
            hooksInstalled: { HookInstaller().isInstalled() }
        )
        panel.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventServer?.stop()
    }

    // MARK: - Hook kurulumu

    private func installHooks() {
        let installer = HookInstaller(port: EventServer.configuredPort())
        do {
            try installer.install()
            logger.info("Hook'lar kuruldu.")
            showAlert(
                title: "Hook'lar kuruldu",
                message: "Claude Code hook'ları eklendi; mevcut ayarların yedeği "
                    + "settings.json.agenthouse-backup dosyasında. Eventler YENİ başlayan "
                    + "Claude oturumlarından akmaya başlar."
            )
        } catch {
            logger.error("Hook kurulumu başarısız: \(error.localizedDescription, privacy: .public)")
            showAlert(title: "Hook kurulumu başarısız", message: error.localizedDescription, style: .warning)
        }
    }

    private func uninstallHooks() {
        let installer = HookInstaller(port: EventServer.configuredPort())
        do {
            try installer.uninstall()
            logger.info("Hook'lar kaldırıldı.")
            showAlert(
                title: "Hook'lar kaldırıldı",
                message: "settings.json'dan yalnızca AgentHouse'un eklediği girdiler çıkarıldı."
            )
        } catch {
            logger.error("Hook kaldırma başarısız: \(error.localizedDescription, privacy: .public)")
            showAlert(title: "Hook kaldırma başarısız", message: error.localizedDescription, style: .warning)
        }
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
