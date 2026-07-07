import AppKit
import Combine
import os

/// Uygulama yaşam döngüsünü yöneten delegate; overlay paneli, event sunucusunu,
/// menü bar denetleyicisini, ayarlar ve onboarding pencerelerini ayağa kaldırır.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayPanel: OverlayPanel?
    private var menuBarController: MenuBarController?
    private var eventServer: EventServer?
    private var sessionManager: SessionManager?
    private var eventLogStore: EventLogStore?
    private var eventLogWindowController: EventLogWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var systemNotifier: SystemNotifier?
    private var usageReader: UsageReader?
    private var serverCancellable: AnyCancellable?
    private var serverStatusCancellable: AnyCancellable?
    /// Listener düşünce bir kez sessizce yeniden denenir; ikinci hata kullanıcıya gösterilir.
    private var serverRestartAttempted = false
    private var cancellables = Set<AnyCancellable>()
    private let terminalFocuser = TerminalFocuser()
    private let logger = Logger(subsystem: "com.agenthouse.app", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit testler bu uygulamayı host olarak başlatır; test sırasında UI ve sunucu kurulmaz.
        guard NSClassFromString("XCTestCase") == nil else { return }

        let manager = SessionManager(
            longTaskThreshold: SessionManager.configuredLongTaskThreshold(),
            frontmostApp: { [terminalFocuser] in terminalFocuser.frontmostApplicationBundleId() }
        )
        manager.startStaleMonitoring()
        sessionManager = manager

        let panel = OverlayPanel(
            sessionManager: manager,
            onSessionActivate: { [terminalFocuser] session in
                terminalFocuser.focusApplication(bundleId: session.sourceBundleId)
            }
        )
        overlayPanel = panel

        let logStore = EventLogStore()
        eventLogStore = logStore
        let logWindowController = EventLogWindowController(store: logStore, sessionManager: manager)
        eventLogWindowController = logWindowController

        let notifier = SystemNotifier()
        systemNotifier = notifier
        manager.longTaskCompleted
            .sink { notifier.notifyLongTaskCompleted($0) }
            .store(in: &cancellables)

        let reader = UsageReader()
        usageReader = reader
        reader.usageUpdated
            .receive(on: DispatchQueue.main)
            .sink { update in
                manager.updateUsage(update.usage, forSession: update.sessionId)
            }
            .store(in: &cancellables)
        reader.limitDetected
            .receive(on: DispatchQueue.main)
            .sink { sessionId in
                manager.applyLimitSignal(toSession: sessionId)
            }
            .store(in: &cancellables)

        startServer(port: EventServer.configuredPort())

        settingsWindowController = SettingsWindowController(actions: makeSettingsActions())

        menuBarController = MenuBarController(
            overlayPanel: panel,
            sessionManager: manager,
            openSettings: { [weak self] in self?.settingsWindowController?.show() }
        )
        panel.show()

        onboardingWindowController = OnboardingWindowController { [weak self] in
            self?.installHooksQuietly()
        }
        onboardingWindowController?.showIfNeeded()

        // Uyku sonrası listener düşmüş olabilir; uyanınca sağlık kontrolü yapılır.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        eventServer?.stop()
    }

    /// Uyanma sonrası listener sağlıklı değilse sessizce yeniden kurulur.
    @objc private func systemDidWake() {
        guard let server = eventServer, server.currentStatus != .ready else { return }
        logger.info("Uyanma sonrası EventServer sağlıklı değil; yeniden başlatılıyor.")
        serverRestartAttempted = false
        startServer(port: EventServer.configuredPort())
    }

    // MARK: - Event sunucusu

    /// Sunucuyu verilen portta başlatır ve event akışını ilgili tüketicilere bağlar.
    /// Port değişiminde eski sunucu durdurulup aboneliğiyle birlikte değiştirilir.
    private func startServer(port: UInt16) {
        eventServer?.stop()
        let server = EventServer(port: port)
        eventServer = server
        serverCancellable = server.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.eventLogStore?.append(event)
                self?.sessionManager?.handle(event)
                self?.usageReader?.handle(event)
            }
        serverStatusCancellable = server.status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handleServerStatus(status, port: port)
            }
        do {
            try server.start()
        } catch {
            logger.error("EventServer başlatılamadı: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Listener durum değişimlerini işler: port çakışması gibi asenkron hatalarda önce
    /// bir kez sessiz yeniden deneme, tekrarında kullanıcıya uyarı gösterilir.
    private func handleServerStatus(_ status: EventServer.ListenerStatus, port: UInt16) {
        switch status {
        case .ready:
            serverRestartAttempted = false
        case .failed(let reason):
            if serverRestartAttempted {
                showAlert(
                    title: String(localized: "Event server could not start"),
                    message: String(localized: "Port \(String(port)) appears to be in use (\(reason)). Pick a different port in Settings; hook events will not arrive until the server is running."),
                    style: .warning
                )
            } else {
                serverRestartAttempted = true
                logger.info("EventServer düştü; 2 sn sonra yeniden denenecek.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.eventServer?.currentStatus != .ready else { return }
                    self.startServer(port: EventServer.configuredPort())
                }
            }
        case .idle:
            break
        }
    }

    /// Ayarlardan port değişimi: kaydet, sunucuyu yeni portla yeniden başlat,
    /// hook'lar kuruluysa komutları yeni portla güncelle.
    private func applyPort(_ port: UInt16) {
        UserDefaults.standard.set(Int(port), forKey: EventServer.portDefaultsKey)
        startServer(port: port)

        let installer = HookInstaller(port: port)
        if installer.isInstalled() {
            do {
                try installer.install()
                logger.info("Hook komutları yeni portla güncellendi: \(port)")
            } catch {
                logger.error("Hook portu güncellenemedi: \(error.localizedDescription, privacy: .public)")
                showAlert(
                    title: String(localized: "Hooks could not be updated"),
                    message: String(localized: "The server is now listening on port \(String(port)) but the hook commands still use the old port: \(error.localizedDescription)"),
                    style: .warning
                )
            }
        }
    }

    // MARK: - Ayarlar

    private func makeSettingsActions() -> SettingsView.Actions {
        var actions = SettingsView.Actions()
        actions.installHooks = { [weak self] in self?.installHooks() }
        actions.uninstallHooks = { [weak self] in self?.uninstallHooks() }
        actions.hooksInstalled = { HookInstaller().isInstalled() }
        actions.applyPort = { [weak self] port in self?.applyPort(port) }
        actions.currentPort = { EventServer.configuredPort() }
        actions.resetPanelPosition = { [weak self] in self?.overlayPanel?.resetPosition() }
        actions.setBannerThreshold = { [weak self] threshold in
            UserDefaults.standard.set(threshold, forKey: SessionManager.longTaskThresholdDefaultsKey)
            self?.sessionManager?.setLongTaskThreshold(threshold)
        }
        actions.systemNotificationsEnabled = { [weak self] in self?.systemNotifier?.isEnabled ?? false }
        actions.setSystemNotificationsEnabled = { [weak self] enabled in
            self?.systemNotifier?.setEnabled(enabled)
        }
        actions.openEventLog = { [weak self] in self?.eventLogWindowController?.show() }
        return actions
    }

    // MARK: - Hook kurulumu

    private func installHooks() {
        let installer = HookInstaller(port: EventServer.configuredPort())
        do {
            try installer.install()
            logger.info("Hook'lar kuruldu.")
            showAlert(
                title: String(localized: "Hooks installed"),
                message: String(localized: "Claude Code hooks were added; a backup of your previous settings is at settings.json.agenthouse-backup. Events start flowing from NEWLY started Claude sessions.")
            )
        } catch {
            logger.error("Hook kurulumu başarısız: \(error.localizedDescription, privacy: .public)")
            showAlert(
                title: String(localized: "Hook installation failed"),
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    /// Onboarding için alert'siz kurulum; hata mesajı döndürür (nil = başarı).
    private func installHooksQuietly() -> String? {
        let installer = HookInstaller(port: EventServer.configuredPort())
        do {
            try installer.install()
            logger.info("Hook'lar kuruldu (onboarding).")
            return nil
        } catch {
            logger.error("Hook kurulumu başarısız: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    private func uninstallHooks() {
        let installer = HookInstaller(port: EventServer.configuredPort())
        do {
            try installer.uninstall()
            logger.info("Hook'lar kaldırıldı.")
            showAlert(
                title: String(localized: "Hooks removed"),
                message: String(localized: "Only the entries AgentHouse added were removed from settings.json.")
            )
        } catch {
            logger.error("Hook kaldırma başarısız: \(error.localizedDescription, privacy: .public)")
            showAlert(
                title: String(localized: "Hook removal failed"),
                message: error.localizedDescription,
                style: .warning
            )
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
