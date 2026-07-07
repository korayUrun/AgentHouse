import Combine
import XCTest
@testable import AgentHouse

/// UsageReader'ın gerçek dosyalarla artımlı okuma, canlı limit izi ve
/// eksik dosya davranışlarını doğrular.
final class UsageReaderTests: XCTestCase {
    private var tempDirectory: URL!
    private var cancellables: Set<AnyCancellable> = []

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeTranscript(named name: String = "session.jsonl", lines: [String]) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        let content = lines.map { $0 + "\n" }.joined()
        try content.data(using: .utf8)!.write(to: url)
        return url
    }

    private func usageLine(model: String = "claude-opus-4-8", input: Int, output: Int) -> String {
        """
        {"type":"assistant","message":{"model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output)}}}
        """
    }

    private let limitLine = """
    {"isApiErrorMessage":true,"message":{"content":[{"type":"text","text":"Claude usage limit reached."}]}}
    """

    // MARK: - Catch-up okuma

    func testExistingContentIsAccumulatedOnTrack() throws {
        let url = try makeTranscript(lines: [
            usageLine(input: 10, output: 100),
            "{\"type\":\"user\"}",
            usageLine(input: 5, output: 50),
        ])

        let reader = UsageReader()
        let received = expectation(description: "usage yayınlandı")
        var lastUpdate: SessionUsageUpdate?
        reader.usageUpdated
            .sink { update in
                lastUpdate = update
                received.fulfill()
            }
            .store(in: &cancellables)

        reader.track(sessionId: "s1", transcriptPath: url.path)
        wait(for: [received], timeout: 2)

        XCTAssertEqual(lastUpdate?.sessionId, "s1")
        XCTAssertEqual(lastUpdate?.usage.inputTokens, 15)
        XCTAssertEqual(lastUpdate?.usage.outputTokens, 150)
    }

    // MARK: - Artımlı okuma

    func testAppendedLinesAreReadIncrementally() throws {
        let url = try makeTranscript(lines: [usageLine(input: 1, output: 1)])

        let reader = UsageReader()
        var updates: [SessionUsage] = []
        let sawAppend = expectation(description: "eklenen satır okundu")
        reader.usageUpdated
            .sink { update in
                updates.append(update.usage)
                if update.usage.outputTokens == 1 + 99 { sawAppend.fulfill() }
            }
            .store(in: &cancellables)

        reader.track(sessionId: "s1", transcriptPath: url.path)

        // Catch-up bittikten sonra dosyaya yeni satır ekle (Claude Code'un yaptığı gibi).
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            let handle = try! FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write((self.usageLine(input: 2, output: 99) + "\n").data(using: .utf8)!)
            try! handle.close()
        }

        wait(for: [sawAppend], timeout: 3)
        XCTAssertEqual(updates.last?.inputTokens, 3)
        XCTAssertEqual(updates.last?.outputTokens, 100)
    }

    func testPartialLineIsBufferedUntilNewlineArrives() throws {
        let url = try makeTranscript(lines: [])

        let reader = UsageReader()
        var totals: [Int] = []
        let sawComplete = expectation(description: "tam satır işlendi")
        reader.usageUpdated
            .sink { update in
                totals.append(update.usage.outputTokens)
                sawComplete.fulfill()
            }
            .store(in: &cancellables)

        reader.track(sessionId: "s1", transcriptPath: url.path)

        // Satırı ikiye bölerek yaz: newline gelmeden usage YAYINLANMAMALI.
        let full = usageLine(input: 1, output: 42) + "\n"
        let cut = full.index(full.startIndex, offsetBy: full.count / 2)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            let handle = try! FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write(String(full[..<cut]).data(using: .utf8)!)
            try! handle.close()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
            let handle = try! FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write(String(full[cut...]).data(using: .utf8)!)
            try! handle.close()
        }

        wait(for: [sawComplete], timeout: 3)
        XCTAssertEqual(totals, [42])
    }

    // MARK: - Limit izi

    func testLimitTraceInHistoryDoesNotSignal() throws {
        // Geçmişte kalmış (catch-up'ta okunan) eski limit hatası state'i bozmamalı.
        let url = try makeTranscript(lines: [limitLine, usageLine(input: 1, output: 1)])

        let reader = UsageReader()
        var limitSignals: [String] = []
        reader.limitDetected
            .sink { limitSignals.append($0) }
            .store(in: &cancellables)

        let usageSeen = expectation(description: "catch-up bitti")
        reader.usageUpdated
            .sink { _ in usageSeen.fulfill() }
            .store(in: &cancellables)

        reader.track(sessionId: "s1", transcriptPath: url.path)
        wait(for: [usageSeen], timeout: 2)

        XCTAssertTrue(limitSignals.isEmpty)
    }

    func testLiveLimitTraceSignalsSession() throws {
        let url = try makeTranscript(lines: [usageLine(input: 1, output: 1)])

        let reader = UsageReader()
        let signaled = expectation(description: "canlı limit sinyali")
        reader.limitDetected
            .sink { sessionId in
                XCTAssertEqual(sessionId, "s1")
                signaled.fulfill()
            }
            .store(in: &cancellables)

        reader.track(sessionId: "s1", transcriptPath: url.path)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            let handle = try! FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write((self.limitLine + "\n").data(using: .utf8)!)
            try! handle.close()
        }

        wait(for: [signaled], timeout: 3)
    }

    // MARK: - Kenar durumlar

    func testMissingTranscriptFileIsIgnoredWithoutCrash() {
        let reader = UsageReader()
        reader.track(sessionId: "s1", transcriptPath: tempDirectory.appendingPathComponent("yok.jsonl").path)

        // Yayın olmamalı; kısa bir süre bekleyip crash olmadığını doğrula.
        let quiet = expectation(description: "sessiz")
        quiet.isInverted = true
        reader.usageUpdated.sink { _ in quiet.fulfill() }.store(in: &cancellables)
        wait(for: [quiet], timeout: 0.5)
    }

    func testLargeTranscriptIsProcessedInChunks() throws {
        // ~2 MB'lık dosya: chunk'lı catch-up doğru toplam üretmeli (bellek iddiası
        // manuel ölçümde; burada doğruluk ve tamamlanma test edilir).
        let lineCount = 10_000
        let lines = (0..<lineCount).map { _ in usageLine(input: 3, output: 7) }
        let url = try makeTranscript(lines: lines)

        let reader = UsageReader()
        let done = expectation(description: "büyük dosya okundu")
        var last: SessionUsage?
        reader.usageUpdated
            .sink { update in
                last = update.usage
                if update.usage.inputTokens == lineCount * 3 { done.fulfill() }
            }
            .store(in: &cancellables)

        reader.track(sessionId: "s1", transcriptPath: url.path)
        wait(for: [done], timeout: 10)

        XCTAssertEqual(last?.inputTokens, lineCount * 3)
        XCTAssertEqual(last?.outputTokens, lineCount * 7)
    }

    func testSessionEndStopsTracking() throws {
        let url = try makeTranscript(lines: [usageLine(input: 1, output: 1)])

        let reader = UsageReader()
        let caughtUp = expectation(description: "catch-up")
        reader.usageUpdated.sink { _ in caughtUp.fulfill() }.store(in: &cancellables)
        reader.track(sessionId: "s1", transcriptPath: url.path)
        wait(for: [caughtUp], timeout: 2)

        reader.stopTracking(sessionId: "s1")

        // Durdurulduktan sonra eklenen satır yayın ÜRETMEMELİ.
        let quiet = expectation(description: "sessiz")
        quiet.isInverted = true
        reader.usageUpdated.sink { _ in quiet.fulfill() }.store(in: &cancellables)

        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write((usageLine(input: 9, output: 9) + "\n").data(using: .utf8)!)
        try handle.close()

        wait(for: [quiet], timeout: 0.7)
    }
}
