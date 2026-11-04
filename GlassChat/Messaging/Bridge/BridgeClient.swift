import Foundation
import Network

/// NDJSON client over a Unix domain socket to glasschat-bridge.
actor BridgeClient {
    private let socketPath: String
    private var connection: NWConnection?
    private var buffer = Data()
    private var pending: [String: CheckedContinuation<BridgeEnvelope, Error>] = [:]
    private var eventHandlers: [UUID: @Sendable (BridgeEnvelope) -> Void] = [:]
    private var isStarted = false

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() async throws {
        if isStarted { return }
        let endpoint = NWEndpoint.unix(path: socketPath)
        let parameters = NWParameters()
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let lock = NSLock()
            var resumed = false
            func resumeOnce(_ result: Result<Void, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce(.success(()))
                case .failed(let error):
                    resumeOnce(.failure(error))
                case .cancelled:
                    resumeOnce(.failure(CancellationError()))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }

        isStarted = true
        receiveLoop()
    }

    func stop() {
        connection?.cancel()
        connection = nil
        isStarted = false
        for (_, continuation) in pending {
            continuation.resume(throwing: CancellationError())
        }
        pending.removeAll()
    }

    func onEvent(_ handler: @escaping @Sendable (BridgeEnvelope) -> Void) -> UUID {
        let id = UUID()
        eventHandlers[id] = handler
        return id
    }

    func removeEventHandler(_ id: UUID) {
        eventHandlers.removeValue(forKey: id)
    }

    func request(method: BridgeMethod, payload: [String: BridgeJSON] = [:]) async throws -> BridgeEnvelope {
        try await start()
        let id = UUID().uuidString
        var body: [String: Any] = [
            "id": id,
            "type": "request",
            "method": method.rawValue
        ]
        if !payload.isEmpty {
            body["payload"] = payload.mapValues(\.jsonObject)
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        var line = data
        line.append(0x0A)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            connection?.send(content: line, completion: .contentProcessed { [weak self] error in
                if let error {
                    Task {
                        await self?.failPending(id: id, error: error)
                    }
                }
            })
        }
    }

    private func failPending(id: String, error: Error) {
        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(throwing: error)
        }
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] content, _, isComplete, error in
            Task {
                await self?.handleReceive(content: content, isComplete: isComplete, error: error)
            }
        }
    }

    private func handleReceive(content: Data?, isComplete: Bool, error: Error?) async {
        if let error {
            for (_, continuation) in pending {
                continuation.resume(throwing: error)
            }
            pending.removeAll()
            return
        }
        if let content {
            buffer.append(content)
            while let range = buffer.range(of: Data([0x0A])) {
                let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                await handleLine(line)
            }
        }
        if isComplete {
            return
        }
        receiveLoop()
    }

    private func handleLine(_ line: Data) async {
        guard !line.isEmpty else { return }
        do {
            let envelope = try JSONDecoder().decode(BridgeEnvelope.self, from: line)
            if envelope.type == "response" {
                if let continuation = pending.removeValue(forKey: envelope.id) {
                    if envelope.ok == false {
                        continuation.resume(throwing: MessagingError.bridgeUnavailable(envelope.error ?? "Bridge request failed"))
                    } else {
                        continuation.resume(returning: envelope)
                    }
                }
            } else if envelope.type == "event" {
                for handler in eventHandlers.values {
                    handler(envelope)
                }
            }
        } catch {
            // Ignore malformed lines.
        }
    }
}

private extension BridgeJSON {
    var jsonObject: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .object(let value): return value.mapValues(\.jsonObject)
        case .array(let value): return value.map(\.jsonObject)
        case .null: return NSNull()
        }
    }
}
