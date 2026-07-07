import Foundation

/// Transcript JSONL'inin tek bir satırından çıkarılan token kullanımı.
struct UsageDelta: Equatable {
    /// Satırdaki model adı (fiyatlandırma bu ada göre seçilir).
    var model: String?
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationTokens = 0
    var cacheReadTokens = 0

    /// Satırda hiç token yoksa true (satır usage taşımıyor demektir).
    var isEmpty: Bool {
        inputTokens == 0 && outputTokens == 0 && cacheCreationTokens == 0 && cacheReadTokens == 0
    }
}

/// Bir oturumun birikmiş token kullanımı ve tahmini maliyeti. Maliyet, her delta
/// eklendiği anda o satırın modeline göre hesaplanır (model oturum içinde değişebilir).
struct SessionUsage: Equatable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationTokens = 0
    var cacheReadTokens = 0
    /// Bilinen modeller için birikmiş tahmini maliyet (USD). Best-effort — "~" ile gösterilir.
    var estimatedCostUSD: Double = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    mutating func add(_ delta: UsageDelta) {
        inputTokens += delta.inputTokens
        outputTokens += delta.outputTokens
        cacheCreationTokens += delta.cacheCreationTokens
        cacheReadTokens += delta.cacheReadTokens
        if let pricing = ModelPricing.pricing(forModel: delta.model) {
            estimatedCostUSD += pricing.estimatedCost(for: delta)
        }
    }
}

/// Model adına göre sabit, yaklaşık fiyat tablosu (USD / milyon token).
/// Kaynak: Anthropic liste fiyatları; tabloyu bilerek kaba tutuyoruz — UI'da her zaman
/// "tahmini ~" olarak sunulur (ADR-010).
struct ModelPricing: Equatable {
    let inputPerMTok: Double
    let outputPerMTok: Double

    /// Cache yazma yaklaşık 1.25x, cache okuma yaklaşık 0.1x input fiyatıdır.
    var cacheWritePerMTok: Double { inputPerMTok * 1.25 }
    var cacheReadPerMTok: Double { inputPerMTok * 0.1 }

    /// Model adındaki aile ismine göre fiyat seçer; tanınmayan model için nil
    /// (o satırın maliyeti hesaba katılmaz, token sayısı yine de gösterilir).
    static func pricing(forModel model: String?) -> ModelPricing? {
        guard let model else { return nil }
        let lowered = model.lowercased()
        if lowered.contains("fable") || lowered.contains("mythos") {
            return ModelPricing(inputPerMTok: 10, outputPerMTok: 50)
        }
        if lowered.contains("opus") {
            return ModelPricing(inputPerMTok: 5, outputPerMTok: 25)
        }
        if lowered.contains("sonnet") {
            return ModelPricing(inputPerMTok: 3, outputPerMTok: 15)
        }
        if lowered.contains("haiku") {
            return ModelPricing(inputPerMTok: 1, outputPerMTok: 5)
        }
        return nil
    }

    func estimatedCost(for delta: UsageDelta) -> Double {
        Double(delta.inputTokens) / 1_000_000 * inputPerMTok
            + Double(delta.outputTokens) / 1_000_000 * outputPerMTok
            + Double(delta.cacheCreationTokens) / 1_000_000 * cacheWritePerMTok
            + Double(delta.cacheReadTokens) / 1_000_000 * cacheReadPerMTok
    }
}

/// Transcript JSONL satırının uygulamayı ilgilendiren sınıflandırması.
enum TranscriptLineEvent: Equatable {
    /// Satır token kullanımı taşıyor.
    case usage(UsageDelta)
    /// Satır bir API rate-limit hatası izi (limit sinyali).
    case limitTrace
    /// Satır bizi ilgilendirmiyor (veya bozuk — sessizce yok sayılır).
    case other
}

/// `~/.claude/projects/**/*.jsonl` satırlarını savunmacı biçimde sınıflandıran saf parser.
/// Bozuk/bilinmeyen satır asla hata üretmez, `.other` döner.
enum TranscriptLineParser {
    /// Verilen tek satırı sınıflandırır. Limit izi YALNIZCA `isApiErrorMessage`
    /// işaretli satırlarda aranır; sohbet içeriğinde geçen "rate limit" lafı
    /// yanlış tetikleme yapmasın diye (best-effort, emin değilsen state'i bozma).
    static func classify(line: String) -> TranscriptLineEvent {
        // Ucuz ön filtre: ilgisiz satırlar için JSON parse maliyetine girme.
        guard line.contains("\"usage\"") || line.contains("isApiErrorMessage") else {
            return .other
        }
        guard let data = line.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .other
        }

        if root["isApiErrorMessage"] as? Bool == true, LimitDetector.isLimitNotification(line) {
            return .limitTrace
        }

        guard let message = root["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else {
            return .other
        }
        let delta = UsageDelta(
            model: message["model"] as? String,
            inputTokens: intValue(usage["input_tokens"]),
            outputTokens: intValue(usage["output_tokens"]),
            cacheCreationTokens: intValue(usage["cache_creation_input_tokens"]),
            cacheReadTokens: intValue(usage["cache_read_input_tokens"])
        )
        return delta.isEmpty ? .other : .usage(delta)
    }

    // Alan eksikse veya beklenmedik tipteyse 0: şema değişse bile akış devam eder.
    private static func intValue(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }
}
