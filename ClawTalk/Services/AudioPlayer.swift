import Foundation
import AVFoundation
import Combine

class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var audioLevel: Float = 0.0
    
    private var audioPlayer: AVAudioPlayer?
    private var completion: (() -> Void)?
    private var queue: [Data] = []
    private var queueCompletion: (() -> Void)?
    private var isQueueMode = false
    
    // MARK: - Single playback
    
    func play(data: Data, completion: (() -> Void)? = nil) {
        isQueueMode = false
        self.completion = completion
        playData(data)
    }
    
    // MARK: - Queue playback (for chunked TTS)
    
    func startQueue(completion: (() -> Void)? = nil) {
        isQueueMode = true
        queue.removeAll()
        queueCompletion = completion
    }
    
    func enqueue(data: Data) {
        queue.append(data)
        // If not currently playing, start playing from queue
        if !isPlaying {
            playNext()
        }
    }
    
    func finishQueue() {
        // Called when no more chunks will be added
        // If nothing is playing and queue is empty, complete now
        if !isPlaying && queue.isEmpty {
            isQueueMode = false
            DispatchQueue.main.async {
                self.queueCompletion?()
            }
        }
        // Otherwise, audioPlayerDidFinishPlaying will handle it
    }
    
    private func playNext() {
        guard !queue.isEmpty else {
            isPlaying = false
            return
        }
        let data = queue.removeFirst()
        playData(data)
    }
    
    private func playData(_ data: Data) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.isMeteringEnabled = true
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("Playback failed: \(error)")
            isPlaying = false
            if isQueueMode {
                playNext()
            } else {
                completion?()
            }
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        isPlaying = false
        audioLevel = 0.0
        queue.removeAll()
        isQueueMode = false
    }
    
    func updateMeters() {
        guard isPlaying, let player = audioPlayer else {
            audioLevel = 0.0
            return
        }
        player.updateMeters()
        let level = player.averagePower(forChannel: 0)
        let normalized = max(0, (level + 50) / 50)
        audioLevel = normalized
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            if self.isQueueMode {
                if !self.queue.isEmpty {
                    self.playNext()
                } else {
                    self.isPlaying = false
                    self.isQueueMode = false
                    self.queueCompletion?()
                }
            } else {
                self.isPlaying = false
                self.completion?()
            }
        }
    }
}
