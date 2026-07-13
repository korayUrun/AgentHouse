import Combine
import Foundation
import Network
import os

/// Claude Code hook'larından gelen `POST /event` isteklerini dinleyen, YALNIZCA 127.0.0.1'e
/// bağlanan minimal HTTP sunucusu. Gelen gövdeyi `HookEvent`'e decode edip Combine ile yayınlar.
final class EventServer {
    /// Varsayılan dinleme portu; UserDefaults'taki `eventServerPort` anahtarıyla geçersiz kılınabilir.
    static let defaultPort: UInt16 = 48756

    /// Port ayarının saklandığı UserDefaults anahtarı.
    static let portDefaultsKey = "eventServerPort"

    /// Sunucu kurulum hataları.
    enum ServerError: LocalizedError {
        case invalidPort(UInt16)

        var errorDescription: String? {
            switch self {
            case .invalidPort(let port):
                return String(localized: "Invalid port: \(String(port))")
            }
        }
    }

    /// Dinleyicinin gözlemlenebilir yaşam döngüsü durumu. NWListener port çakışmasını
    /// start() anında değil asenkron `.failed` state'iyle bildirir; UI bu yayına abone olur.
    enum ListenerStatus: Equatable {
        case idle
        case ready
        case failed(reason: String)
    }

    /// Çözümlenen hook eventlerinin yayını; ana kuyrukta teslim edilir.
    var events: AnyPublisher<HookEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    /// Dinleyici durum yayını; sunucu kuyruğundan yayınlanır (abone `receive(on: .main)` kullanmalı).
    var status: AnyPublisher<ListenerStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    /// Anlık dinleyici durumu (uyanma sonrası sağlık kontrolü için).
    var currentStatus: ListenerStatus {
        statusSubject.value
    }

    /// Sunucunun bağlanacağı port.
    let port: UInt16

    private let subject = PassthroughSubject<HookEvent, Never>()
    private let statusSubject = CurrentValueSubject<ListenerStatus, Never>(.idle)
    private let queue = DispatchQueue(label: "com.agenthouse.app.eventserver")
    private let logger = Logger(subsystem: "com.agenthouse.app", category: "EventServer")
    private let decoder = JSONDecoder()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var connectionTimeouts: [ObjectIdentifier: DispatchWorkItem] = [:]

    /// Gövdesi tamamlanmayan bir bağlantının iptal edileceği süre (kaynak birikmesin).
    private static let connectionTimeout: TimeInterval = 10

    init(port: UInt16 = EventServer.defaultPort) {
        self.port = port
    }

    /// UserDefaults'taki portu okur; yoksa veya geçersizse varsayılanı döndürür.
    static func configuredPort(defaults: UserDefaults = .standard) -> UInt16 {
        let stored = defaults.integer(forKey: portDefaultsKey)
        guard (1024...65535).contains(stored) else { return defaultPort }
        return UInt16(stored)
    }

    /// Dinlemeye başlar. Zaten çalışıyorsa hiçbir şey yapmaz.
    func start() throws {
        guard listener == nil else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.invalidPort(port)
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Sadece loopback: dış ağdan gelen bağlantılar en baştan imkansız.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)

        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.logger.info("EventServer 127.0.0.1:\(self.port, privacy: .public) dinlemede.")
                self.statusSubject.send(.ready)
            case .failed(let error):
                self.logger.error("EventServer başarısız (port çakışması olabilir): \(error.localizedDescription, privacy: .public)")
                self.statusSubject.send(.failed(reason: error.localizedDescription))
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    /// Dinlemeyi ve tüm açık bağlantıları sonlandırır.
    func stop() {
        listener?.cancel()
        listener = nil
        statusSubject.send(.idle)
        queue.async { [weak self] in
            guard let self else { return }
            self.connections.values.forEach { $0.cancel() }
            self.connections.removeAll()
            self.connectionTimeouts.values.forEach { $0.cancel() }
            self.connectionTimeouts.removeAll()
        }
    }

