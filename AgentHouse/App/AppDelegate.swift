import AppKit

/// Uygulama yaşam döngüsünü yöneten delegate; overlay paneli ve menü bar denetleyicisini ayağa kaldırır.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayPanel: OverlayPanel?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = OverlayPanel()
        overlayPanel = panel
        menuBarController = MenuBarController(overlayPanel: panel)
        panel.show()
    }
}
