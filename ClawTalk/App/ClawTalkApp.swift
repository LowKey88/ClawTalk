import SwiftUI
import AVFoundation

@main
struct ClawTalkApp: App {
    @State private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .preferredColorScheme(settings.colorScheme)
                .onAppear {
                    settings.migrateIfNeeded()
                    configureAudioForBackground()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        // Keep audio session active in background
                        ensureAudioSessionActive()
                    }
                }
        }
    }
    
    private func configureAudioForBackground() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Background audio config failed: \(error)")
        }
    }
    
    private func ensureAudioSessionActive() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
        } catch {
            print("Failed to keep audio active in background: \(error)")
        }
    }
}
