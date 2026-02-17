import Foundation
import AVFoundation
import Combine

class AudioRecorder: NSObject {
    var isRecording = false
    var audioLevel: Float = 0.0
    
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
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
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    func startRecording() {
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
                self?.audioRecorder?.updateMeters()
                let level = self?.audioRecorder?.averagePower(forChannel: 0) ?? -160
                let normalized = max(0, (level + 50) / 50)
                self?.audioLevel = normalized
            }
        } catch {
            print("Recording failed: \(error)")
        }
    }
    
    func stopRecording() -> URL? {
        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder?.stop()
        isRecording = false
        audioLevel = 0.0
        
        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            return nil
        }
        return recordingURL
    }
}
