import SwiftUI

/// İlk açılışta gösterilen tek ekran: uygulamanın ne yaptığının şeffaf açıklaması
/// ve tek tıkla hook kurulumu.
struct OnboardingView: View {
    /// Hook kurulumunu dener; hata mesajı döndürür (nil = başarı).
    var installHooks: () -> String? = { nil }
    var dismiss: () -> Void = {}

    @State private var installed = false
    @State private var installError: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "house.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text("AgentHouse'a hoş geldin")
                .font(.title2.weight(.semibold))

            Text("Claude Code oturumlarını her zaman önde duran küçük bir panelde izler: "
                + "hangi proje çalışıyor, hangisi senden onay bekliyor, hangisi bitti.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                explanationRow(
                    icon: "link",
                    text: "Kurulum, Claude Code'un hook ayarlarına yalnızca bu Mac içinde "
                        + "(127.0.0.1) çalışan bildirim komutları ekler."
                )
                explanationRow(
                    icon: "arrow.uturn.backward.circle",
                    text: "~/.claude/settings.json'daki mevcut ayarlara dokunulmaz; yazmadan "
                        + "önce yedek alınır. Kaldırma yalnızca AgentHouse girdilerini siler."
                )
                explanationRow(
                    icon: "lock.shield",
                    text: "Hiçbir veri internete gönderilmez veya diske yazılmaz. AgentHouse "
                        + "kapalıyken Claude Code hiç etkilenmez."
                )
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))

            if installed {
                Label(
                    "Kuruldu. Yeni bir Claude oturumu başlattığında kartı panelde göreceksin.",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                .font(.callout)
            } else if let installError {
                Text(installError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack {
                if installed {
                    Button("Bitti") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Şimdilik Atla") { dismiss() }
                    Button("Hook'ları Kur ve Başla") {
                        installError = installHooks()
                        installed = installError == nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 4)

            Text("Hook'ları daha sonra Ayarlar'dan da kurup kaldırabilirsin.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 460)
        .fixedSize()
    }

    private func explanationRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Onboarding penceresini yalnızca ilk açılışta gösteren denetleyici.
final class OnboardingWindowController {
    /// Onboarding'in gösterildiğini işaretleyen UserDefaults anahtarı (UI tercihi; kural 2).
    static let shownDefaultsKey = "onboardingShown"

    private var window: NSWindow?
    private let defaults: UserDefaults
    private let installHooks: () -> String?

    init(defaults: UserDefaults = .standard, installHooks: @escaping () -> String?) {
        self.defaults = defaults
        self.installHooks = installHooks
    }

    /// Daha önce gösterilmediyse pencereyi açar ve gösterildi olarak işaretler
    /// ("Şimdilik atla" diyen kullanıcı kurulumu Ayarlar'dan yapabilir).
    func showIfNeeded() {
        guard !defaults.bool(forKey: Self.shownDefaultsKey) else { return }
        defaults.set(true, forKey: Self.shownDefaultsKey)

        let hosting = NSHostingController(
            rootView: OnboardingView(
                installHooks: installHooks,
                dismiss: { [weak self] in self?.close() }
            )
        )
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.styleMask = [.titled, .closable]
        newWindow.title = "AgentHouse"
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        window = newWindow

        NSApp.activate()
        newWindow.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
        window = nil
    }
}

#Preview {
    OnboardingView()
}
