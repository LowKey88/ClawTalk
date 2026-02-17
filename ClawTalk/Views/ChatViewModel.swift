import Foundation
import SwiftUI

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
}

@Observable
@MainActor
class ChatViewModel: NSObject, AudioRecorderDelegate {
    var messages: [ChatMessage] = [] {
        didSet { saveMessages() }
    }
    var state: ChatState = .idle
    var audioLevel: Float = 0.0
    
    private let recorder = AudioRecorder()
    private let player = AudioPlayer()
    private var pendingSettings: AppSettings?
    
    private var currentProfileID: UUID?
    
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
    
    // MARK: - Push-to-talk
    
    func startRecording() {
        recorder.startRecording()
        state = .recording
    }
    
    func stopAndProcess(settings: AppSettings) {
        guard let audioURL = recorder.stopRecording() else {
            state = .idle
            return
        }
        
        Task {
            await processAudio(audioURL: audioURL, settings: settings)
        }
    }
    
    // MARK: - Hands-free (VAD)
    
    func startHandsFree(settings: AppSettings) {
        pendingSettings = settings
        state = .listening
        recorder.startListening()
    }
    
    func stopHandsFree() {
        pendingSettings = nil
        recorder.stopListening()
        state = .idle
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
            await processAudio(audioURL: audioURL, settings: settings, resumeListening: true)
        }
    }
    
    // MARK: - Audio processing pipeline
    
    private func processAudio(audioURL: URL, settings: AppSettings, resumeListening: Bool = false) async {
        // Step 1: STT
        state = .transcribing
        let whisper = WhisperService(apiKey: settings.openaiAPIKey)
        
        do {
            let transcript = try await whisper.transcribe(audioURL: audioURL)
            
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
            
            var firstToken = true
            let fullResponse = try await openclaw.sendMessageStreaming(transcript) { [weak self] token in
                Task { @MainActor in
                    guard let self else { return }
                    if firstToken {
                        self.state = .streaming
                        firstToken = false
                    }
                    // Append token to the streaming message
                    self.messages[messageIndex].content += token
                }
            }
            
            // Ensure final content is complete
            messages[messageIndex].content = fullResponse
            
            // Step 3: TTS
            state = .speaking
            let elevenlabs = ElevenLabsService(apiKey: settings.elevenlabsAPIKey, voiceID: settings.selectedVoiceID)
            let audioData = try await elevenlabs.synthesize(text: fullResponse)
            
            // Play audio, then resume listening if hands-free
            player.play(data: audioData) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if resumeListening && settings.isHandsFree {
                        self.startHandsFree(settings: settings)
                    } else {
                        self.state = .idle
                    }
                }
            }
            
        } catch {
            print("Error: \(error)")
            let errorMessage = ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)", timestamp: Date())
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
        if settings.isHandsFree {
            startHandsFree(settings: settings)
        } else {
            state = .idle
        }
    }
    
    func updateAudioLevel() {
        audioLevel = recorder.audioLevel
    }
    
    func clearChat() {
        messages.removeAll()
        UserDefaults.standard.removeObject(forKey: messagesKey)
    }
}
