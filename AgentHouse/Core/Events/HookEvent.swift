import Foundation

/// Claude Code hook'undan gelen tek bir event payload'ı; tüm alanlar savunmacı olarak optional'dır
/// ve bilinmeyen/yanlış tipli alanlar decode'u düşürmez.
struct HookEvent: Equatable {
    /// Tanınan hook event adları; ham `hook_event_name` string'inden türetilir.
    enum Name: String {
        case sessionStart = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case notification = "Notification"
        case stop = "Stop"
        case sessionEnd = "SessionEnd"
    }

    let hookEventName: String?
    let sessionId: String?
    let transcriptPath: String?
    let cwd: String?
    let toolName: String?
    let message: String?
    let prompt: String?
    let source: String?
    let reason: String?

    /// Tanınan event adı; bilinmeyen adlar için nil (event yok sayılır, crash yok).
    var name: Name? {
        hookEventName.flatMap(Name.init(rawValue:))
    }
}

extension HookEvent: Decodable {
    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case toolName = "tool_name"
        case message
        case prompt
        case source
        case reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hookEventName = Self.string(container, .hookEventName)
        sessionId = Self.string(container, .sessionId)
        transcriptPath = Self.string(container, .transcriptPath)
        cwd = Self.string(container, .cwd)
        toolName = Self.string(container, .toolName)
        message = Self.string(container, .message)
        prompt = Self.string(container, .prompt)
        source = Self.string(container, .source)
        reason = Self.string(container, .reason)
    }

    // Alan eksikse VEYA beklenmedik tipteyse nil: hook şeması değişse bile event akmaya devam eder.
    private static func string(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> String? {
        (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
    }
}
