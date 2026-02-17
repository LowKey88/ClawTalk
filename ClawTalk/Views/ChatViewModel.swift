import Foundation
import SwiftUI

enum ChatState {
    case idle
    case recording
    case transcribing
    case thinking
    case speaking
}

@Observable
@MainActor
class ChatViewModel {
    var messages: [ChatMessage] = []
    var state: ChatState = .idle
    var audioLevel: Float = 0.0
    
    private let recorder = AudioRecorder()
    private let player = AudioPlayer()
    
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
    
    func updateAudioLevel() {
        audioLevel = recorder.audioLevel
    }
    
    private func processAudio(audioURL: URL, settings: AppSettings) async {
        // Step 1: STT
        state = .transcribing
        let whisper = WhisperService(apiKey: settings.openaiAPIKey)
        
        do {
            let transcript = try await whisper.transcribe(audioURL: audioURL)
            
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .idle
                return
            }
            
            // Add user message
            let userMessage = ChatMessage(role: .user, content: transcript, timestamp: Date())
            messages.append(userMessage)
            
            // Step 2: LLM
            state = .thinking
            let openclaw = OpenClawService(baseURL: settings.openclawURL, token: settings.gatewayToken)
            let response = try await openclaw.sendMessage(transcript)
            
            // Add assistant message
            let assistantMessage = ChatMessage(role: .assistant, content: response, timestamp: Date())
            messages.append(assistantMessage)
            
            // Step 3: TTS
            state = .speaking
            let elevenlabs = ElevenLabsService(apiKey: settings.elevenlabsAPIKey, voiceID: settings.selectedVoiceID)
            let audioData = try await elevenlabs.synthesize(text: response)
            
            // Play audio
            player.play(data: audioData) { [weak self] in
                Task { @MainActor in
                    self?.state = .idle
                }
            }
            
        } catch {
            print("Error: \(error)")
            let errorMessage = ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)", timestamp: Date())
            messages.append(errorMessage)
            state = .idle
        }
    }
    
    func clearChat() {
        messages.removeAll()
    }
}
