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
    private var isQueueFinished = false
    
    // MARK: - Single playback
    
    func play(data: Data, completion: (() -> Void)? = nil) {
        isQueueMode = false
        self.completion = completion
        playData(data)
    }
    
    // MARK: - Queue playback (for chunked TTS)
    
    func startQueue(completion: (() -> Void)? = nil) {
        isQueueMode = true
        isQueueFinished = false
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
        isQueueFinished = true
        completeQueueIfDone()
    }

    /// Fires the queue completion callback only when all chunks have been
    /// enqueued (isQueueFinished) AND fully played (!isPlaying && queue empty).
    private func completeQueueIfDone() {
        guard isQueueFinished && !isPlaying && queue.isEmpty else { return }
        isQueueMode = false
        isQueueFinished = false
        queueCompletion?()
    }
    
    private func playNext() {
        guard !queue.isEmpty else {
            isPlaying = false
            return
        }
        let data = queue.removeFirst()
        playData(data)
    }
    
    func prepareAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    private func playData(_ data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.isMeteringEnabled = true
            audioPlayer?.prepareToPlay()
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
        isQueueFinished = false
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
                    self.completeQueueIfDone()
                }
            } else {
                self.isPlaying = false
                self.completion?()
            }
        }
    }
}
