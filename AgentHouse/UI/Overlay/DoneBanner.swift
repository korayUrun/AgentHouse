import SwiftUI

/// Eşiği aşan bir iş bitince kartın altından spring animasyonla sarkan ve birkaç saniye
/// sonra toplanan bildirim. Tıklayınca terminale gitme Faz 8'de TerminalFocuser'a bağlanacak.
struct DoneBanner: View {
    let completion: LongTaskCompletion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(completion.projectName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("İş bitti · \(Self.format(duration: completion.duration))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 124)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.green.opacity(0.4), lineWidth: 1)
        }
    }

    /// "2 dk 5 sn" biçiminde kısa süre metni; formatter pahalı, bir kez kurulur.
    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private static func format(duration: TimeInterval) -> String {
        durationFormatter.string(from: duration) ?? ""
    }
}

#Preview {
    DoneBanner(completion: LongTaskCompletion(
        sessionId: "s1",
        projectName: "AgentHouse",
        duration: 125
    ))
    .padding()
}
