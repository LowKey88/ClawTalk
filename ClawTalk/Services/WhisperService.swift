import Foundation

enum TranscriptionUtils {
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
