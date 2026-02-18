import Foundation
import SwiftUI

// MARK: - Bot Profile

struct BotProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String        // e.g. "Botopus", "Moltopus"
    var emoji: String       // e.g. "🐙", "🦀"
    var openclawURL: String
    var gatewayToken: String
    var voiceID: String
    var voiceName: String
    
    init(id: UUID = UUID(), name: String = "", emoji: String = "🤖", openclawURL: String = "", gatewayToken: String = "", voiceID: String = "", voiceName: String = "Default") {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.openclawURL = openclawURL
        self.gatewayToken = gatewayToken
        self.voiceID = voiceID
        self.voiceName = voiceName
    }
    
    var isConfigured: Bool {
        !openclawURL.isEmpty && !gatewayToken.isEmpty && !name.isEmpty
    }
}

// MARK: - App Settings

@Observable
class AppSettings {
    
    // MARK: Global keys (shared across profiles)
    
    var openaiAPIKey: String {
        get { UserDefaults.standard.string(forKey: "openaiAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openaiAPIKey") }
    }
    var elevenlabsAPIKey: String {
        get { UserDefaults.standard.string(forKey: "elevenlabsAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "elevenlabsAPIKey") }
    }
    var isHandsFree: Bool {
        get { UserDefaults.standard.bool(forKey: "isHandsFree") }
        set { UserDefaults.standard.set(newValue, forKey: "isHandsFree") }
    }
    
    // 0 = system, 1 = light, 2 = dark
    var appearanceMode: Int = UserDefaults.standard.integer(forKey: "appearanceMode") {
        didSet { UserDefaults.standard.set(appearanceMode, forKey: "appearanceMode") }
    }
    
    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil  // follow system
        }
    }
    
    /// Always returns a concrete ColorScheme - for sheets that don't inherit system appearance.
    /// When mode is System, queries the device's actual appearance via UIScreen.
    var resolvedColorScheme: ColorScheme {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default:
            let style = UIScreen.main.traitCollection.userInterfaceStyle
            return style == .dark ? .dark : .light
        }
    }
    
    // MARK: Profiles (stored properties for SwiftUI observation)
    
    var profiles: [BotProfile] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(profiles) {
                UserDefaults.standard.set(encoded, forKey: "botProfiles")
            }
        }
    }
    
    var activeProfileID: UUID? = nil {
        didSet {
            UserDefaults.standard.set(activeProfileID?.uuidString, forKey: "activeProfileID")
        }
    }
    
    init() {
        // Load from UserDefaults on init
        if let data = UserDefaults.standard.data(forKey: "botProfiles"),
           let decoded = try? JSONDecoder().decode([BotProfile].self, from: data) {
            self.profiles = decoded
        }
        if let str = UserDefaults.standard.string(forKey: "activeProfileID"),
           let uuid = UUID(uuidString: str) {
            self.activeProfileID = uuid
        }
    }
    
    var activeProfile: BotProfile? {
        profiles.first(where: { $0.id == activeProfileID })
    }
    
    // MARK: Convenience (active profile properties)
    
    var openclawURL: String { activeProfile?.openclawURL ?? "" }
    var gatewayToken: String { activeProfile?.gatewayToken ?? "" }
    var selectedVoiceID: String { activeProfile?.voiceID ?? "" }
    var selectedVoiceName: String { activeProfile?.voiceName ?? "Default" }
    
    var isConfigured: Bool {
        guard let profile = activeProfile else {
            // Fallback: if profiles exist but no active, auto-select first
            if let first = profiles.first {
                activeProfileID = first.id
                return first.isConfigured && !openaiAPIKey.isEmpty && !elevenlabsAPIKey.isEmpty
            }
            return false
        }
        return profile.isConfigured &&
               !openaiAPIKey.isEmpty &&
               !elevenlabsAPIKey.isEmpty
    }
    
    // MARK: Profile management
    
    func addProfile(_ profile: BotProfile) {
        var list = profiles
        list.append(profile)
        profiles = list
        // Always set as active if it's the first or no active set
        if activeProfileID == nil || list.count == 1 {
            activeProfileID = profile.id
        }
    }
    
    func updateProfile(_ profile: BotProfile) {
        var list = profiles
        if let idx = list.firstIndex(where: { $0.id == profile.id }) {
            list[idx] = profile
            profiles = list
        }
    }
    
    func deleteProfile(_ id: UUID) {
        var list = profiles
        list.removeAll(where: { $0.id == id })
        profiles = list
        if activeProfileID == id {
            activeProfileID = list.first?.id
        }
    }
    
    func setActiveProfile(_ id: UUID) {
        activeProfileID = id
    }
    
    // MARK: Migration from old single-profile settings
    
    func migrateIfNeeded() {
        guard profiles.isEmpty else { return }
        
        let oldURL = UserDefaults.standard.string(forKey: "openclawURL") ?? ""
        let oldToken = UserDefaults.standard.string(forKey: "gatewayToken") ?? ""
        let oldVoiceID = UserDefaults.standard.string(forKey: "selectedVoiceID") ?? ""
        let oldVoiceName = UserDefaults.standard.string(forKey: "selectedVoiceName") ?? "Default"
        
        guard !oldURL.isEmpty else { return }
        
        let migrated = BotProfile(
            name: "My Bot",
            emoji: "🤖",
            openclawURL: oldURL,
            gatewayToken: oldToken,
            voiceID: oldVoiceID,
            voiceName: oldVoiceName
        )
        addProfile(migrated)
    }
}
