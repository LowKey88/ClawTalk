import Foundation

final class RealtimeTranscriptionService {
    var onTranscriptDelta: ((String) -> Void)?
    var onTranscriptCompleted: ((String) -> Void)?
    var onSpeechStarted: (() -> Void)?
    var onSpeechStopped: (() -> Void)?
    var onError: ((Error) -> Void)?

    private(set) var isConnected = false

    private let endpoint = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var isDisconnecting = false
    private var currentTranscript = ""
    private let eventStateQueue = DispatchQueue(label: "com.clawtalk.realtime.event-state")
    private var seenEventTypes = Set<String>()
    private var eventWaiters: [String: [UUID: CheckedContinuation<Void, Error>]] = [:]

    func connect(apiKey: String) async throws {
        if isConnected { return }
        if webSocketTask != nil || session != nil || receiveTask != nil {
            disconnect()
        }
        resetEventState()

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)

        self.session = session
        self.webSocketTask = task
        self.isDisconnecting = false
        task.resume()
        startReceiveLoop()

        do {
            try await waitForEvent("session.created", timeout: 10)
            try await sendNow(SessionUpdateEvent.defaultTranscription)
            try await waitForEvent("session.updated", timeout: 10)
            isConnected = true
        } catch {
            disconnect()
            throw error
        }
    }

    func appendAudio(_ pcm16Data: Data) {
        guard isConnected else { return }
        let event = InputAudioAppendEvent(audio: pcm16Data.base64EncodedString())
        send(event)
    }

    func commitAudio() {
        guard isConnected else { return }
        send(InputAudioCommitEvent())
    }

    func disconnect() {
        isDisconnecting = true
        isConnected = false
        currentTranscript = ""
        failAllEventWaiters(with: RealtimeTranscriptionError.notConnected)
        resetEventState()

        receiveTask?.cancel()
        receiveTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - Private

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard let task = self.webSocketTask else { return }

                do {
                    let message = try await task.receive()
                    self.handleMessage(message)
                } catch {
                    if Task.isCancelled || self.isDisconnecting {
                        return
                    }
                    self.failAllEventWaiters(with: error)
                    self.disconnect()
                    self.emitError(error)
                    return
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data

        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let raw):
            data = raw
        @unknown default:
            return
        }

        guard let event = try? decoder.decode(RealtimeEvent.self, from: data) else {
            return
        }
        notifyEventWaiters(for: event.type)

        switch event.type {
        case "conversation.item.input_audio_transcription.delta":
            guard let delta = event.delta, !delta.isEmpty else { return }
            currentTranscript += delta
            onTranscriptDelta?(delta)

        case "conversation.item.input_audio_transcription.completed":
            let transcript = (event.transcript ?? currentTranscript)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            currentTranscript = ""
            onTranscriptCompleted?(transcript)

        case "input_audio_buffer.speech_started":
            onSpeechStarted?()

        case "input_audio_buffer.speech_stopped":
            onSpeechStopped?()

        case "error":
            let message = event.error?.message ?? "Realtime transcription error"
            let serverError = RealtimeTranscriptionError.server(message)
            failAllEventWaiters(with: serverError)
            emitError(serverError)

        default:
            break
        }
    }

    private func waitForEvent(_ eventType: String, timeout: TimeInterval) async throws {
        let waiterID = UUID()
        let timeoutNanoseconds = UInt64(timeout * 1_000_000_000)
        var timeoutTask: Task<Void, Never>?

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if registerEventWaiter(continuation, for: eventType, id: waiterID) {
                    continuation.resume(returning: ())
                    return
                }

                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    guard let self else { return }
                    if let waiter = self.removeEventWaiter(for: eventType, id: waiterID) {
                        waiter.resume(throwing: RealtimeTranscriptionError.timeout)
                    }
                }
            }
            timeoutTask?.cancel()
        } catch {
            timeoutTask?.cancel()
            throw error
        }
    }

    private func registerEventWaiter(
        _ continuation: CheckedContinuation<Void, Error>,
        for eventType: String,
        id: UUID
    ) -> Bool {
        eventStateQueue.sync {
            if seenEventTypes.contains(eventType) {
                return true
            }

            var waiters = eventWaiters[eventType] ?? [:]
            waiters[id] = continuation
            eventWaiters[eventType] = waiters
            return false
        }
    }

    private func removeEventWaiter(for eventType: String, id: UUID) -> CheckedContinuation<Void, Error>? {
        eventStateQueue.sync {
            guard var waiters = eventWaiters[eventType] else { return nil }
            let waiter = waiters.removeValue(forKey: id)
            if waiters.isEmpty {
                eventWaiters.removeValue(forKey: eventType)
            } else {
                eventWaiters[eventType] = waiters
            }
            return waiter
        }
    }

    private func notifyEventWaiters(for eventType: String) {
        let waiters: [CheckedContinuation<Void, Error>] = eventStateQueue.sync { () -> [CheckedContinuation<Void, Error>] in
            seenEventTypes.insert(eventType)
            let eventWaiters = self.eventWaiters.removeValue(forKey: eventType)?.values ?? []
            return Array(eventWaiters)
        }

        for waiter in waiters {
            waiter.resume(returning: ())
        }
    }

    private func failAllEventWaiters(with error: Error) {
        let waiters: [CheckedContinuation<Void, Error>] = eventStateQueue.sync { () -> [CheckedContinuation<Void, Error>] in
            let waiters = eventWaiters.values.flatMap(\.values)
            eventWaiters.removeAll()
            return Array(waiters)
        }

        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }

    private func resetEventState() {
        eventStateQueue.sync {
            seenEventTypes.removeAll()
            eventWaiters.removeAll()
        }
    }

    private func send<T: Encodable>(_ event: T) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sendNow(event)
            } catch {
                if !self.isDisconnecting {
                    self.disconnect()
                    self.emitError(error)
                }
            }
        }
    }

    private func sendNow<T: Encodable>(_ event: T) async throws {
        guard let task = webSocketTask else {
            throw RealtimeTranscriptionError.notConnected
        }

        let data = try encoder.encode(event)
        let json = String(decoding: data, as: UTF8.self)
        try await task.send(.string(json))
    }

    private func emitError(_ error: Error) {
        onError?(error)
    }
}

