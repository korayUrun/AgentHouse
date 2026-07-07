import ServiceManagement
import SwiftUI

/// Ayarlar penceresi içeriği: genel tercihler, panel davranışı, hook kurulumu ve
/// gelişmiş ayarlar. Alt sistemlere doğrudan bağlanmaz; eylemler enjekte edilir.
struct SettingsView: View {
    /// AppDelegate'ten enjekte edilen eylemler.
    struct Actions {
        var installHooks: () -> Void = {}
        var uninstallHooks: () -> Void = {}
        var hooksInstalled: () -> Bool = { false }
        var applyPort: (UInt16) -> Void = { _ in }
        var currentPort: () -> UInt16 = { 0 }
        var resetPanelPosition: () -> Void = {}
        var setBannerThreshold: (TimeInterval) -> Void = { _ in }
        var systemNotificationsEnabled: () -> Bool = { false }
        var setSystemNotificationsEnabled: (Bool) -> Void = { _ in }
        var openEventLog: () -> Void = {}
    }

    let actions: Actions

    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var notificationsEnabled = false
    @State private var bannerThreshold = SessionManager.configuredLongTaskThreshold()
    @State private var hooksInstalled = false
    @State private var portText = ""
    @State private var portError: String?

    var body: some View {
        Form {
            generalSection
            panelSection
            hooksSection
            advancedSection
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        .onAppear(perform: refresh)
    }

    /// Dışarıda (menü/onboarding üzerinden) değişmiş olabilecek durumları tazeler.
    private func refresh() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        notificationsEnabled = actions.systemNotificationsEnabled()
        bannerThreshold = SessionManager.configuredLongTaskThreshold()
        hooksInstalled = actions.hooksInstalled()
        portText = String(actions.currentPort())
    }

    // MARK: - Genel

    private var generalSection: some View {
        Section("Genel") {
            Toggle("Login'de başlat", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Toggle("İş bitince sistem bildirimi", isOn: $notificationsEnabled)
                .onChange(of: notificationsEnabled) { _, enabled in
                    actions.setSystemNotificationsEnabled(enabled)
                }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Ayarlanamadı: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Panel

    private var panelSection: some View {
        Section("Panel") {
            LabeledContent("Pozisyon") {
                Button("Varsayılana Sıfırla") {
                    actions.resetPanelPosition()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Stepper(value: $bannerThreshold, in: 10...600, step: 10) {
                    Text("Bitti bildirimi eşiği: \(Int(bannerThreshold)) sn")
                }
                .onChange(of: bannerThreshold) { _, threshold in
                    actions.setBannerThreshold(threshold)
                }
                Text("Bundan kısa süren işler banner/bildirim çıkarmaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Hook'lar

    private var hooksSection: some View {
        Section("Claude Code Hook'ları") {
            LabeledContent("Durum") {
                Label(
                    hooksInstalled ? "Kurulu" : "Kurulu değil",
                    systemImage: hooksInstalled ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(hooksInstalled ? .green : .secondary)
            }

            HStack {
                Button("Hook'ları Kur") {
                    actions.installHooks()
                    hooksInstalled = actions.hooksInstalled()
                }
                Button("Hook'ları Kaldır") {
                    actions.uninstallHooks()
                    hooksInstalled = actions.hooksInstalled()
                }
            }

            Text("~/.claude/settings.json'a yalnızca AgentHouse'un event komutları eklenir; "
                + "mevcut ayarların yedeği settings.json.agenthouse-backup dosyasına alınır. "
                + "Kaldırma yalnızca AgentHouse girdilerini siler.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Gelişmiş

    private var advancedSection: some View {
        Section("Gelişmiş") {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Dinleme portu") {
                    HStack {
                        TextField("48756", text: $portText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        Button("Uygula") { applyPort() }
                    }
                }
                if let portError {
                    Text(portError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Değişiklik anında uygulanır; kurulu hook'lar yeni portla güncellenir. "
                    + "Açık Claude oturumları eski portu kullanmaya devam edebilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Debug") {
                Button("Event Log'u Aç") {
                    actions.openEventLog()
                }
            }
        }
    }

    private func applyPort() {
        guard let port = UInt16(portText), port >= 1024 else {
            portError = "Port 1024-65535 aralığında bir sayı olmalı."
            return
        }
        portError = nil
        actions.applyPort(port)
        portText = String(actions.currentPort())
    }
}

/// Ayarlar penceresini tembel oluşturup öne getiren denetleyici (LSUIElement
/// uygulamada SwiftUI Settings sahnesi yerine AppKit penceresi kullanılır).
final class SettingsWindowController {
    private var window: NSWindow?
    private let actions: SettingsView.Actions

    init(actions: SettingsView.Actions) {
        self.actions = actions
    }

    /// Pencereyi (gerekirse oluşturup) öne getirir.
    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(actions: actions))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.styleMask = [.titled, .closable]
            newWindow.title = "AgentHouse Ayarları"
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

#Preview {
    SettingsView(actions: SettingsView.Actions())
}
