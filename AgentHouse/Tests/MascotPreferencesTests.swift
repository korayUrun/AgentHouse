import XCTest
@testable import AgentHouse

/// Proje → maskot karakteri tercih deposunu doğrular (ADR-014).
final class MascotPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MascotPreferencesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testUnknownProjectFallsBackToDefault() {
        let preferences = MascotPreferences(defaults: defaults)

        XCTAssertEqual(preferences.character(forProject: "/Users/dev/blog"), .default)
        XCTAssertEqual(preferences.character(forProject: nil), .default)
    }

    func testChoicePersistsAcrossInstances() {
        MascotPreferences(defaults: defaults)
            .setCharacter(.rocket, forProject: "/Users/dev/blog")

        let reloaded = MascotPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.character(forProject: "/Users/dev/blog"), .rocket)
        XCTAssertEqual(reloaded.character(forProject: "/Users/dev/other"), .default)
    }

    func testSelectingDefaultRemovesStoredEntry() {
        let preferences = MascotPreferences(defaults: defaults)
        preferences.setCharacter(.lighthouse, forProject: "/Users/dev/blog")
        preferences.setCharacter(.default, forProject: "/Users/dev/blog")

        XCTAssertEqual(preferences.character(forProject: "/Users/dev/blog"), .default)
        XCTAssertNil(defaults.dictionary(forKey: MascotPreferences.defaultsKey)?["/Users/dev/blog"])
    }

    func testCorruptStoredValueIsIgnored() {
        defaults.set(["/Users/dev/blog": "dragon"], forKey: MascotPreferences.defaultsKey)

        let preferences = MascotPreferences(defaults: defaults)
        XCTAssertEqual(preferences.character(forProject: "/Users/dev/blog"), .default)
    }

    func testNilOrEmptyProjectKeyIsNotStored() {
        let preferences = MascotPreferences(defaults: defaults)
        preferences.setCharacter(.rocket, forProject: nil)
        preferences.setCharacter(.rocket, forProject: "")

        XCTAssertTrue(preferences.characterByProject.isEmpty)
    }
}

/// Renderer'ın her karakter×state kombinasyonunda çıktı ürettiğini doğrular;
/// görsel doğrulama için kareler geçici dizine PNG olarak yazılır.
final class MascotSnapshotTests: XCTestCase {
    func testEveryCharacterStateComboRenders() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mascot-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        for character in MascotCharacter.allCases {
            for state in SessionState.allCases {
                let data = MascotSnapshot.png(character: character, state: state)
                XCTAssertNotNil(data, "\(character.rawValue)/\(state.rawValue) çizilemedi")
                try data?.write(
                    to: outputDir.appendingPathComponent("\(character.rawValue)-\(state.rawValue).png")
                )
            }
        }
    }
}
