import Foundation
import SwiftUI

/// Serializes TTS API calls so audio chunks are enqueued in order
actor TTSChunkQueue {
    private let elevenlabs: ElevenLabsService
    private let player: AudioPlayer

    init(elevenlabs: ElevenLabsService, player: AudioPlayer) {
        self.elevenlabs = elevenlabs
        self.player = player
    }

    /// Each call waits for the previous one to finish before starting
    func enqueue(text: String) async {
        do {
            let audioData = try await elevenlabs.synthesize(text: text)
            await MainActor.run {
                player.enqueue(data: audioData)
            }
        } catch {
            print("TTS chunk failed: \(error)")
        }
    }
}

enum ChatState {
    case idle
    case listening    // VAD mode: waiting for speech
    case recording    // actively recording speech
    case transcribing
    case thinking
    case streaming    // receiving streaming text
    case speaking

    var displayText: String {
        switch self {
        case .idle: return ""
        case .listening: return "Listening"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .thinking: return "Thinking"
        case .streaming: return "Generating"
        case .speaking: return "Speaking"
        }
    }

    var displayIcon: String {
        switch self {
        case .idle: return ""
        case .listening: return "ear.fill"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .thinking: return "brain"
        case .streaming: return "text.cursor"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    var stateColor: Color {
        switch self {
        case .idle: return .secondary
        case .listening: return .green
        case .recording: return .red
        case .transcribing: return .purple
        case .thinking: return .blue
        case .streaming: return .cyan
        case .speaking: return .orange
        }
    }
}

@Observable
@MainActor
class ChatViewModel: NSObject, AudioRecorderDelegate {
    var messages: [ChatMessage] = [] {
        didSet { saveMessages() }
    }
    var state: ChatState = .idle
    var audioLevel: Float = 0.0
    var speakingLevel: Float = 0.0
    var liveTranscript: String = ""

    private let recorder = AudioRecorder()
    private let player = AudioPlayer()
    private var pendingSettings: AppSettings?
    private var levelTimer: DispatchSourceTimer?

    private var currentProfileID: UUID?
    private var lastSpokenText: String = ""

    private var realtimeSTT: RealtimeTranscriptionService?
    private var realtimeAPIKey: String = ""
    private var pendingPushToTalkSettings: AppSettings?
    private var awaitingPushToTalkTranscript = false
    private var isHandsFreeCaptureActive = false

    override init() {
        super.init()
        recorder.vadDelegate = self
    }

    // MARK: - Profile switching

    func switchToProfile(_ profileID: UUID?) {
        guard profileID != currentProfileID else { return }
        currentProfileID = profileID
        loadMessages()
    }

    // MARK: - Persistence (per-profile)

    private var messagesKey: String {
        if let id = currentProfileID {
            return "chatMessages_\(id.uuidString)"
        }
        return "chatMessages"
    }

    private func saveMessages() {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: messagesKey)
        }
    }

