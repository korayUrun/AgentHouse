import XCTest
@testable import AgentHouse

/// HookInstaller'ın yedekleme, merge ve geri alma davranışlarını geçici bir dizinde doğrular.
final class HookInstallerTests: XCTestCase {
    private var directory: URL!
    private var settingsURL: URL!
    private var installer: HookInstaller!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenthouse-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settingsURL = directory.appendingPathComponent("settings.json")
        installer = HookInstaller(settingsURL: settingsURL, port: 48756)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Yardımcılar

    private func writeSettings(_ json: String) throws {
        try Data(json.utf8).write(to: settingsURL)
    }

    private func readRoot() throws -> [String: Any] {
        let data = try Data(contentsOf: settingsURL)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func hookGroups(in root: [String: Any], event: String) -> [[String: Any]] {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        return hooks[event] as? [[String: Any]] ?? []
    }

    private func agentHouseCommands(in root: [String: Any], event: String) -> [String] {
        hookGroups(in: root, event: event).flatMap { group -> [String] in
            let hookList = group["hooks"] as? [[String: Any]] ?? []
            return hookList
                .compactMap { $0["command"] as? String }
                .filter(HookInstaller.isAgentHouseCommand)
        }
    }

    // MARK: - Kurulum

    func testInstallCreatesSettingsWithAllManagedEvents() throws {
        try installer.install()

        let root = try readRoot()
        for event in HookInstaller.managedEventNames {
            let commands = agentHouseCommands(in: root, event: event)
            XCTAssertEqual(commands.count, 1, "\(event) için tam bir AgentHouse girdisi bekleniyordu")

            let command = try XCTUnwrap(commands.first)
            XCTAssertTrue(command.contains("--max-time 1"), "Komut Claude Code'u bloklamamalı")
            XCTAssertTrue(command.hasSuffix("|| true"), "Komut hata durumunda da 0 dönmeli")
            XCTAssertTrue(command.contains("http://127.0.0.1:48756/event"))
        }
    }

    func testInstallAddsMatcherOnlyToToolEvents() throws {
        try installer.install()

        let root = try readRoot()
        for event in ["PreToolUse", "PostToolUse"] {
            let group = try XCTUnwrap(hookGroups(in: root, event: event).first)
            XCTAssertEqual(group["matcher"] as? String, "*")
        }
        for event in ["SessionStart", "Stop", "Notification"] {
            let group = try XCTUnwrap(hookGroups(in: root, event: event).first)
            XCTAssertNil(group["matcher"])
        }
    }

    func testInstallBacksUpExistingFile() throws {
        let original = #"{"model": "opus"}"#
        try writeSettings(original)

        try installer.install()

        let backupData = try Data(contentsOf: installer.backupURL)
        XCTAssertEqual(String(data: backupData, encoding: .utf8), original)
    }

    func testInstallDoesNotCreateBackupWhenFileMissing() throws {
        try installer.install()

        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.backupURL.path))
    }

    func testSecondInstallKeepsOriginalPristineBackup() throws {
        // Yedek yalnızca İLK yazımdan önce alınır; ikinci install (ör. port değişimi)
        // yedeği ezmemeli, aksi halde yedek de AgentHouse girdilerini içerir.
        let original = #"{"model": "opus"}"#
        try writeSettings(original)

        try installer.install()
        try installer.install()

        let backupData = try Data(contentsOf: installer.backupURL)
        XCTAssertEqual(
            String(data: backupData, encoding: .utf8),
            original,
            "Yedek ilk (pristine) içerikte kalmalı; AgentHouse girdileriyle kirlenmemeli"
        )
    }

    func testInstallPreservesUnrelatedSettingsAndUserHooks() throws {
        try writeSettings(
            """
            {
                "model": "opus",
                "permissions": {"allow": ["Bash(ls:*)"]},
                "hooks": {
                    "SessionStart": [
                        {"hooks": [{"type": "command", "command": "echo kullanici-hooku"}]}
                    ]
                }
            }
            """
        )

        try installer.install()

        let root = try readRoot()
        XCTAssertEqual(root["model"] as? String, "opus")
        XCTAssertNotNil(root["permissions"])

        let sessionStartGroups = hookGroups(in: root, event: "SessionStart")
        XCTAssertEqual(sessionStartGroups.count, 2, "Kullanıcı girdisi korunup bizimki eklenmeli")

        let userCommands = sessionStartGroups.flatMap { group -> [String] in
            let hookList = group["hooks"] as? [[String: Any]] ?? []
            return hookList.compactMap { $0["command"] as? String }
        }
        XCTAssertTrue(userCommands.contains("echo kullanici-hooku"))
    }

    func testInstallIsIdempotent() throws {
        try installer.install()
        try installer.install()

        let root = try readRoot()
        for event in HookInstaller.managedEventNames {
            XCTAssertEqual(
                agentHouseCommands(in: root, event: event).count,
                1,
                "\(event) için tekrar kurulumda kopya girdi oluşmamalı"
            )
        }
    }

    func testInstallThrowsOnCorruptJSONWithoutTouchingFile() throws {
        let corrupt = "bu { json değil"
        try writeSettings(corrupt)

        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? HookInstaller.InstallerError, .settingsNotJSON)
        }

        let data = try Data(contentsOf: settingsURL)
        XCTAssertEqual(String(data: data, encoding: .utf8), corrupt, "Bozuk dosya asla ezilmemeli")
    }

    // MARK: - Kaldırma

    func testUninstallRemovesOnlyOurEntries() throws {
        try writeSettings(
            """
            {
                "hooks": {
                    "SessionStart": [
                        {"hooks": [{"type": "command", "command": "echo kullanici-hooku"}]}
                    ]
                }
            }
            """
        )
        try installer.install()

        try installer.uninstall()

        let root = try readRoot()
        for event in HookInstaller.managedEventNames {
            XCTAssertTrue(agentHouseCommands(in: root, event: event).isEmpty)
        }
        let sessionStartGroups = hookGroups(in: root, event: "SessionStart")
        XCTAssertEqual(sessionStartGroups.count, 1, "Kullanıcının kendi hook'u korunmalı")

        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertNil(hooks["Stop"], "Boşalan event anahtarları temizlenmeli")
    }

    func testInstallThenUninstallRestoresEquivalentSettings() throws {
        try writeSettings(
            """
            {
                "model": "opus",
                "statusLine": {"type": "command", "command": "starship"},
                "hooks": {
                    "PreToolUse": [
                        {"matcher": "Bash", "hooks": [{"type": "command", "command": "echo denetim"}]}
                    ]
                }
            }
            """
        )
        let originalRoot = try readRoot()

        try installer.install()
        try installer.uninstall()

        let finalRoot = try readRoot()
        XCTAssertEqual(
            NSDictionary(dictionary: finalRoot),
            NSDictionary(dictionary: originalRoot),
            "Kaldırma sonrası settings.json kurulum öncesiyle eşdeğer olmalı"
        )
    }

    func testUninstallWithoutFileDoesNothing() throws {
        XCTAssertNoThrow(try installer.uninstall())
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
    }

    func testUninstallPreservesThirdPartyLocalhostHook() throws {
        // Başka bir aracın localhost hook'u AgentHouse imzası taşımaz; kaldırma onu silmemeli.
        // Eski gevşek eşleşme (curl + 127.0.0.1 + /event) bunu yanlışlıkla siliyordu.
        let thirdParty = "curl -s -X POST http://127.0.0.1:9999/event -d @-"
        try writeSettings(
            """
            {
                "hooks": {
                    "Stop": [
                        {"hooks": [{"type": "command", "command": "\(thirdParty)"}]}
                    ]
                }
            }
            """
        )
        try installer.install()
        try installer.uninstall()

        let root = try readRoot()
        let stopCommands = hookGroups(in: root, event: "Stop").flatMap { group -> [String] in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
        XCTAssertTrue(
            stopCommands.contains(thirdParty),
            "Üçüncü tarafın localhost hook'u silinmemeli (imza artık AgentHouse'a özgü)"
        )
    }

    // MARK: - Durum sorgusu

    func testIsInstalledReflectsState() throws {
        XCTAssertFalse(installer.isInstalled())

        try installer.install()
        XCTAssertTrue(installer.isInstalled())

        try installer.uninstall()
        XCTAssertFalse(installer.isInstalled())
    }
}
