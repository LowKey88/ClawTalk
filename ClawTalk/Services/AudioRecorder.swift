import Foundation
import AVFoundation
import Combine

protocol AudioRecorderDelegate: AnyObject {
    func audioRecorderDidDetectSpeechStart()
    func audioRecorderDidDetectSpeechEnd(audioURL: URL)
}

class AudioRecorder: NSObject {
    var isRecording = false
    var audioLevel: Float = 0.0
    weak var vadDelegate: AudioRecorderDelegate?
    
    // VAD settings
    private let speechThreshold: Float = -25.0   // dB threshold for speech
    private let silenceTimeout: TimeInterval = 1.2 // seconds of silence to end
    private let minSpeechDuration: TimeInterval = 0.3 // minimum speech to count
    
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var isVADMode = false
    private var isSpeechDetected = false
    private var speechStartTime: Date?
    private var lastSpeechTime: Date?
    private var ignoreUntil: Date?
    
    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("clawtalk_recording.m4a")
    }
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    // MARK: - Push-to-talk mode
    
    func startRecording() {
        isVADMode = false
        beginRecording()
    }
    
    func stopRecording() -> URL? {
        stopMonitoring()
        audioRecorder?.stop()
        isRecording = false
        audioLevel = 0.0
        
        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            return nil
        }
        return recordingURL
    }
    
    // MARK: - VAD (hands-free) mode
    
    func startListening() {
        isVADMode = true
        isSpeechDetected = false
        speechStartTime = nil
        lastSpeechTime = nil
        beginRecording()
    }
    
    /// Ignore VAD input for a brief period (avoids TTS echo pickup)
    func setIgnorePeriod(_ seconds: TimeInterval) {
        ignoreUntil = Date().addingTimeInterval(seconds)
        // Reset any in-progress speech detection
        isSpeechDetected = false
        speechStartTime = nil
        lastSpeechTime = nil
    }
    
    func stopListening() {
        isVADMode = false
        isSpeechDetected = false
        stopMonitoring()
        audioRecorder?.stop()
        isRecording = false
        audioLevel = 0.0
    }
    
    // MARK: - Private
    
    private func beginRecording() {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            try? FileManager.default.removeItem(at: recordingURL)
            
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.updateMeters()
            }
        } catch {
            print("Recording failed: \(error)")
        }
    }
    
    private func stopMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
    
    private func updateMeters() {
        audioRecorder?.updateMeters()
        let level = audioRecorder?.averagePower(forChannel: 0) ?? -160
        let normalized = max(0, (level + 50) / 50)
        audioLevel = normalized
        
        guard isVADMode else { return }
        
        let now = Date()
        
        // Ignore period after TTS to avoid echo
        if let ignoreUntil, now < ignoreUntil { return }
        ignoreUntil = nil
        
        if level > speechThreshold {
            // Speech detected
            lastSpeechTime = now
            
            if !isSpeechDetected {
                isSpeechDetected = true
                speechStartTime = now
                vadDelegate?.audioRecorderDidDetectSpeechStart()
            }
        } else if isSpeechDetected, let lastSpeech = lastSpeechTime {
            // Silence after speech - check timeout
            let silenceDuration = now.timeIntervalSince(lastSpeech)
            
            if silenceDuration >= silenceTimeout {
                // Check minimum speech duration
                let speechDuration = lastSpeech.timeIntervalSince(speechStartTime ?? lastSpeech)
                
                if speechDuration >= minSpeechDuration {
                    // Speech ended - stop and deliver
                    isSpeechDetected = false
                    stopMonitoring()
                    audioRecorder?.stop()
                    isRecording = false
                    audioLevel = 0.0
                    
                    if FileManager.default.fileExists(atPath: recordingURL.path) {
                        vadDelegate?.audioRecorderDidDetectSpeechEnd(audioURL: recordingURL)
                    }
                } else {
                    // Too short, reset
                    isSpeechDetected = false
                    speechStartTime = nil
                    lastSpeechTime = nil
                }
            }
        }
    }
}
