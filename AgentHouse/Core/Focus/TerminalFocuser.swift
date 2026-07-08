import AppKit
import os

/// Oturumun kaynak uygulamasını (Terminal/iTerm/VS Code vb.) öne getiren ince AppKit sarmalayıcı.
/// Hook payload'ı kaynak uygulamayı taşımadığından, SessionStart/UserPromptSubmit anındaki
/// önplan uygulaması best-effort kaynak kabul edilir. Pencere düzeyinde eşleşme garanti
/// edilmez; uygulama düzeyinde aktive edilir (v1.0 kapsamı — Accessibility izni gerektirmez).
struct TerminalFocuser {
    private let logger = Logger(subsystem: "com.agenthouse.app", category: "TerminalFocuser")

    /// Klasör argümanıyla açıldığında o klasörün MEVCUT penceresini öne getiren editörler.
    /// Bu davranış editörün kendisinden gelir; Accessibility izni gerekmez.
    private static let folderAwareEditorBundleIds: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
    ]

    /// O an önplandaki uygulamanın bundle id'si; önplan biz isek veya okunamıyorsa nil.
    func frontmostApplicationBundleId() -> String? {
        guard
            let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            bundleId != Bundle.main.bundleIdentifier
        else { return nil }
        return bundleId
    }

    /// Oturumun kaynağını öne getirir: kaynak klasör-bilinçli bir editörse (VS Code
    /// ailesi) cwd'yi o editörle "açarak" doğru PENCERENİN odaklanmasını sağlar;
    /// değilse uygulama düzeyinde aktive eder.
    @discardableResult
    func focusSession(bundleId: String?, cwd: String?) -> Bool {
        if
            let bundleId,
            let cwd, !cwd.isEmpty,
            Self.folderAwareEditorBundleIds.contains(bundleId),
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
            FileManager.default.fileExists(atPath: cwd)
        {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: cwd, isDirectory: true)],
                withApplicationAt: appURL,
                configuration: configuration
            ) { [logger] _, error in
                if let error {
                    logger.info("Editörde klasör odaklama başarısız: \(error.localizedDescription, privacy: .public)")
                }
            }
            return true
        }
        return focusApplication(bundleId: bundleId)
    }

    /// Verilen bundle id'ye sahip çalışan uygulamayı öne getirir; uygulama artık
    /// çalışmıyorsa veya id bilinmiyorsa hiçbir şey yapmaz ve false döner.
    @discardableResult
    func focusApplication(bundleId: String?) -> Bool {
        guard let bundleId else {
            logger.info("Oturumun kaynak uygulaması bilinmiyor; odaklama atlandı.")
            return false
        }
        let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId)
            .first { !$0.isTerminated }
        guard let running else {
            logger.info("Kaynak uygulama artık çalışmıyor: \(bundleId, privacy: .public)")
            return false
        }
        return running.activate()
    }
}
