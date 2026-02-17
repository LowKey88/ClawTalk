import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String
    let timestamp: Date
    var isPlaying: Bool = false
    
    enum Role {
        case user
        case assistant
    }
}
