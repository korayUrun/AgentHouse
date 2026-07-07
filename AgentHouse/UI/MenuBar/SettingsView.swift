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
        Section("General") {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Toggle("System notification when a task finishes", isOn: $notificationsEnabled)
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
            launchAtLoginError = String(localized: "Could not update: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Panel

    private var panelSection: some View {
        Section("Panel") {
            LabeledContent("Position") {
                Button("Reset to Default") {
                    actions.resetPanelPosition()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Stepper(value: $bannerThreshold, in: 10...600, step: 10) {
                    Text("Done banner threshold: \(Int(bannerThreshold)) s")
                }
                .onChange(of: bannerThreshold) { _, threshold in
                    actions.setBannerThreshold(threshold)
                }
                Text("Tasks shorter than this don't show a banner or notification.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Hook'lar

    private var hooksSection: some View {
        Section("Claude Code Hooks") {
            LabeledContent("Status") {
                Label(
                    hooksInstalled ? "Installed" : "Not installed",
                    systemImage: hooksInstalled ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(hooksInstalled ? .green : .secondary)
            }

            HStack {
                Button("Install Hooks") {
                    actions.installHooks()
                    hooksInstalled = actions.hooksInstalled()
                }
                Button("Remove Hooks") {
                    actions.uninstallHooks()
                    hooksInstalled = actions.hooksInstalled()
                }
            }

            Text("Only AgentHouse's event commands are added to ~/.claude/settings.json; a backup of your existing settings is saved as settings.json.agenthouse-backup. Removal deletes only AgentHouse's entries.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Gelişmiş

    private var advancedSection: some View {
        Section("Advanced") {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Listening port") {
                    HStack {
                        TextField(text: $portText, prompt: Text(verbatim: "48756")) {
                            Text("Listening port")
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .labelsHidden()
                        Button("Apply") { applyPort() }
                    }
                }
                if let portError {
                    Text(portError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Applied immediately; installed hooks are updated to the new port. Already-open Claude sessions may keep using the old port.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Debug") {
                Button("Open Event Log") {
                    actions.openEventLog()
                }
            }
        }
    }

    private func applyPort() {
        guard let port = UInt16(portText), port >= 1024 else {
            portError = String(localized: "Port must be a number between 1024 and 65535.")
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
            newWindow.title = String(localized: "AgentHouse Settings")
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