    // MARK: - Bağlantı yönetimi (hepsi `queue` üzerinde)

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        // Gövdesi hiç tamamlanmayan bağlantı kuyrukta süresiz birikmesin diye watchdog;
        // bağlantı biterken (aşağıdaki .cancelled/.failed) temizlenir.
        let timeout = DispatchWorkItem { [weak connection] in connection?.cancel() }
        connectionTimeouts[id] = timeout
        queue.asyncAfter(deadline: .now() + Self.connectionTimeout, execute: timeout)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.connections.removeValue(forKey: id)
                self?.connectionTimeouts.removeValue(forKey: id)?.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(connection, buffered: Data())
    }

    private func receive(_ connection: NWConnection, buffered: Data, sentContinue: Bool = false) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffered
            if let data {
                buffer.append(data)
            }
            if let error {
                self.logger.debug("Bağlantı hatası: \(error.localizedDescription, privacy: .public)")
                connection.cancel()
                return
            }

            switch Self.parseRequest(buffer) {
            case .needMoreData:
                if isComplete {
                    connection.cancel()
                } else {
                    // curl, gövde >1KB olduğunda otomatik `Expect: 100-continue` yollar.
                    // Interim `100 Continue` dönmezsek istemci ~1 sn bekler ve bu bekleme
                    // `--max-time 1` ile çakışıp isteği keser (event kaybı). Header'ları
                    // görür görmez interim yanıtı gönderip gövdeyi hemen aldırıyoruz —
                    // HTTP-doğru davranış, kurulu hook komutunu değiştirmeye gerek yok.
                    var didSendContinue = sentContinue
                    if !sentContinue, Self.expectsContinue(in: buffer) {
                        self.sendContinue(connection)
                        didSendContinue = true
                    }
                    self.receive(connection, buffered: buffer, sentContinue: didSendContinue)
                }
            case .rejected(let status, let reason):
                self.logger.info("İstek reddedildi: \(status, privacy: .public) \(reason, privacy: .public)")
                self.respond(connection, status: status, reason: reason)
            case .complete(let body):
                if self.publishEvent(from: body) {
                    self.respond(connection, status: 204, reason: "No Content")
                } else {
                    self.respond(connection, status: 400, reason: "Bad Request")
                }
            }
        }
    }

    /// Gövdeyi decode edip yayınlar; bozuk JSON loglanır ve yok sayılır (asla crash yok).
    private func publishEvent(from body: Data) -> Bool {
        do {
            let event = try decoder.decode(HookEvent.self, from: body)
            let name = event.hookEventName ?? "?"
            let session = event.sessionId.map { String($0.prefix(8)) } ?? "-"
            logger.info("Event alındı: \(name, privacy: .public) session=\(session, privacy: .public)")
            DispatchQueue.main.async { [subject] in
                subject.send(event)
            }
            return true
        } catch {
            logger.error("Bozuk event gövdesi yok sayıldı: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func respond(_ connection: NWConnection, status: Int, reason: String) {
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// `Expect: 100-continue` gören istemciye gövdeyi hemen yollaması için interim yanıt
    /// gönderir; bağlantıyı KAPATMAZ (1xx interim, ardından nihai yanıt gelir).
    private func sendContinue(_ connection: NWConnection) {
        connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { _ in })
    }

    // MARK: - HTTP ayrıştırma

    /// Minimal HTTP isteği ayrıştırma sonucu; testler için internal.
    enum ParseResult: Equatable {
        case needMoreData
        case complete(body: Data)
        case rejected(status: Int, reason: String)
    }

    private static let maxHeaderBytes = 16 * 1024
    private static let maxBodyBytes = 1024 * 1024

    /// Ham TCP verisinden `POST /event` isteğini ayrıştırır. Eksik veri → `.needMoreData`;
    /// yanlış metod/yol veya aşırı boyut → `.rejected`.
    static func parseRequest(_ raw: Data) -> ParseResult {
        guard let headerRange = raw.range(of: Data("\r\n\r\n".utf8)) else {
            if raw.count > maxHeaderBytes {
                return .rejected(status: 431, reason: "Request Header Fields Too Large")
            }
            return .needMoreData
        }
        guard let head = String(data: raw[raw.startIndex..<headerRange.lowerBound], encoding: .utf8) else {
            return .rejected(status: 400, reason: "Bad Request")
        }

        let lines = head.components(separatedBy: "\r\n")
        let requestLine = (lines.first ?? "").split(separator: " ")
        guard requestLine.count >= 2 else {
            return .rejected(status: 400, reason: "Bad Request")
        }
        guard requestLine[0] == "POST" else {
            return .rejected(status: 405, reason: "Method Not Allowed")
        }
        guard requestLine[1] == "/event" else {
            return .rejected(status: 404, reason: "Not Found")
        }

        var contentLength: Int?
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            if pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(pair[1].trimmingCharacters(in: .whitespaces))
            }
        }
        guard let contentLength, contentLength >= 0 else {
            return .rejected(status: 400, reason: "Bad Request")
        }
        guard contentLength <= maxBodyBytes else {
            return .rejected(status: 413, reason: "Payload Too Large")
        }

        let bodyStart = headerRange.upperBound
        guard raw.endIndex - bodyStart >= contentLength else {
            return .needMoreData
        }
        return .complete(body: raw.subdata(in: bodyStart..<(bodyStart + contentLength)))
    }

    /// Header bloğu tamamlanmışsa ve bir `Expect: 100-continue` başlığı taşıyorsa true
    /// (istemciye interim yanıt gönderilmeli). Header henüz tam gelmemişse false.
    static func expectsContinue(in raw: Data) -> Bool {
        guard
            let headerRange = raw.range(of: Data("\r\n\r\n".utf8)),
            let head = String(data: raw[raw.startIndex..<headerRange.lowerBound], encoding: .utf8)
        else { return false }
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard
                pair.count == 2,
                pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "expect"
            else { continue }
            return pair[1].lowercased().contains("100-continue")
        }
        return false
    }
}
