import SwiftUI

/// Tek bir oturumu overlay panelde gösteren kart: maskot alanı, proje adı,
/// state etiketi ve son aktivite göstergesi. Maskot karakteri sağ-tık
/// menüsünden değiştirilir; seçim projeye kaydedilir (ADR-014).
struct SessionCardView: View {
    /// Sağ-tık menüsündeki küme eylemi (ADR-017): ayır ya da ana panele döndür.
    struct ClusterAction {
        /// true → "kendi paneline ayır"; false → "ana panele döndür".
        let isDetach: Bool
        let perform: () -> Void
    }

    let session: Session
    var mascotCharacter: MascotCharacter = .default
    var onSelectMascot: (MascotCharacter) -> Void = { _ in }
    var clusterAction: ClusterAction? = nil

    var body: some View {
        VStack(spacing: 8) {
            // attention puls halkası dahil tüm animasyon maskotun kendi içinde
            // (CPU bütçesi için SwiftUI animasyonu yerine CG çizimi).
            ActiveMascot(state: session.state, character: mascotCharacter)
                .frame(width: 64, height: 64)

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
        .contextMenu {
            Menu {
                ForEach(MascotCharacter.allCases) { character in
                    Button {
                        onSelectMascot(character)
                    } label: {
                        if character == mascotCharacter {
                            Label(character.displayName, systemImage: "checkmark")
                        } else {
                            Text(character.displayName)
                        }
                    }
                }
            } label: {
                Text("Mascot")
            }

            if let clusterAction {
                Button {
                    clusterAction.perform()
                } label: {
                    if clusterAction.isDetach {
                        Label("Detach into own panel", systemImage: "rectangle.on.rectangle")
                    } else {
                        Label("Return to main panel", systemImage: "rectangle.stack")
                    }
                }
            }
        }
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

/// Usage'ın kompakt metni. Kartta gösterilmez (ADR-013); Faz 8'deki menü bar
/// popover'ındaki oturum dökümü bu metni kullanacak. UI katmanına aittir.
extension SessionUsage {
    /// "42K tok · ~$1.80" biçiminde tek satır; maliyet yalnızca anlamlı büyüklükteyse eklenir.
    var compactDisplayText: String {
        var text = String(localized: "\(Self.compactTokenText(totalTokens)) tok")
        if estimatedCostUSD >= 0.01 {
            text += String(format: " · ~$%.2f", estimatedCostUSD)
        }
        return text
    }

    private static func compactTokenText(_ count: Int) -> String {
        switch count {
        case ..<1_000:
            return "\(count)"
        case ..<1_000_000:
            return String(format: "%.0fK", Double(count) / 1_000)
        default:
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }
}

/// SessionState'in panel üzerindeki görsel dili. UI katmanına aittir; Core bu
/// eşlemeyi bilmez.
extension SessionState {
    /// Kart üzerindeki kısa state etiketi (katalogdan yerelleşir).
    var displayLabel: String {
        switch self {
        case .idle: return String(localized: "Idle")
        case .working: return String(localized: "Working")
        case .attention: return String(localized: "Attention!")
        case .questioning: return String(localized: "Question")
        case .done: return String(localized: "Done")
        case .limit: return String(localized: "At limit")
        }
    }

    /// State renk dili: idle nötr, working mavi/mor, attention amber,
    /// questioning camgöbeği, done yeşil, limit gri/uyku.
    var tint: Color {
        switch self {
        case .idle: return .gray
        case .working: return .indigo
        case .attention: return .orange
        case .questioning: return .teal
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
