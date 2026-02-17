import Foundation
import SwiftUI

@Observable
class AppSettings {
    var openclawURL: String {
        get { UserDefaults.standard.string(forKey: "openclawURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openclawURL") }
    }
    var gatewayToken: String {
        get { UserDefaults.standard.string(forKey: "gatewayToken") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "gatewayToken") }
    }
    var openaiAPIKey: String {
        get { UserDefaults.standard.string(forKey: "openaiAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openaiAPIKey") }
    }
    var elevenlabsAPIKey: String {
        get { UserDefaults.standard.string(forKey: "elevenlabsAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "elevenlabsAPIKey") }
    }
    var selectedVoiceID: String {
        get { UserDefaults.standard.string(forKey: "selectedVoiceID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedVoiceID") }
    }
    var selectedVoiceName: String {
        get { UserDefaults.standard.string(forKey: "selectedVoiceName") ?? "Default" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedVoiceName") }
    }
    var isHandsFree: Bool {
        get { UserDefaults.standard.bool(forKey: "isHandsFree") }
        set { UserDefaults.standard.set(newValue, forKey: "isHandsFree") }
    }
    
    var isConfigured: Bool {
        !openclawURL.isEmpty &&
        !gatewayToken.isEmpty &&
        !openaiAPIKey.isEmpty &&
        !elevenlabsAPIKey.isEmpty
    }
}
