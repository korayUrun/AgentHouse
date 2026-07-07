import AppKit
import os

/// Oturumun kaynak uygulamasını (Terminal/iTerm/VS Code vb.) öne getiren ince AppKit sarmalayıcı.
/// Hook payload'ı kaynak uygulamayı taşımadığından, SessionStart/UserPromptSubmit anındaki
/// önplan uygulaması best-effort kaynak kabul edilir. Pencere düzeyinde eşleşme garanti
/// edilmez; uygulama düzeyinde aktive edilir (v1.0 kapsamı — Accessibility izni gerektirmez).
struct TerminalFocuser {
    private let logger = Logger(subsystem: "com.agenthouse.app", category: "TerminalFocuser")

    /// O an önplandaki uygulamanın bundle id'si; önplan biz isek veya okunamıyorsa nil.
    func frontmostApplicationBundleId() -> String? {
        guard
            let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            bundleId != Bundle.main.bundleIdentifier
        else { return nil }
        return bundleId
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
