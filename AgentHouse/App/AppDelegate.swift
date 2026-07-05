import AppKit

/// Uygulama yaşam döngüsünü yöneten delegate; menü bar denetleyicisini ayağa kaldırır.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
    }
}
