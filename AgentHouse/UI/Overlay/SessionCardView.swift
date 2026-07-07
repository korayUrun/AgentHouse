import SwiftUI

/// Tek bir oturumu overlay panelde gösteren kart: maskot alanı, proje adı,
/// state etiketi ve son aktivite göstergesi.
struct SessionCardView: View {
    let session: Session

    var body: some View {
        VStack(spacing: 8) {
            // attention puls halkası dahil tüm animasyon maskotun kendi içinde
            // (CPU bütçesi için SwiftUI animasyonu yerine CG çizimi).
            ActiveMascot(state: session.state)
                .frame(width: 48, height: 48)

            Text(session.projectName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)

            stateBadge

            // Text(_, style: .relative) her ekran karesinde SwiftUI render'ı
            // uyandırdığı için seyrek periyodik tik + formatter kullanılır
            // (her tik kart layout'unu yeniden çalıştırıyor; 10 sn yeterli).
            TimelineView(.periodic(from: .now, by: 10)) { context in
                Text(Self.relativeFormatter.localizedString(
                    for: session.lastActivity,
                    relativeTo: context.date
                ))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(width: 124)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    session.state.tint.opacity(session.state == .attention ? 0.6 : 0.25),
                    lineWidth: 1
                )
        }
        .opacity(session.isStale ? 0.45 : 1)
    }

    /// "42 saniye önce" biçiminde kısa göreli zaman; formatter pahalı, bir kez kurulur.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var stateBadge: some View {
        Text(session.state.displayLabel)
            .font(.caption2.weight(.medium))
            .foregroundStyle(session.state.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(session.state.tint.opacity(0.15)))
    }
}

/// SessionState'in panel üzerindeki görsel dili. UI katmanına aittir; Core bu
/// eşlemeyi bilmez.
extension SessionState {
    /// Kart üzerindeki kısa Türkçe etiket.
    var displayLabel: String {
        switch self {
        case .idle: return "Boşta"
        case .working: return "Çalışıyor"
        case .attention: return "Dikkat!"
        case .done: return "Bitti"
        case .limit: return "Limitte"
        }
    }

    /// State renk dili: idle nötr, working mavi/mor, attention amber,
    /// done yeşil, limit gri/uyku.
    var tint: Color {
        switch self {
        case .idle: return .gray
        case .working: return .indigo
        case .attention: return .orange
        case .done: return .green
        case .limit: return .gray
        }
    }
}

#Preview("State'ler") {
    HStack(alignment: .top, spacing: 10) {
        ForEach(SessionState.allCases, id: \.self) { state in
            SessionCardView(session: Session(
                id: state.rawValue,
                projectName: "AgentHouse",
                cwd: "/Users/dev/AgentHouse",
                state: state,
                lastActivity: Date().addingTimeInterval(-42),
                isStale: false,
                startedAt: Date()
            ))
        }
    }
    .padding()
}
