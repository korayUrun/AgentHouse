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

            Text("Welcome to AgentHouse")
                .font(.title2.weight(.semibold))

            Text("Watches your Claude Code sessions on a small always-on-top panel: which project is working, which one needs your approval, which one is done.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                explanationRow(
                    icon: "link",
                    text: "Installation adds notification commands to Claude Code's hook settings that run only inside this Mac (127.0.0.1)."
                )
                explanationRow(
                    icon: "arrow.uturn.backward.circle",
                    text: "Your existing settings in ~/.claude/settings.json are untouched; a backup is taken before writing. Removal deletes only AgentHouse's entries."
                )
                explanationRow(
                    icon: "lock.shield",
                    text: "No data is sent to the internet or written to disk. When AgentHouse is closed, Claude Code is not affected at all."
                )
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))

            if installed {
                Label(
                    "Installed. Start a new Claude session and its card will appear on the panel.",
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
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Skip for Now") { dismiss() }
                    Button("Install Hooks & Start") {
                        installError = installHooks()
                        installed = installError == nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 4)

            Text("You can also install or remove the hooks later from Settings.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 460)
        .fixedSize()
    }

    private func explanationRow(icon: String, text: LocalizedStringKey) -> some View {
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
