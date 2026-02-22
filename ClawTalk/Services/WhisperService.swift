import Foundation

class WhisperService {
    private let apiKey: String
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func transcribe(audioURL: URL) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        let audioData = try Data(contentsOf: audioURL)
        
        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("gpt-4o-mini-transcribe\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClawTalkError.sttFailed
        }
        
        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        let text = result.text
        
        // Filter Whisper hallucinations (random text from silence/noise)
        if Self.isHallucination(text) {
            return ""
        }
        
        return text
    }
    
    /// Detect common Whisper hallucination patterns
    static func isHallucination(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Too short
        if trimmed.count < 2 { return true }
        
        // Common hallucination phrases
        let hallucinations = [
            "请不吝点赞", "订阅", "转发", "小明星", "大跟班",
            "Thank you for watching", "Thanks for watching",
            "Please subscribe", "Like and subscribe",
            "Subtitles by", "Amara.org", "MosoSub",
            "ご視聴ありがとうございました", "字幕",
            "你", "您", "谢谢", "感谢",
        ]
        
        for phrase in hallucinations {
            if trimmed.contains(phrase) { return true }
        }
        
        // Mostly non-Latin when user likely speaks English/Malay
        let latinCount = trimmed.unicodeScalars.filter { $0.isASCII || ($0.value >= 0x00C0 && $0.value <= 0x024F) }.count
        let totalCount = trimmed.unicodeScalars.count
        if totalCount > 5 && Double(latinCount) / Double(totalCount) < 0.3 {
            return true
        }
        
        return false
    }
}

struct WhisperResponse: Codable {
    let text: String
}

enum ClawTalkError: LocalizedError {
    case sttFailed
    case llmFailed
    case ttsFailed
    case noAudio
    
    var errorDescription: String? {
        switch self {
        case .sttFailed: return "Speech-to-text failed"
        case .llmFailed: return "OpenClaw API failed"
        case .ttsFailed: return "Text-to-speech failed"
        case .noAudio: return "No audio recorded"
        }
    }
}
