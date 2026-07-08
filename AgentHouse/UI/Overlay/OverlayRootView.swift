import SwiftUI

/// Overlay panelinin SwiftUI kök görünümü: aktif oturum kartlarını yatay dizer
/// ve içeriğin ideal boyutunu panele bildirir (panel içeriğe göre boyutlanır).
struct OverlayRootView: View {
    @ObservedObject var sessionManager: SessionManager
    /// Kart → panel atamaları (ADR-017); bu panel yalnızca kendi kümesini gösterir.
    @ObservedObject var clusterStore: ClusterStore
    /// Bu panelin kümesi.
    var clusterId: String = ClusterStore.mainClusterId
    /// Panel görünürlüğü; gizliyken maskot animasyonları durdurulur.
    @ObservedObject var visibility = OverlayContentVisibility()
    /// Üzerine panel sürükleniyor sinyali; içerik hafif büyüyerek "birleşiriz" der.
    @ObservedObject var mergeHighlight = MergeHighlightModel()
    /// İçeriğin ideal boyutu değiştiğinde çağrılır; OverlayPanel bununla kendini
    /// yeniden boyutlandırır.
    var onContentSizeChange: (CGSize) -> Void = { _ in }
    /// Karta veya done banner'a tıklanınca çağrılır; kaynak terminali öne getirmek
    /// için AppDelegate TerminalFocuser'a bağlar.
    var onSessionActivate: (Session) -> Void = { _ in }

    /// Ekranda duran done banner'ları, session_id → tamamlama bilgisi.
    @State private var doneBanners: [String: LongTaskCompletion] = [:]

    /// Proje → maskot karakteri tercihleri (ADR-014); seçim kart menüsünden yapılır.
    @StateObject private var mascotPreferences = MascotPreferences()

    /// Banner'ın kendiliğinden toplanmadan önce ekranda kaldığı süre (sn).
    static let bannerDisplayDuration: TimeInterval = 5

    /// Bir satırdaki en fazla kart sayısı; fazlası alt satıra sarar ki panel
    /// çok oturumda ekran genişliğini aşmasın.
    static let maxCardsPerRow = 5

    /// Kart çerçevelerinin toplandığı koordinat uzayı adı (boşluk hesabı için).
    private static let contentSpace = "overlayContent"

    /// Kart id → içerik uzayındaki çerçevesi; hover'dan ekleme indeksi hesaplanır.
    @State private var cardFrames: [String: CGRect] = [:]

    /// Bu panelde görünen oturumlar: kümesi bu panele atananlar, kayıtlı kart sırasıyla.
    private var clusterSessions: [Session] {
        clusterStore.orderedSessions(
            sessionManager.sessions.filter {
                clusterStore.clusterId(forProject: $0.projectKey) == clusterId
            },
            inCluster: clusterId
        )
    }

