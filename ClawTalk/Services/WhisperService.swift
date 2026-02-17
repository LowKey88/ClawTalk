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
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClawTalkError.sttFailed
        }
        
        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return result.text
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
