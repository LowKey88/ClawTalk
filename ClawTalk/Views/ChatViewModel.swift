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
        guard !Task.isCancelled else { return }
        
        do {
            let audioData = try await elevenlabs.synthesize(text: text)
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                player.enqueue(data: audioData)
            }
        } catch is CancellationError {
            return
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
    
    private let recorder = AudioRecorder()
    private let player = AudioPlayer()
    private var pendingSettings: AppSettings?
    private var levelTimer: DispatchSourceTimer?
    
    private var currentProfileID: UUID?
    private var lastSpokenText: String = ""
    private var currentPipelineTask: Task<Void, Never>?
    private var currentPipelineID: UUID?
    
    override init() {
        super.init()
        recorder.vadDelegate = self
    }
    
    // MARK: - Profile switching
    
    func switchToProfile(_ profileID: UUID?) {
        guard profileID != currentProfileID else { return }
        stopAll()
        currentProfileID = profileID
        lastSpokenText = ""
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
    
    // MARK: - Push-to-talk
    
    func startRecording() {
        recorder.startRecording()
        state = .recording
        startLevelTimer()
    }
    
    func stopAndProcess(settings: AppSettings) {
        stopLevelTimer()
        guard let audioURL = recorder.stopRecording() else {
            state = .idle
            return
        }
        
        startPipeline { [weak self] pipelineID in
            await self?.processAudio(audioURL: audioURL, settings: settings, pipelineID: pipelineID)
        }
    }
    
    // MARK: - Hands-free (VAD)
    
    func startHandsFree(settings: AppSettings) {
        pendingSettings = settings
        state = .listening
        recorder.startListening()
        startLevelTimer()
    }
    
    func stopHandsFree() {
        cancelCurrentPipeline()
        player.stop()
        stopSpeakingTimer()
        pendingSettings = nil
        stopLevelTimer()
        recorder.stopListening()
        state = .idle
    }
    
    /// Stop everything - cancel any active operation
    func stopAll() {
        cancelCurrentPipeline()
        player.stop()
        stopSpeakingTimer()
        stopLevelTimer()
        pendingSettings = nil
        recorder.stopListening()
        state = .idle
    }
    
    /// Force-end current recording and process immediately (hands-free send button)
    func forceEndRecording(settings: AppSettings) {
        stopLevelTimer()
        guard let audioURL = recorder.stopRecording() else {
            startHandsFree(settings: settings)
            return
        }
        
        startPipeline { [weak self] pipelineID in
            await self?.processAudio(audioURL: audioURL, settings: settings, resumeListening: true, pipelineID: pipelineID)
        }
    }
    
    // MARK: - AudioRecorderDelegate (VAD callbacks)
    
    nonisolated func audioRecorderDidDetectSpeechStart() {
        Task { @MainActor in
            state = .recording
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
    }
    
    nonisolated func audioRecorderDidDetectSpeechEnd(audioURL: URL) {
        Task { @MainActor in
            guard let settings = pendingSettings else {
                state = .idle
                return
            }
            startPipeline { [weak self] pipelineID in
                await self?.processAudio(audioURL: audioURL, settings: settings, resumeListening: true, pipelineID: pipelineID)
            }
        }
    }
    
    // MARK: - Audio processing pipeline
    
    private func startPipeline(_ operation: @escaping @MainActor (UUID) async -> Void) {
        cancelCurrentPipeline()
        
        let pipelineID = UUID()
        currentPipelineID = pipelineID
        currentPipelineTask = Task { [weak self] in
            await operation(pipelineID)
            await MainActor.run {
                guard let self, self.currentPipelineID == pipelineID else { return }
                self.currentPipelineTask = nil
            }
        }
    }
    
    private func cancelCurrentPipeline() {
        currentPipelineTask?.cancel()
        currentPipelineTask = nil
        currentPipelineID = nil
    }
    
    private func ensurePipelineIsActive(_ pipelineID: UUID) throws {
        if Task.isCancelled || currentPipelineID != pipelineID {
            throw CancellationError()
        }
    }

    private func assistantMessageIndex(for messageID: UUID, pipelineID: UUID) throws -> Int {
        try ensurePipelineIsActive(pipelineID)

        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }) else {
            throw CancellationError()
        }

        return messageIndex
    }
    
    private func finishPipeline(_ pipelineID: UUID, settings: AppSettings? = nil, resumeListening: Bool = false, applyIgnorePeriod: Bool = false) {
        guard currentPipelineID == pipelineID else { return }
        
        currentPipelineID = nil
        currentPipelineTask = nil
        stopSpeakingTimer()
        
        if resumeListening, let settings, settings.isHandsFree {
            if applyIgnorePeriod {
                recorder.setIgnorePeriod(1.5)
            }
            startHandsFree(settings: settings)
        } else {
            state = .idle
        }
    }
    
    private func processAudio(audioURL: URL, settings: AppSettings, resumeListening: Bool = false, pipelineID: UUID) async {
        // Step 1: STT
        state = .transcribing
        let whisper = WhisperService(apiKey: settings.openaiAPIKey)
        
        do {
            try ensurePipelineIsActive(pipelineID)
            let transcript = try await whisper.transcribe(audioURL: audioURL)
            try ensurePipelineIsActive(pipelineID)
            
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                finishPipeline(pipelineID, settings: settings, resumeListening: resumeListening)
                return
            }
            
            // Echo detection: discard if transcript matches recent TTS output
            if !lastSpokenText.isEmpty && isEcho(transcript: transcript, spokenText: lastSpokenText) {
                print("Echo detected, discarding: \(transcript)")
                finishPipeline(pipelineID, settings: settings, resumeListening: resumeListening)
                return
            }
            
            // Add user message
            let userMessage = ChatMessage(role: .user, content: transcript, timestamp: Date())
            messages.append(userMessage)
            
            try await streamAssistantResponse(
                transcript: transcript,
                settings: settings,
                resumeListening: resumeListening,
                pipelineID: pipelineID
            )
        } catch is CancellationError {
            return
        } catch {
            guard currentPipelineID == pipelineID else { return }
            print("Error: \(error)")
            player.stop()
            finishPipeline(pipelineID, settings: settings, resumeListening: resumeListening)
            let errorMessage = ChatMessage(role: .assistant, content: "⚠️ \(error.localizedDescription)\nTap to retry", timestamp: Date(), isError: true)
            messages.append(errorMessage)
        }
    }
    
    private func streamAssistantResponse(transcript: String, settings: AppSettings, resumeListening: Bool, pipelineID: UUID) async throws {
        try ensurePipelineIsActive(pipelineID)
        
        state = .thinking
        let openclaw = OpenClawService(baseURL: settings.openclawURL, token: settings.gatewayToken)
        let assistantMessage = ChatMessage(role: .assistant, content: "", timestamp: Date())
        messages.append(assistantMessage)
        let assistantMessageID = assistantMessage.id
        
        let elevenlabs = ElevenLabsService(apiKey: settings.elevenlabsAPIKey, voiceID: settings.selectedVoiceID)
        let ttsQueue = TTSChunkQueue(elevenlabs: elevenlabs, player: player)
        var sentenceBuffer = ""
        var spokenUpTo = 0
        var firstToken = true
        var isFirstChunk = true
        let chunkBreaks: [Character] = [".", "!", "?", "\n", ",", ";", ":", "-"]
        let maxChunkLength = 120
        
        player.prepareAudioSession()
        player.startQueue { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.finishPipeline(
                    pipelineID,
                    settings: settings,
                    resumeListening: resumeListening,
                    applyIgnorePeriod: true
                )
            }
        }
        
        let fullResponse = try await openclaw.sendMessageStreaming(transcript) { [weak self] token in
            guard let self else { return }
            try self.ensurePipelineIsActive(pipelineID)
            
            if firstToken {
                self.state = .streaming
                firstToken = false
            }

            let messageIndex = try self.assistantMessageIndex(for: assistantMessageID, pipelineID: pipelineID)
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
                
                try self.ensurePipelineIsActive(pipelineID)
                await ttsQueue.enqueue(text: trimmed)
                try self.ensurePipelineIsActive(pipelineID)
            }
        }
        
        try ensurePipelineIsActive(pipelineID)
        let messageIndex = try assistantMessageIndex(for: assistantMessageID, pipelineID: pipelineID)
        messages[messageIndex].content = fullResponse
        
        let trimmedResponse = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedResponse.isEmpty || trimmedResponse == "NO_REPLY" || trimmedResponse == "HEARTBEAT_OK" {
            let messageIndex = try assistantMessageIndex(for: assistantMessageID, pipelineID: pipelineID)
            messages.remove(at: messageIndex)
            player.stop()
            finishPipeline(pipelineID, settings: settings, resumeListening: resumeListening)
            return
        }
        
        lastSpokenText = fullResponse.lowercased()
        
        let remaining = String(fullResponse.dropFirst(spokenUpTo)).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            if state != .speaking {
                state = .speaking
                startSpeakingTimer()
            }
            
            try ensurePipelineIsActive(pipelineID)
            await ttsQueue.enqueue(text: remaining)
            try ensurePipelineIsActive(pipelineID)
        }
        
        player.finishQueue()
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

        startPipeline { [weak self] pipelineID in
            guard let self else { return }
            do {
                try await self.streamAssistantResponse(
                    transcript: transcript,
                    settings: settings,
                    resumeListening: false,
                    pipelineID: pipelineID
                )
            } catch is CancellationError {
                return
            } catch {
                guard self.currentPipelineID == pipelineID else { return }
                self.player.stop()
                self.finishPipeline(pipelineID)
                let errorMsg = ChatMessage(role: .assistant, content: "⚠️ \(error.localizedDescription)\nTap to retry", timestamp: Date(), isError: true)
                self.messages.append(errorMsg)
            }
        }
    }
    
    func deleteMessage(id: UUID) {
        messages.removeAll { $0.id == id }
    }
    
    func clearChat() {
        cancelCurrentPipeline()
        player.stop()
        stopSpeakingTimer()
        messages.removeAll()
        UserDefaults.standard.removeObject(forKey: messagesKey)
        state = .idle
    }
}
