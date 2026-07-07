import Foundation
import UserNotifications
import os

/// İsteğe bağlı macOS sistem bildirimi: uzun bir iş bittiğinde UNUserNotificationCenter
/// üzerinden bildirim atar. Varsayılan KAPALI; menü barından açılır (Faz 8'de SettingsView'a taşınır).
final class SystemNotifier {
    /// UserDefaults anahtarı; yalnızca UI tercihi saklanır (kural 2).
    static let enabledDefaultsKey = "systemNotificationsEnabled"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.agenthouse.app", category: "SystemNotifier")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Kullanıcının sistem bildirimini açıp açmadığı.
    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledDefaultsKey)
    }

    /// Tercihi kaydeder; sistem izni yalnızca kullanıcı özelliği AÇTIĞINDA istenir.
    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [logger] granted, error in
            if let error {
                logger.error("Bildirim izni istenemedi: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                logger.info("Bildirim izni verilmedi; özellik açık ama bildirimler sistemce engellenecek.")
            }
        }
    }

    /// Uzun bir işin bittiğini bildirir; özellik kapalıysa hiçbir şey yapmaz.
    func notifyLongTaskCompleted(_ completion: LongTaskCompletion) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = completion.projectName
        content.body = String(localized: "Claude finished its task.")
        let request = UNNotificationRequest(
            identifier: completion.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error("Bildirim gönderilemedi: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
