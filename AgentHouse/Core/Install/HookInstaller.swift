import Foundation
import os

/// `~/.claude/settings.json` dosyasına AgentHouse hook komutlarını güvenle ekleyen/kaldıran kurulumcu.
/// Mevcut içeriği ASLA silmez/ezmez: parse eder, kendi girdilerini merge eder, yazmadan önce yedek alır.
/// `uninstall()` yalnızca AgentHouse'un eklediği girdileri kaldırır.
struct HookInstaller {
    /// Kurulum/kaldırma hataları.
    enum InstallerError: LocalizedError, Equatable {
        case settingsNotJSON

        var errorDescription: String? {
            switch self {
            case .settingsNotJSON:
                return String(localized: "settings.json is not a valid JSON object; the file was left untouched. Fix it manually and try again.")
            }
        }
    }

    /// AgentHouse'un dinlediği hook eventleri.
    static let managedEventNames = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "Notification",
        "Stop",
        "SessionEnd",
    ]

    // Tool eventleri matcher alanı bekler; "*" tüm tool'ları eşler.
    private static let matcherEventNames: Set<String> = ["PreToolUse", "PostToolUse"]

    /// Hook girdilerinin yazıldığı settings dosyası (varsayılan: ~/.claude/settings.json).
    let settingsURL: URL

    /// Hook komutunun POST atacağı port.
    let port: UInt16

    init(settingsURL: URL = HookInstaller.defaultSettingsURL, port: UInt16 = EventServer.defaultPort) {
        self.settingsURL = settingsURL
        self.port = port
    }

    /// Gerçek Claude Code ayar dosyasının yolu.
    static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
    }

    /// Yazmadan önce alınan yedeğin yolu (settings.json.agenthouse-backup).
    var backupURL: URL {
        settingsURL.deletingLastPathComponent()
            .appendingPathComponent(settingsURL.lastPathComponent + ".agenthouse-backup")
    }

    /// settings.json'a eklenen komut. `--max-time 1` ve `|| true` sayesinde uygulama
    /// kapalıyken bile Claude Code'u asla bloklamaz.
    var hookCommand: String {
        "curl -s --max-time 1 -X POST http://127.0.0.1:\(port)/event"
            + " -H 'Content-Type: application/json' -d @- || true"
    }

    /// Bir hook komutunun AgentHouse'a ait olup olmadığını belirler (port değişse bile tanır).
    static func isAgentHouseCommand(_ command: String) -> Bool {
        command.contains("curl") && command.contains("127.0.0.1") && command.contains("/event")
    }

    /// Hook girdilerini merge ederek kurar. Dosya varsa önce yedek alınır; işlem idempotenttir.
    func install() throws {
        var root = try readSettings()
        try backUpExistingFile()

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for eventName in Self.managedEventNames {
            // Beklenmedik tipte mevcut bir değer varsa ona dokunma (veri kaybetme).
            guard hooks[eventName] == nil || hooks[eventName] is [[String: Any]] else { continue }
            var groups = hooks[eventName] as? [[String: Any]] ?? []
            groups = Self.removingAgentHouseEntries(from: groups)
            groups.append(makeHookGroup(for: eventName))
            hooks[eventName] = groups
        }
        root["hooks"] = hooks
        try write(root)
    }

    /// SADECE AgentHouse'un eklediği hook girdilerini kaldırır; kullanıcının girdileri korunur.
    func uninstall() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        var root = try readSettings()
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for (eventName, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned = Self.removingAgentHouseEntries(from: groups)
            if cleaned.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = cleaned
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        try write(root)
    }

    /// En az bir yönetilen event'te AgentHouse girdisi var mı?
    func isInstalled() -> Bool {
        guard
            let root = try? readSettings(),
            let hooks = root["hooks"] as? [String: Any]
        else { return false }

        return hooks.values.contains { value in
            guard let groups = value as? [[String: Any]] else { return false }
            return groups.contains { group in
                guard let hookList = group["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { hook in
                    (hook["command"] as? String).map(Self.isAgentHouseCommand) == true
                }
            }
        }
    }

    // MARK: - Yardımcılar

    private func makeHookGroup(for eventName: String) -> [String: Any] {
        var group: [String: Any] = [
            "hooks": [["type": "command", "command": hookCommand]]
        ]
        if Self.matcherEventNames.contains(eventName) {
            group["matcher"] = "*"
        }
        return group
    }

    /// Grup listesinden AgentHouse komutlarını ayıklar; boşalan gruplar düşürülür,
    /// tanınmayan yapılar olduğu gibi bırakılır.
    private static func removingAgentHouseEntries(from groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            guard let hookList = group["hooks"] as? [[String: Any]], !hookList.isEmpty else {
                return group
            }
            let kept = hookList.filter { hook in
                guard let command = hook["command"] as? String else { return true }
                return !isAgentHouseCommand(command)
            }
            guard !kept.isEmpty else { return nil }
            var newGroup = group
            newGroup["hooks"] = kept
            return newGroup
        }
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty else { return [:] }
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            throw InstallerError.settingsNotJSON
        }
        return dictionary
    }

    private func backUpExistingFile() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: settingsURL.path) else { return }
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: settingsURL, to: backupURL)
    }

    private func write(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: settingsURL, options: .atomic)
    }
}
