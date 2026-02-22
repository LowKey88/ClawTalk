import Foundation
import AVFoundation

class AudioRecorder: NSObject {
    var isRecording = false
    var audioLevel: Float = 0.0
    var onAudioChunk: ((Data) -> Void)?
    var onSpeechLevelUpdate: ((Float) -> Void)?

    /// Whether the current audio output route is a built-in speaker/receiver (echo-prone)
    var isUsingSpeaker: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { $0.portType == .builtInSpeaker || $0.portType == .builtInReceiver }
    }

    private let targetSampleRate: Double = 24_000
    private let chunkDuration: Double = 0.10
    private let chunkQueue = DispatchQueue(label: "com.clawtalk.audio.chunk")

    private var audioEngine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var pcmChunkBuffer = Data()
    private var ignoreUntil: Date?
    private var silentPlayer: AVAudioPlayer?

    override init() {
        super.init()
        setupAudioSession()
    }

    // MARK: - Public controls

    func startRecording() {
        startCapture()
    }

    func stopRecording() {
        stopCapture()
    }

    func startListening() {
        startSilentAudio()
        startCapture()
    }

    /// Ignore audio chunks for a brief period (useful to avoid TTS echo pickup).
    func setIgnorePeriod(_ seconds: TimeInterval) {
        let adjusted = isUsingSpeaker ? seconds * 2.0 : seconds
        chunkQueue.async { [weak self] in
            self?.ignoreUntil = Date().addingTimeInterval(adjusted)
            self?.pcmChunkBuffer.removeAll(keepingCapacity: true)
        }
        print("Echo ignore: \(adjusted)s (speaker: \(isUsingSpeaker))")
    }

    func stopListening() {
        stopCapture()
        stopSilentAudio()
    }

    // MARK: - Audio session

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    /// Check and prefer Bluetooth mic before each recording
    private func preferBluetoothMic() {
        let session = AVAudioSession.sharedInstance()
        if let inputs = session.availableInputs {
            if let btInput = inputs.first(where: {
                $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE || $0.portType == .bluetoothA2DP
            }) {
                do {
                    try session.setPreferredInput(btInput)
                    print("Using Bluetooth mic: \(btInput.portName)")
                } catch {
                    print("Failed to set Bluetooth input: \(error)")
                }
            }
        }
    }

    // MARK: - Capture pipeline

    private func startCapture() {
        if isRecording { return }

        preferBluetoothMic()

        audioEngine.stop()
        audioEngine.reset()
        audioEngine = AVAudioEngine()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("Failed to create audio converter")
            return
        }

        self.targetFormat = targetFormat
        self.converter = converter

        pcmChunkBuffer.removeAll(keepingCapacity: true)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            inputNode.removeTap(onBus: 0)
            print("Audio engine start failed: \(error)")
        }
    }

    private func stopCapture() {
        guard isRecording else {
            audioLevel = 0.0
            return
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioEngine.reset()

        flushRemainingChunk()

        converter = nil
        targetFormat = nil
        isRecording = false
        audioLevel = 0.0
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        updateAudioLevel(from: buffer)

        guard let converter,
              let targetFormat else {
            return
        }

        let ratio = targetSampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 256

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return
        }

        var didProvideInput = false
        var error: NSError?

        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error {
            if let error {
                print("Audio convert failed: \(error)")
            }
            return
        }

        guard convertedBuffer.frameLength > 0,
              let channelData = convertedBuffer.int16ChannelData else {
            return
        }

        let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
        let pcmData = Data(bytes: channelData[0], count: byteCount)

        chunkQueue.async { [weak self] in
            self?.appendPCMData(pcmData)
        }
    }

    private func appendPCMData(_ data: Data) {
        let now = Date()
        if let ignoreUntil, now < ignoreUntil {
            pcmChunkBuffer.removeAll(keepingCapacity: true)
            return
        }
        ignoreUntil = nil

        pcmChunkBuffer.append(data)
        let chunkSizeBytes = Int(targetSampleRate * chunkDuration) * MemoryLayout<Int16>.size

        while pcmChunkBuffer.count >= chunkSizeBytes {
            let chunk = Data(pcmChunkBuffer.prefix(chunkSizeBytes))
            pcmChunkBuffer.removeFirst(chunkSizeBytes)
            onAudioChunk?(chunk)
        }
    }

    private func flushRemainingChunk() {
        chunkQueue.sync {
            guard !pcmChunkBuffer.isEmpty else { return }
            onAudioChunk?(pcmChunkBuffer)
            pcmChunkBuffer.removeAll(keepingCapacity: true)
        }
    }

    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else {
            return
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sumSquares: Float = 0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Float(frameCount))
        let db = 20 * log10(max(rms, 0.000_01))
        let normalized = max(0, min(1, (db + 50) / 50))

        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = normalized
            self?.onSpeechLevelUpdate?(normalized)
        }
    }

    // MARK: - Silent audio (keeps app alive in background)

    private func startSilentAudio() {
        guard silentPlayer == nil else { return }

        let sampleRate: Double = 16_000
        let numSamples = Int(sampleRate)
        let dataSize = numSamples * 2
        let fileSize = 44 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize - 8).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16_000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(32_000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        data.append(Data(count: dataSize))

        do {
            silentPlayer = try AVAudioPlayer(data: data)
            silentPlayer?.numberOfLoops = -1
            silentPlayer?.volume = 0.05
            silentPlayer?.prepareToPlay()
            silentPlayer?.play()
        } catch {
            print("Silent audio failed: \(error)")
        }
    }

    private func stopSilentAudio() {
        silentPlayer?.stop()
        silentPlayer = nil
    }
}
