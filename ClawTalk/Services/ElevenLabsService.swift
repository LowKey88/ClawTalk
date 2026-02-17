import Foundation

class ElevenLabsService {
    private let apiKey: String
    private var voiceID: String
    
    init(apiKey: String, voiceID: String = "21m00Tcm4TlvDq8ikWAM") {
        self.apiKey = apiKey
        self.voiceID = voiceID
    }
    
    func setVoice(_ id: String) {
        self.voiceID = id
    }
    
    func synthesize(text: String) async throws -> Data {
        // Default to Rachel voice if no voice selected
        let activeVoiceID = voiceID.isEmpty ? "21m00Tcm4TlvDq8ikWAM" : voiceID
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(activeVoiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClawTalkError.ttsFailed
        }
        
        return data
    }
    
    func fetchVoices() async throws -> [Voice] {
        let url = URL(string: "https://api.elevenlabs.io/v1/voices")!
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClawTalkError.ttsFailed
        }
        
        let result = try JSONDecoder().decode(VoicesResponse.self, from: data)
        return result.voices
    }
}

struct VoicesResponse: Codable {
    let voices: [Voice]
}

struct Voice: Codable, Identifiable {
    let voice_id: String
    let name: String
    let category: String?
    
    var id: String { voice_id }
}
