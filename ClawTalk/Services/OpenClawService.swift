import Foundation

class OpenClawService {
    private let baseURL: String
    private let token: String
    private let sessionKey: String
    private let userID: String
    private var conversationHistory: [[String: String]] = []
    
    init(baseURL: String, token: String, sessionKey: String, userID: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token
        self.sessionKey = sessionKey
        self.userID = userID
    }
    
    // MARK: - Streaming response
    
    func sendMessageStreaming(_ text: String, onToken: @escaping (String) -> Void) async throws -> String {
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionKey, forHTTPHeaderField: "x-openclaw-session-key")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300  // 5 min for long agent runs
        
        conversationHistory.append(["role": "user", "content": text])
        let messages = Array(conversationHistory.suffix(20))
        
        let body: [String: Any] = [
            "model": "openclaw:main",
            "messages": messages,
            "user": userID,
            "stream": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Custom session with longer timeouts for SSE streaming
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClawTalkError.llmFailed
        }
        
        var fullContent = ""
        
        for try await line in bytes.lines {
            // SSE format: "data: {...}" or "data: [DONE]"
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            
            if jsonString == "[DONE]" { break }
            
            guard let jsonData = jsonString.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: jsonData),
                  let delta = chunk.choices.first?.delta.content else {
                continue
            }
            
            fullContent += delta
            onToken(delta)
        }
        
        if fullContent.isEmpty {
            fullContent = "No response"
        }
        
        conversationHistory.append(["role": "assistant", "content": fullContent])
        return fullContent
    }
    
    // MARK: - Non-streaming (fallback)
    
    func sendMessage(_ text: String) async throws -> String {
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionKey, forHTTPHeaderField: "x-openclaw-session-key")
        request.timeoutInterval = 60
        
        conversationHistory.append(["role": "user", "content": text])
        let messages = Array(conversationHistory.suffix(20))
        
        let body: [String: Any] = [
            "model": "openclaw:main",
            "messages": messages,
            "user": userID
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClawTalkError.llmFailed
        }
        
        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let content = result.choices.first?.message.content ?? "No response"
        
        conversationHistory.append(["role": "assistant", "content": content])
        return content
    }
    
    func clearHistory() {
        conversationHistory.removeAll()
    }
}

// MARK: - Response models

struct ChatCompletionResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: ChoiceMessage
    }
    
    struct ChoiceMessage: Codable {
        let content: String
    }
}

struct StreamChunk: Codable {
    let choices: [StreamChoice]
    
    struct StreamChoice: Codable {
        let delta: Delta
    }
    
    struct Delta: Codable {
        let content: String?
    }
}
