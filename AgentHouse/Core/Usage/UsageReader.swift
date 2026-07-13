import Combine
import Foundation
import os

/// Bir oturumun usage güncellemesi: hangi oturum, birikmiş toplam ne.
struct SessionUsageUpdate: Equatable {
    let sessionId: String
    let usage: SessionUsage
}

/// Aktif oturumların transcript JSONL dosyalarını SALT-OKUNUR ve artımlı izler:
/// dosya başına bir TranscriptTail açar, yeni satırları parse edip birikmiş usage'ı
/// ve canlı rate-limit izlerini Combine publisher'larıyla dışarı verir.
/// Tüm iç state tek seri kuyruğa hapsedilir; publisher'lar bu kuyruktan yayınlar
/// (aboneler `receive(on: .main)` kullanmalı).
final class UsageReader {
    /// Bir tail yeni satırlar işledikçe (toplu olarak) yayınlanır.
    let usageUpdated = PassthroughSubject<SessionUsageUpdate, Never>()
    /// CANLI eklenen bir satırda rate-limit izi görülünce oturum id'siyle yayınlanır.
    /// Geçmiş (catch-up) satırlardaki eski limit hataları sinyal üretmez.
    let limitDetected = PassthroughSubject<String, Never>()

    private let queue = DispatchQueue(label: "com.agenthouse.app.usagereader")
    private var tails: [String: TranscriptTail] = [:]
    private let logger = Logger(subsystem: "com.agenthouse.app", category: "UsageReader")

    deinit {
        // Teardown seri kuyrukta yapılır ki o an koşan readNewData ile fileHandle/source
        // üzerinde yarış olmasın (kuyruk sözleşmesi: tüm erişimler bu kuyrukta).
        queue.sync {
            tails.values.forEach { $0.stop() }
            tails.removeAll()
        }
    }

    /// Gelen hook eventine göre izlemeyi başlatır/durdurur. Herhangi bir thread'den çağrılabilir.
    func handle(_ event: HookEvent) {
        guard let sessionId = event.sessionId, !sessionId.isEmpty else { return }
        if event.name == .sessionEnd {
            stopTracking(sessionId: sessionId)
            return
        }
        guard let path = event.transcriptPath, !path.isEmpty else { return }
        track(sessionId: sessionId, transcriptPath: path)
    }

    /// Oturumun transcript dosyasını izlemeye başlar; zaten izleniyorsa hiçbir şey yapmaz.
    /// Dosya henüz yoksa sessizce vazgeçer — sonraki eventte yeniden denenir (best-effort).
    func track(sessionId: String, transcriptPath: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let url = URL(fileURLWithPath: transcriptPath)
            if let existing = self.tails[sessionId] {
                // Aynı dosya zaten izleniyorsa yeniden açma.
                guard existing.url != url else { return }
                // Resume/compact aynı session_id için YENİ bir transcript dosyasına
                // yazmaya başlamış olabilir; eskisini bırakıp yenisine geç (sayaç donmasın).
                existing.stop()
                self.tails.removeValue(forKey: sessionId)
            }
            guard let tail = TranscriptTail(
                url: url,
                queue: self.queue,
                onUsageChanged: { [weak self] usage in
                    self?.usageUpdated.send(SessionUsageUpdate(sessionId: sessionId, usage: usage))
                },
                onLiveLimitTrace: { [weak self] in
                    self?.limitDetected.send(sessionId)
                }
            ) else {
                self.logger.debug("Transcript açılamadı (henüz yok olabilir): \(transcriptPath, privacy: .public)")
                return
            }
            self.tails[sessionId] = tail
            tail.start()
        }
    }

    /// Oturumun tail'ini kapatır (SessionEnd).
    func stopTracking(sessionId: String) {
        queue.async { [weak self] in
            self?.tails.removeValue(forKey: sessionId)?.stop()
        }
    }
}

/// TEK transcript dosyasını izleyen sarmalayıcı: açılışta mevcut içeriği chunk chunk
/// okur (catch-up), sonra DispatchSource ile yalnızca YENİ eklenen baytları okur.
/// Dosyanın tamamı asla yeniden okunmaz; bellekte yalnızca tamamlanmamış son satır tutulur.
/// Bütün çağrılar sahibinin seri kuyruğunda yapılmalıdır.
private final class TranscriptTail {
    private static let chunkSize = 256 * 1024

    /// İzlenen dosyanın yolu; UsageReader aynı oturum için farklı yol gelince karşılaştırır.
    let url: URL
    private let queue: DispatchQueue
    private let onUsageChanged: (SessionUsage) -> Void
    private let onLiveLimitTrace: () -> Void

    private let fileHandle: FileHandle
    private var source: DispatchSourceFileSystemObject?
    private var pendingLine = Data()
    private var usage = SessionUsage()
    /// Catch-up sırasında true: eski satırlardaki limit izleri sinyal üretmez.
    private var isCatchingUp = true

    /// Dosya salt-okunur açılamazsa nil (kural 2: ~/.claude'a asla yazılmaz).
    init?(
        url: URL,
        queue: DispatchQueue,
        onUsageChanged: @escaping (SessionUsage) -> Void,
        onLiveLimitTrace: @escaping () -> Void
    ) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        self.url = url
        self.queue = queue
        self.fileHandle = handle
        self.onUsageChanged = onUsageChanged
        self.onLiveLimitTrace = onLiveLimitTrace
    }

    func start() {
        readNewData()
        isCatchingUp = false

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.readNewData()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        try? fileHandle.close()
    }

    /// Offset'ten dosya sonuna kadar olan yeni baytları chunk chunk okur, tam satırları
    /// işler; usage değiştiyse toplu tek güncelleme yayınlar.
    private func readNewData() {
        let usageBefore = usage
        while let chunk = try? fileHandle.read(upToCount: Self.chunkSize), !chunk.isEmpty {
            pendingLine.append(chunk)
            drainCompleteLines()
        }
        if usage != usageBefore {
            onUsageChanged(usage)
        }
    }

    private func drainCompleteLines() {
        while let newlineIndex = pendingLine.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = pendingLine[pendingLine.startIndex..<newlineIndex]
            let line = String(decoding: lineData, as: UTF8.self)
            pendingLine.removeSubrange(pendingLine.startIndex...newlineIndex)
            process(line: line)
        }
    }

    private func process(line: String) {
        switch TranscriptLineParser.classify(line: line) {
        case .usage(let delta):
            usage.add(delta)
        case .limitTrace:
            if !isCatchingUp {
                onLiveLimitTrace()
            }
        case .other:
            break
        }
    }
}