private enum RealtimeTranscriptionError: LocalizedError {
    case notConnected
    case timeout
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Realtime transcription is not connected"
        case .timeout:
            return "Timed out waiting for realtime transcription session setup"
        case .server(let message):
            return message
        }
    }
}

private struct RealtimeEvent: Decodable {
    let type: String
    let delta: String?
    let transcript: String?
    let error: RealtimeEventError?
}

private struct RealtimeEventError: Decodable {
    let message: String?
}

private struct SessionUpdateEvent: Encodable {
    let type = "session.update"
    let session: SessionPayload

    static let defaultTranscription = SessionUpdateEvent(
        session: SessionPayload(
            type: "transcription",
            audio: AudioPayload(
                input: InputPayload(
                    format: AudioFormatPayload(type: "audio/pcm", rate: 24000),
                    noiseReduction: NoiseReductionPayload(type: "near_field"),
                    transcription: TranscriptionPayload(model: "gpt-4o-mini-transcribe", language: "en"),
                    turnDetection: TurnDetectionPayload(
                        type: "server_vad",
                        threshold: 0.5,
                        prefixPaddingMs: 300,
                        silenceDurationMs: 600
                    )
                )
            )
        )
    )
}

private struct SessionPayload: Encodable {
    let type: String
    let audio: AudioPayload
}

private struct AudioPayload: Encodable {
    let input: InputPayload
}

private struct InputPayload: Encodable {
    let format: AudioFormatPayload
    let noiseReduction: NoiseReductionPayload
    let transcription: TranscriptionPayload
    let turnDetection: TurnDetectionPayload

    enum CodingKeys: String, CodingKey {
        case format
        case noiseReduction = "noise_reduction"
        case transcription
        case turnDetection = "turn_detection"
    }
}

private struct AudioFormatPayload: Encodable {
    let type: String
    let rate: Int
}

private struct NoiseReductionPayload: Encodable {
    let type: String
}

private struct TranscriptionPayload: Encodable {
    let model: String
    let language: String
}

private struct TurnDetectionPayload: Encodable {
    let type: String
    let threshold: Double
    let prefixPaddingMs: Int
    let silenceDurationMs: Int

    enum CodingKeys: String, CodingKey {
        case type
        case threshold
        case prefixPaddingMs = "prefix_padding_ms"
        case silenceDurationMs = "silence_duration_ms"
    }
}

private struct InputAudioAppendEvent: Encodable {
    let type = "input_audio_buffer.append"
    let audio: String
}

private struct InputAudioCommitEvent: Encodable {
    let type = "input_audio_buffer.commit"
}