    var body: some View {
        content
            .padding(10)
            .fixedSize()
            .coordinateSpace(name: Self.contentSpace)
            .scaleEffect(mergeHighlight.isTargeted ? 1.04 : 1)
            .animation(
                .spring(response: 0.28, dampingFraction: 0.55),
                value: mergeHighlight.isTargeted
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(ContentSizePreferenceKey.self, perform: onContentSizeChange)
            .onPreferenceChange(CardFramesPreferenceKey.self) { cardFrames = $0 }
            .animation(
                .spring(response: 0.35, dampingFraction: 0.8),
                value: clusterSessions.map(\.id)
            )
            .animation(
                .spring(response: 0.3, dampingFraction: 0.7),
                value: mergeHighlight.insertionIndex
            )
            .environment(\.mascotAnimationsPaused, !visibility.isVisible)
            .onReceive(sessionManager.longTaskCompleted) { showBanner($0) }
            .onReceive(mergeHighlight.$hoverPoint) { point in
                let index = point.map(insertionIndex(for:))
                if mergeHighlight.insertionIndex != index {
                    mergeHighlight.insertionIndex = index
                }
            }
    }

    /// Hover noktasına en yakın kart aralığının görüntü sırası indeksi:
    /// önce dikeyde en yakın satır, sonra o satırda imlecin solunda kalan kartlar sayılır.
    private func insertionIndex(for point: CGPoint) -> Int {
        var indexed: [(index: Int, frame: CGRect)] = []
        for (offset, session) in clusterSessions.enumerated() {
            if let frame = cardFrames[session.id] {
                indexed.append((offset, frame))
            }
        }
        guard var nearest = indexed.first else { return 0 }

        // İmlece dikeyde en yakın kartın satırı hedef satırdır.
        var nearestDistance = abs(nearest.frame.midY - point.y)
        for card in indexed {
            let distance = abs(card.frame.midY - point.y)
            if distance < nearestDistance {
                nearest = card
                nearestDistance = distance
            }
        }
        var row = indexed.filter { abs($0.frame.minY - nearest.frame.minY) < 1 }
        row.sort { $0.frame.minX < $1.frame.minX }

        for card in row where point.x < card.frame.midX {
            return card.index
        }
        return (row.last?.index ?? -1) + 1
    }

    @ViewBuilder
    private var content: some View {
        if clusterSessions.isEmpty {
            Text("Waiting for sessions…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else {
            let totalCount = clusterSessions.count
            let rows = sessionRows
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.element.first?.id) { rowIndex, row in
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(row.enumerated()), id: \.element.id) { columnIndex, session in
                            let displayIndex = rowIndex * Self.maxCardsPerRow + columnIndex
                            if shouldShowGap(at: displayIndex) {
                                insertionGap
                            }
                            cardCell(for: session)
                        }
                        if rowIndex == rows.count - 1, shouldShowGap(at: totalCount) {
                            insertionGap
                        }
                    }
                }
            }
        }
    }

    /// Tek kart hücresi: kart + varsa done banner'ı + çerçeve raporu.
    private func cardCell(for session: Session) -> some View {
        VStack(spacing: 6) {
            SessionCardView(
                session: session,
                mascotCharacter: mascotPreferences.character(forProject: session.projectKey),
                onSelectMascot: { character in
                    mascotPreferences.setCharacter(character, forProject: session.projectKey)
                },
                clusterAction: clusterAction(for: session)
            )
            .onTapGesture { onSessionActivate(session) }
            if let banner = doneBanners[session.id] {
                DoneBanner(completion: banner)
                    .onTapGesture { onSessionActivate(session) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CardFramesPreferenceKey.self,
                    value: [session.id: proxy.frame(in: .named(Self.contentSpace))]
                )
            }
        )
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    /// Sürüklenen panel bırakılırsa kartların gireceği yerde açılan boşluk.
    private var insertionGap: some View {
        Color.clear
            .frame(width: 36, height: 64)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    private func shouldShowGap(at displayIndex: Int) -> Bool {
        mergeHighlight.isTargeted && mergeHighlight.insertionIndex == displayIndex
    }

    /// Kartın sağ-tık küme eylemi: ana kümedeyse "kendi paneline ayır",
    /// ayrıksa "ana panele döndür". Anahtarsız oturum taşınamaz (nil).
    private func clusterAction(for session: Session) -> SessionCardView.ClusterAction? {
        guard let projectKey = session.projectKey else { return nil }
        if clusterId == ClusterStore.mainClusterId {
            return SessionCardView.ClusterAction(isDetach: true) {
                clusterStore.detach(project: projectKey)
            }
        }
        return SessionCardView.ClusterAction(isDetach: false) {
            clusterStore.returnToMain(project: projectKey)
        }
    }

    /// Oturumları satır başına en fazla `maxCardsPerRow` kart olacak şekilde böler.
    private var sessionRows: [[Session]] {
        let sessions = clusterSessions
        return stride(from: 0, to: sessions.count, by: Self.maxCardsPerRow).map {
            Array(sessions[$0..<min($0 + Self.maxCardsPerRow, sessions.count)])
        }
    }

    /// Banner'ı yay efektiyle sarkıtır ve süresi dolunca toplar. Aynı oturumdan yeni bir
    /// tamamlama gelirse süre baştan başlar (id karşılaştırması eski zamanlayıcıyı etkisiz kılar).
    private func showBanner(_ completion: LongTaskCompletion) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
            doneBanners[completion.sessionId] = completion
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bannerDisplayDuration) {
            guard doneBanners[completion.sessionId]?.id == completion.id else { return }
            _ = withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                doneBanners.removeValue(forKey: completion.sessionId)
            }
        }
    }
}

/// İçeriğin ideal boyutunu köke taşıyan preference anahtarı.
private struct ContentSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Kart çerçevelerini (içerik uzayında) köke taşıyan preference anahtarı.
private struct CardFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

#Preview("3 oturum") {
    OverlayRootView(
        sessionManager: .previewWithThreeSessions,
        clusterStore: ClusterStore(defaults: UserDefaults(suiteName: "preview")!)
    )
    .padding()
}

private extension SessionManager {
    /// Yalnızca SwiftUI preview'ları için üç örnek oturumlu manager.
    static var previewWithThreeSessions: SessionManager {
        let manager = SessionManager()
        for (id, cwd, event) in [
            ("a", "/Users/dev/AgentHouse", "UserPromptSubmit"),
            ("b", "/Users/dev/blog", "Notification"),
            ("c", "/Users/dev/side-project", "Stop"),
        ] {
            manager.handle(HookEvent(
                hookEventName: event,
                sessionId: id,
                transcriptPath: nil,
                cwd: cwd,
                toolName: nil,
                message: nil,
                prompt: nil,
                source: nil,
                reason: nil
            ))
        }
        return manager
    }
}
