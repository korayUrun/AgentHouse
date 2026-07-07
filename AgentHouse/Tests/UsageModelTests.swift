import XCTest
@testable import AgentHouse

/// TranscriptLineParser'ın savunmacı satır sınıflandırmasını, SessionUsage birikimini
/// ve ModelPricing tablosunu doğrular.
final class UsageModelTests: XCTestCase {
    // MARK: - Satır sınıflandırma

    func testAssistantLineWithUsageIsParsed() {
        let line = """
        {"type":"assistant","message":{"model":"claude-opus-4-8","usage":{"input_tokens":4,"output_tokens":252,"cache_creation_input_tokens":120,"cache_read_input_tokens":14000}}}
        """
        guard case .usage(let delta) = TranscriptLineParser.classify(line: line) else {
            return XCTFail("usage beklenirdi")
        }
        XCTAssertEqual(delta.model, "claude-opus-4-8")
        XCTAssertEqual(delta.inputTokens, 4)
        XCTAssertEqual(delta.outputTokens, 252)
        XCTAssertEqual(delta.cacheCreationTokens, 120)
        XCTAssertEqual(delta.cacheReadTokens, 14000)
    }

    func testMissingUsageFieldsDefaultToZero() {
        let line = """
        {"message":{"model":"claude-opus-4-8","usage":{"output_tokens":10}}}
        """
        guard case .usage(let delta) = TranscriptLineParser.classify(line: line) else {
            return XCTFail("usage beklenirdi")
        }
        XCTAssertEqual(delta.inputTokens, 0)
        XCTAssertEqual(delta.outputTokens, 10)
    }

    func testLinesWithoutUsageAreOther() {
        XCTAssertEqual(TranscriptLineParser.classify(line: "{\"type\":\"user\"}"), .other)
        XCTAssertEqual(TranscriptLineParser.classify(line: ""), .other)
        XCTAssertEqual(TranscriptLineParser.classify(line: "bozuk { json"), .other)
        // usage alanı var ama tüm sayaçlar sıfır: gösterilecek bir şey yok.
        XCTAssertEqual(
            TranscriptLineParser.classify(line: "{\"message\":{\"usage\":{}}}"),
            .other
        )
    }

    func testWrongTypedUsageValuesDoNotCrash() {
        let line = """
        {"message":{"model":42,"usage":{"input_tokens":"çok","output_tokens":5}}}
        """
        guard case .usage(let delta) = TranscriptLineParser.classify(line: line) else {
            return XCTFail("usage beklenirdi")
        }
        XCTAssertNil(delta.model)
        XCTAssertEqual(delta.inputTokens, 0)
        XCTAssertEqual(delta.outputTokens, 5)
    }

    // MARK: - Limit izi

    func testApiErrorLineWithLimitMessageIsLimitTrace() {
        let line = """
        {"isApiErrorMessage":true,"message":{"content":[{"type":"text","text":"Claude usage limit reached."}]}}
        """
        XCTAssertEqual(TranscriptLineParser.classify(line: line), .limitTrace)
    }

    func testConversationMentioningRateLimitIsNotLimitTrace() {
        // Sohbet içeriğinde "rate limit" geçmesi sinyal ÜRETMEMELİ (isApiErrorMessage yok).
        let line = """
        {"type":"assistant","message":{"usage":{"output_tokens":3},"content":[{"type":"text","text":"rate limit hakkında konuşalım"}]}}
        """
        guard case .usage = TranscriptLineParser.classify(line: line) else {
            return XCTFail("usage beklenirdi, limitTrace değil")
        }
    }

    func testApiErrorWithoutLimitContentIsNotLimitTrace() {
        let line = """
        {"isApiErrorMessage":true,"message":{"content":[{"type":"text","text":"Internal server error"}]}}
        """
        XCTAssertEqual(TranscriptLineParser.classify(line: line), .other)
    }

    // MARK: - Birikim ve maliyet

    func testSessionUsageAccumulatesAcrossDeltas() {
        var usage = SessionUsage()
        usage.add(UsageDelta(model: "claude-opus-4-8", inputTokens: 100, outputTokens: 200))
        usage.add(UsageDelta(model: "claude-opus-4-8", inputTokens: 50, cacheReadTokens: 1_000))

        XCTAssertEqual(usage.inputTokens, 150)
        XCTAssertEqual(usage.outputTokens, 200)
        XCTAssertEqual(usage.cacheReadTokens, 1_000)
        XCTAssertEqual(usage.totalTokens, 1_350)
    }

    func testEstimatedCostUsesModelPricing() {
        var usage = SessionUsage()
        // Opus: input $5/M, output $25/M → 1M input + 1M output = $30.
        usage.add(UsageDelta(model: "claude-opus-4-8", inputTokens: 1_000_000, outputTokens: 1_000_000))
        XCTAssertEqual(usage.estimatedCostUSD, 30, accuracy: 0.001)
    }

    func testCacheTokensArePricedAtCacheRates() {
        var usage = SessionUsage()
        // Sonnet input $3/M → cache write 1.25x = $3.75/M, cache read 0.1x = $0.30/M.
        usage.add(UsageDelta(model: "claude-sonnet-5", cacheCreationTokens: 1_000_000, cacheReadTokens: 1_000_000))
        XCTAssertEqual(usage.estimatedCostUSD, 3.75 + 0.30, accuracy: 0.001)
    }

    func testUnknownModelCountsTokensButNotCost() {
        var usage = SessionUsage()
        usage.add(UsageDelta(model: "tanınmayan-model", inputTokens: 1_000_000))
        XCTAssertEqual(usage.totalTokens, 1_000_000)
        XCTAssertEqual(usage.estimatedCostUSD, 0)
    }

    func testPricingTableMatchesModelFamilies() {
        XCTAssertEqual(ModelPricing.pricing(forModel: "claude-fable-5")?.inputPerMTok, 10)
        XCTAssertEqual(ModelPricing.pricing(forModel: "claude-opus-4-8")?.inputPerMTok, 5)
        XCTAssertEqual(ModelPricing.pricing(forModel: "claude-sonnet-4-6")?.outputPerMTok, 15)
        XCTAssertEqual(ModelPricing.pricing(forModel: "claude-haiku-4-5-20251001")?.inputPerMTok, 1)
        XCTAssertNil(ModelPricing.pricing(forModel: "gpt-x"))
        XCTAssertNil(ModelPricing.pricing(forModel: nil))
    }
}
