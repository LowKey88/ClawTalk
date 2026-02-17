import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    @AppStorage("openclawURL") var openclawURL: String = ""
    @AppStorage("gatewayToken") var gatewayToken: String = ""
    @AppStorage("openaiAPIKey") var openaiAPIKey: String = ""
    @AppStorage("elevenlabsAPIKey") var elevenlabsAPIKey: String = ""
    @AppStorage("selectedVoiceID") var selectedVoiceID: String = ""
    @AppStorage("selectedVoiceName") var selectedVoiceName: String = "Default"
    @AppStorage("isHandsFree") var isHandsFree: Bool = false
    
    var isConfigured: Bool {
        !openclawURL.isEmpty &&
        !gatewayToken.isEmpty &&
        !openaiAPIKey.isEmpty &&
        !elevenlabsAPIKey.isEmpty
    }
}
