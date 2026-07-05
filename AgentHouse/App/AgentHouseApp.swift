import SwiftUI

/// Uygulamanın SwiftUI giriş noktası; yaşam döngüsü yönetimi AppDelegate'e devredilir.
@main
struct AgentHouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menü bar uygulaması: açılışta görünür pencere yok.
        // Settings sahnesi Faz 8'de SettingsView'a bağlanacak.
        Settings {
            EmptyView()
        }
    }
}
