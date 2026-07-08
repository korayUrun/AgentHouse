import XCTest
@testable import AgentHouse

/// Proje → küme atama deposunu doğrular (ADR-017).
final class ClusterStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ClusterStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testUnassignedProjectLivesInMainCluster() {
        let store = ClusterStore(defaults: defaults)

        XCTAssertEqual(store.clusterId(forProject: "/Users/dev/blog"), ClusterStore.mainClusterId)
        XCTAssertEqual(store.clusterId(forProject: nil), ClusterStore.mainClusterId)
    }

    func testDetachAssignsNewClusterAndPersists() {
        let store = ClusterStore(defaults: defaults)
        let clusterId = store.detach(project: "/Users/dev/blog")

        XCTAssertNotNil(clusterId)
        XCTAssertNotEqual(clusterId, ClusterStore.mainClusterId)
        XCTAssertEqual(store.clusterId(forProject: "/Users/dev/blog"), clusterId)

        // Yeni instance aynı atamayı görür (kalıcılık) — projenin sonraki oturumu
        // da kendi panelinde açılır.
        let reloaded = ClusterStore(defaults: defaults)
        XCTAssertEqual(reloaded.clusterId(forProject: "/Users/dev/blog"), clusterId)
    }

    func testDetachWithoutProjectKeyIsRefused() {
        let store = ClusterStore(defaults: defaults)

        XCTAssertNil(store.detach(project: nil))
        XCTAssertNil(store.detach(project: ""))
        XCTAssertTrue(store.clusterByProject.isEmpty)
    }

    func testReturnToMainRemovesAssignment() {
        let store = ClusterStore(defaults: defaults)
        store.detach(project: "/Users/dev/blog")
        store.returnToMain(project: "/Users/dev/blog")

        XCTAssertEqual(store.clusterId(forProject: "/Users/dev/blog"), ClusterStore.mainClusterId)
        XCTAssertTrue(store.clusterByProject.isEmpty)
    }

    func testMergeMovesAllProjectsOfCluster() {
        let store = ClusterStore(defaults: defaults)
        let source = store.detach(project: "/Users/dev/a")!
        store.detach(project: "/Users/dev/b")
        let target = store.clusterId(forProject: "/Users/dev/b")

        store.merge(cluster: source, into: target)
        XCTAssertEqual(store.clusterId(forProject: "/Users/dev/a"), target)
    }

    func testMergeIntoMainClearsAssignments() {
        let store = ClusterStore(defaults: defaults)
        let source = store.detach(project: "/Users/dev/a")!

        store.merge(cluster: source, into: ClusterStore.mainClusterId)
        XCTAssertEqual(store.clusterId(forProject: "/Users/dev/a"), ClusterStore.mainClusterId)
        XCTAssertTrue(store.clusterByProject.isEmpty)
    }

    func testMergeWithOrderPlacesCardsAtDropPosition() {
        let store = ClusterStore(defaults: defaults)
        let source = store.detach(project: "/Users/dev/c")!

        // c kartı, ana kümede a ile b'nin ARASINA bırakıldı.
        store.merge(
            cluster: source,
            into: ClusterStore.mainClusterId,
            order: ["/Users/dev/a", "/Users/dev/c", "/Users/dev/b"]
        )

        let sessions = ["a", "b", "c"].map { name in
            Session(
                id: name,
                projectName: name,
                cwd: "/Users/dev/\(name)",
                state: .idle,
                lastActivity: Date(),
                isStale: false,
                startedAt: Date()
            )
        }
        let ordered = store.orderedSessions(sessions, inCluster: ClusterStore.mainClusterId)
        XCTAssertEqual(ordered.map(\.id), ["a", "c", "b"])

        // Sıra kalıcıdır.
        let reloaded = ClusterStore(defaults: defaults)
        XCTAssertEqual(
            reloaded.orderedSessions(sessions, inCluster: ClusterStore.mainClusterId).map(\.id),
            ["a", "c", "b"]
        )
    }

    func testOrderedSessionsWithoutStoredOrderKeepsCreationOrder() {
        let store = ClusterStore(defaults: defaults)
        let sessions = ["x", "y"].map { name in
            Session(
                id: name,
                projectName: name,
                cwd: "/Users/dev/\(name)",
                state: .idle,
                lastActivity: Date(),
                isStale: false,
                startedAt: Date()
            )
        }
        XCTAssertEqual(
            store.orderedSessions(sessions, inCluster: ClusterStore.mainClusterId).map(\.id),
            ["x", "y"]
        )
    }

    func testGatherAllReturnsEverythingToMain() {
        let store = ClusterStore(defaults: defaults)
        store.detach(project: "/Users/dev/a")
        store.detach(project: "/Users/dev/b")

        store.gatherAll()
        XCTAssertTrue(store.clusterByProject.isEmpty)
        XCTAssertEqual(ClusterStore(defaults: defaults).clusterByProject, [:])
    }
}
