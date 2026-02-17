import Foundation

class OpenClawService {
    private let baseURL: String
    private let token: String
    private var conversationHistory: [[String: String]] = []
    
    init(baseURL: String, token: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token
    }
    
    func sendMessage(_ text: String) async throws -> String {
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("agent:main:main", forHTTPHeaderField: "x-openclaw-session-key")
        request.timeoutInterval = 60
        
        // Add to conversation history
        conversationHistory.append(["role": "user", "content": text])
        
        // Keep last 20 messages for context
        let messages = Array(conversationHistory.suffix(20))
        
        let body: [String: Any] = [
            "model": "openclaw:main",
            "messages": messages,
            "user": "syam"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClawTalkError.llmFailed
        }
        
        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let content = result.choices.first?.message.content ?? "No response"
        
        // Add assistant response to history
        conversationHistory.append(["role": "assistant", "content": content])
        
        return content
    }
    
    func clearHistory() {
        conversationHistory.removeAll()
    }
}

struct ChatCompletionResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: ChoiceMessage
    }
    
    struct ChoiceMessage: Codable {
        let content: String
    }
}