    private func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: messagesKey),
              let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            messages = []
            return
        }
        messages = saved
    }

    // MARK: - Realtime STT lifecycle

    func prepareRealtime(settings: AppSettings) {
        Task { @MainActor in
            do {
                try await ensureRealtimeService(settings: settings, requireAPIKey: false)
            } catch {
                print("Realtime STT warmup failed: \(error)")
            }
        }
    }

    private func ensureRealtimeService(settings: AppSettings, requireAPIKey: Bool = true) async throws {
        let apiKey = settings.openaiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiKey.isEmpty else {
            realtimeSTT?.disconnect()
            realtimeAPIKey = ""
            if requireAPIKey {
                throw ClawTalkError.sttFailed
            }
            return
        }

        if realtimeSTT == nil {
            let service = RealtimeTranscriptionService()
            bindRealtimeCallbacks(service)
            realtimeSTT = service
        }

        guard let realtimeSTT else {
            throw ClawTalkError.sttFailed
        }

        if realtimeAPIKey != apiKey {
            realtimeSTT.disconnect()
        }

        if !realtimeSTT.isConnected {
            try await realtimeSTT.connect(apiKey: apiKey)
        }

        realtimeAPIKey = apiKey
    }

    private func bindRealtimeCallbacks(_ service: RealtimeTranscriptionService) {
        service.onTranscriptDelta = { [weak self] delta in
            Task { @MainActor in
                self?.handleTranscriptDelta(delta)
            }
        }

        service.onTranscriptCompleted = { [weak self] transcript in
            Task { @MainActor in
                self?.handleTranscriptCompleted(transcript)
            }
        }

        service.onSpeechStarted = { [weak self] in
            Task { @MainActor in
                self?.handleSpeechStarted()
            }
        }

        service.onSpeechStopped = { [weak self] in
            Task { @MainActor in
                self?.handleSpeechStopped()
            }
        }

        service.onError = { [weak self] error in
            Task { @MainActor in
                self?.handleRealtimeError(error)
            }
        }
    }

    private func startStreamingAudio(handsFree: Bool) {
        recorder.onAudioChunk = { [weak self] chunk in
            Task { @MainActor in
                self?.realtimeSTT?.appendAudio(chunk)
            }
        }

        liveTranscript = ""

        if handsFree {
            isHandsFreeCaptureActive = true
            recorder.startListening()
            state = .listening
        } else {
            isHandsFreeCaptureActive = false
            recorder.startRecording()
            state = .recording
        }

        startLevelTimer()
    }

    private func pauseHandsFreeCaptureForProcessing() {
        guard isHandsFreeCaptureActive else { return }
        isHandsFreeCaptureActive = false
        stopLevelTimer()
        recorder.stopListening()
    }

    private func handleTranscriptDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        liveTranscript += delta
    }

    private func handleSpeechStarted() {
        guard isHandsFreeCaptureActive else { return }
        state = .recording
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    private func handleSpeechStopped() {
        guard isHandsFreeCaptureActive else { return }
        if state == .recording {
            state = .transcribing
        }
    }

    private func handleTranscriptCompleted(_ transcript: String) {
        let completed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTranscript = completed.isEmpty ? fallback : completed
        liveTranscript = ""

        if awaitingPushToTalkTranscript {
            awaitingPushToTalkTranscript = false

            guard let settings = pendingPushToTalkSettings else {
                state = .idle
                return
            }

            Task { @MainActor in
                await processTranscript(finalTranscript, settings: settings)
            }
            return
        }

        guard isHandsFreeCaptureActive,
              let settings = pendingSettings else {
            return
        }

        pauseHandsFreeCaptureForProcessing()

        Task { @MainActor in
            await processTranscript(finalTranscript, settings: settings, resumeListening: true)
        }
    }

    private func handleRealtimeError(_ error: Error) {
        print("Realtime STT error: \(error)")

        let isTranscriptionState = state == .listening || state == .recording || state == .transcribing || awaitingPushToTalkTranscript

        if isTranscriptionState {
            awaitingPushToTalkTranscript = false
            pendingPushToTalkSettings = nil
            pendingSettings = nil
            isHandsFreeCaptureActive = false
            liveTranscript = ""
            recorder.stopRecording()
            recorder.stopListening()
            stopLevelTimer()
            state = .idle

            let errorMessage = ChatMessage(role: .assistant, content: "⚠️ \(error.localizedDescription)\nTap to retry", timestamp: Date(), isError: true)
            messages.append(errorMessage)
        }
    }

    // MARK: - Push-to-talk

    func startRecording(settings: AppSettings) {
        pendingPushToTalkSettings = settings
        pendingSettings = nil
        awaitingPushToTalkTranscript = false

        Task { @MainActor in
            do {
                try await ensureRealtimeService(settings: settings)
                startStreamingAudio(handsFree: false)
            } catch {
                let errorMessage = ChatMessage(role: .assistant, content: "⚠️ \(error.localizedDescription)\nTap to retry", timestamp: Date(), isError: true)
                messages.append(errorMessage)
                state = .idle
            }
        }
    }

    func stopAndProcess(settings: AppSettings) {
        guard state == .recording else { return }
        pendingPushToTalkSettings = settings

        stopLevelTimer()
        recorder.stopRecording()

        guard let realtimeSTT, realtimeSTT.isConnected else {
            state = .idle
            let errorMessage = ChatMessage(role: .assistant, content: "⚠️ Speech-to-text failed\nTap to retry", timestamp: Date(), isError: true)
            messages.append(errorMessage)
            return
        }

        awaitingPushToTalkTranscript = true
        state = .transcribing
        realtimeSTT.commitAudio()
    }

    // MARK: - Hands-free (server VAD)

    func startHandsFree(settings: AppSettings) {
        pendingSettings = settings
        pendingPushToTalkSettings = nil
        awaitingPushToTalkTranscript = false

        Task { @MainActor in
            do {
                try await ensureRealtimeService(settings: settings)
                startStreamingAudio(handsFree: true)
            } catch {
                let errorMessage = ChatMessage(role: .assistant, content: "⚠️ \(error.localizedDescription)\nTap to retry", timestamp: Date(), isError: true)
                messages.append(errorMessage)
                state = .idle
            }
        }
    }

    func stopHandsFree() {
        pendingSettings = nil
        awaitingPushToTalkTranscript = false
        isHandsFreeCaptureActive = false
        liveTranscript = ""
        stopLevelTimer()
        recorder.stopListening()
        state = .idle
    }

    /// Stop everything - cancel any active operation
    func stopAll() {
        player.stop()
        stopSpeakingTimer()

        pendingSettings = nil
        pendingPushToTalkSettings = nil
        awaitingPushToTalkTranscript = false
        isHandsFreeCaptureActive = false
        liveTranscript = ""

        stopLevelTimer()
        recorder.stopRecording()
        recorder.stopListening()
        state = .idle
    }

    /// Force-end current recording and process immediately (hands-free send button)
    func forceEndRecording(settings: AppSettings) {
        guard isHandsFreeCaptureActive else {
            startHandsFree(settings: settings)
            return
        }

        guard let realtimeSTT, realtimeSTT.isConnected else {
            stopHandsFree()
            let errorMessage = ChatMessage(role: .assistant, content: "⚠️ Speech-to-text failed\nTap to retry", timestamp: Date(), isError: true)
            messages.append(errorMessage)
            return
        }

        state = .transcribing
        realtimeSTT.commitAudio()
    }

    // MARK: - AudioRecorderDelegate (kept for fallback compatibility)

    nonisolated func audioRecorderDidDetectSpeechStart() {}

    nonisolated func audioRecorderDidDetectSpeechEnd(audioURL: URL) {}

    // MARK: - Transcript processing pipeline

    private func processTranscript(_ rawTranscript: String, settings: AppSettings, resumeListening: Bool = false) async {
        let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !transcript.isEmpty else {
            if resumeListening {
                startHandsFree(settings: settings)
            } else {
                state = .idle
            }
            return
        }

        if WhisperService.isHallucination(transcript) {
            if resumeListening {
                startHandsFree(settings: settings)
            } else {
                state = .idle
            }
            return
        }

        // Echo detection: discard if transcript matches recent TTS output
        if !lastSpokenText.isEmpty && isEcho(transcript: transcript, spokenText: lastSpokenText) {
            print("Echo detected, discarding: \(transcript)")
            if resumeListening {
                startHandsFree(settings: settings)
            } else {
                state = .idle
            }
            return
        }

        // Add user message
        let userMessage = ChatMessage(role: .user, content: transcript, timestamp: Date())
        messages.append(userMessage)

        // Step 2: LLM (streaming)
        state = .thinking
        let openclaw = OpenClawService(baseURL: settings.openclawURL, token: settings.gatewayToken)

        // Create placeholder assistant message for streaming
        let assistantMessage = ChatMessage(role: .assistant, content: "", timestamp: Date())
        messages.append(assistantMessage)
        let messageIndex = messages.count - 1

        // Setup chunked TTS - speak while still streaming
        let elevenlabs = ElevenLabsService(apiKey: settings.elevenlabsAPIKey, voiceID: settings.selectedVoiceID)
        var sentenceBuffer = ""
        var spokenUpTo = 0
        var firstToken = true
        var isFirstChunk = true
        let chunkBreaks: [Character] = [".", "!", "?", "\n", ",", ";", ":", "-"]
        let maxChunkLength = 120  // force chunk if no punctuation

        // Serial actor to ensure TTS chunks are enqueued in order
        let ttsQueue = TTSChunkQueue(elevenlabs: elevenlabs, player: player)

        // Prepare audio session once before playback starts
        player.prepareAudioSession()

        // Start audio queue
        player.startQueue { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.stopSpeakingTimer()
                if resumeListening && settings.isHandsFree {
                    // Brief ignore period to avoid picking up TTS echo
                    self.recorder.setIgnorePeriod(1.5)
                    self.startHandsFree(settings: settings)
                } else {
                    self.state = .idle
                }
            }
        }

        // Helper to send a chunk to TTS (serialized)
        func speakChunk(_ text: String) {
            Task {
                await ttsQueue.enqueue(text: text)
            }
        }

        do {
            let fullResponse = try await openclaw.sendMessageStreaming(transcript) { [weak self] token in
                Task { @MainActor in
                    guard let self else { return }
                    if firstToken {
                        self.state = .streaming
                        firstToken = false
                    }
                    // Append token to the streaming message
                    self.messages[messageIndex].content += token
                    sentenceBuffer += token

                    // Determine if we should chunk now
                    let trimmed = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    let minLength = isFirstChunk ? 5 : 8  // lower threshold for first chunk (faster start)
                    let hasBreak = trimmed.last.map { chunkBreaks.contains($0) } ?? false
                    let shouldChunk = (hasBreak && trimmed.count >= minLength) || trimmed.count >= maxChunkLength

                    if shouldChunk && !trimmed.isEmpty {
                        sentenceBuffer = ""
                        spokenUpTo = self.messages[messageIndex].content.count
                        isFirstChunk = false

                        if self.state != .speaking {
                            self.state = .speaking
                            self.startSpeakingTimer()
                        }

                        speakChunk(trimmed)
                    }
                }
            }

            // Ensure final content is complete
            messages[messageIndex].content = fullResponse

            // Filter out silent/empty responses
            let trimmedResponse = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedResponse.isEmpty || trimmedResponse == "NO_REPLY" || trimmedResponse == "HEARTBEAT_OK" {
                messages.remove(at: messageIndex)
                player.stop()
                if resumeListening && settings.isHandsFree {
                    startHandsFree(settings: settings)
                } else {
                    state = .idle
                }
                return
            }

            lastSpokenText = fullResponse.lowercased()

            // Speak any remaining text that wasn't chunked (serialized via queue)
            let remaining = String(fullResponse.dropFirst(spokenUpTo)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                if state != .speaking {
                    state = .speaking
                    startSpeakingTimer()
                }
                await ttsQueue.enqueue(text: remaining)
            }

            // Signal no more chunks
            player.finishQueue()

        } catch {
            print("Error: \(error)")
            let errorMessage = ChatMessage(role: .assistant, content: "⚠️ \(error.localizedDescription)\nTap to retry", timestamp: Date(), isError: true)
            messages.append(errorMessage)

            if resumeListening && settings.isHandsFree {
                startHandsFree(settings: settings)
            } else {
                state = .idle
            }
        }
    }

    // MARK: - Skip TTS

    func skipSpeaking(settings: AppSettings) {
        player.stop()
        stopSpeakingTimer()
        if settings.isHandsFree {
            startHandsFree(settings: settings)
        } else {
            state = .idle
        }
    }

    func updateAudioLevel() {
        audioLevel = recorder.audioLevel
    }

    private func startLevelTimer() {
        stopLevelTimer()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: 0.05)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.audioLevel = self.recorder.audioLevel
                self.player.updateMeters()
                self.speakingLevel = self.player.audioLevel
            }
        }
        timer.resume()
        levelTimer = timer
    }

    func startSpeakingTimer() {
        stopLevelTimer()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: 0.05)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.player.updateMeters()
                self.speakingLevel = self.player.audioLevel
            }
        }
        timer.resume()
        levelTimer = timer
    }

    func stopSpeakingTimer() {
        levelTimer?.cancel()
        levelTimer = nil
        speakingLevel = 0
    }

    private func stopLevelTimer() {
        levelTimer?.cancel()
        levelTimer = nil
        audioLevel = 0
        speakingLevel = 0
    }

    // MARK: - Echo detection

    private func isEcho(transcript: String, spokenText: String) -> Bool {
        let t = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let s = spokenText

        // Check if transcript words appear in spoken text
        let tWords = Set(t.split(separator: " ").map(String.init))
        let sWords = Set(s.split(separator: " ").map(String.init))

        guard !tWords.isEmpty else { return false }

        let overlap = tWords.intersection(sWords).count
        let ratio = Double(overlap) / Double(tWords.count)

        // If >40% of transcript words match spoken text, it's echo
        return ratio > 0.4
    }

    func retryLastMessage(settings: AppSettings) {
        // Remove error message, find last user message, reprocess
        guard let errorIndex = messages.lastIndex(where: { $0.isError }) else { return }
        messages.remove(at: errorIndex)

        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else { return }

        // Re-send via text (not audio)
        let transcript = lastUserMessage.content
        state = .thinking

        let openclaw = OpenClawService(baseURL: settings.openclawURL, token: settings.gatewayToken)
        let elevenlabs = ElevenLabsService(apiKey: settings.elevenlabsAPIKey, voiceID: settings.selectedVoiceID)

        Task { @MainActor in
            do {
                let assistantMessage = ChatMessage(role: .assistant, content: "", timestamp: Date())
                messages.append(assistantMessage)
                let messageIndex = messages.count - 1

                var sentenceBuffer = ""
                var spokenUpTo = 0
                var firstToken = true
                var isFirstChunk = true
                let chunkBreaks: [Character] = [".", "!", "?", "\n", ",", ";", ":", "-"]
                let maxChunkLength = 120

                let ttsQueue = TTSChunkQueue(elevenlabs: elevenlabs, player: player)
                player.prepareAudioSession()
                player.startQueue { [weak self] in
                    Task { @MainActor in
                        self?.stopSpeakingTimer()
                        self?.state = .idle
                    }
                }

                func speakChunk(_ text: String) {
                    Task { await ttsQueue.enqueue(text: text) }
                }

                let fullResponse = try await openclaw.sendMessageStreaming(transcript) { [weak self] token in
                    Task { @MainActor in
                        guard let self else { return }
                        if firstToken {
                            self.state = .streaming
                            firstToken = false
                        }
                        self.messages[messageIndex].content += token
                        sentenceBuffer += token

                        let trimmed = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                        let minLength = isFirstChunk ? 5 : 8
                        let hasBreak = trimmed.last.map { chunkBreaks.contains($0) } ?? false
                        let shouldChunk = (hasBreak && trimmed.count >= minLength) || trimmed.count >= maxChunkLength

                        if shouldChunk && !trimmed.isEmpty {
                            sentenceBuffer = ""
                            spokenUpTo = self.messages[messageIndex].content.count
                            isFirstChunk = false
                            if self.state != .speaking {
                                self.state = .speaking
                                self.startSpeakingTimer()
                            }
                            speakChunk(trimmed)
                        }
                    }
                }

                messages[messageIndex].content = fullResponse

                let trimmedResponse = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedResponse.isEmpty || trimmedResponse == "NO_REPLY" || trimmedResponse == "HEARTBEAT_OK" {
                    messages.remove(at: messageIndex)
                    player.stop()
                    state = .idle
                    return
                }

                lastSpokenText = fullResponse.lowercased()
                let remaining = String(fullResponse.dropFirst(spokenUpTo)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !remaining.isEmpty {
                    if state != .speaking {
                        state = .speaking
                        startSpeakingTimer()
                    }
                    await ttsQueue.enqueue(text: remaining)
                }
                player.finishQueue()

            } catch {
                let errorMsg = ChatMessage(role: .assistant, content: "⚠️ \(error.localizedDescription)\nTap to retry", timestamp: Date(), isError: true)
                messages.append(errorMsg)
                state = .idle
            }
        }
    }

    func deleteMessage(id: UUID) {
        messages.removeAll { $0.id == id }
    }

    func clearChat() {
        messages.removeAll()
        UserDefaults.standard.removeObject(forKey: messagesKey)
    }
}
