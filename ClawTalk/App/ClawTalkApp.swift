import SwiftUI
import AVFoundation
import UIKit

@main
struct ClawTalkApp: App {
    @State private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .onAppear {
                    settings.migrateIfNeeded()
                    configureAudioForBackground()
                    setupInterruptionHandling()
                    applyAppearance()
                }
                .onChange(of: settings.appearanceMode) {
                    applyAppearance()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        startBackgroundTask()
                        ensureAudioSessionActive()
                    case .active:
                        endBackgroundTask()
                        ensureAudioSessionActive()
                    default:
                        break
                    }
                }
        }
    }
    
    private func applyAppearance() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        window.overrideUserInterfaceStyle = settings.userInterfaceStyle
    }
    
    private func configureAudioForBackground() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("Audio session configured for background")
        } catch {
            print("Background audio config failed: \(error)")
        }
    }
    
    private func ensureAudioSessionActive() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
            print("Audio session re-activated")
        } catch {
            print("Failed to keep audio active: \(error)")
        }
    }
    
    private func startBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ClawTalkVoice") {
            // Expiration handler
            print("Background task expiring")
            self.endBackgroundTask()
        }
        print("Background task started, remaining: \(UIApplication.shared.backgroundTimeRemaining)s")
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            
            if type == .ended {
                // Re-activate audio after interruption (e.g. phone call)
                try? AVAudioSession.sharedInstance().setActive(true)
                print("Audio session reactivated after interruption")
            }
        }
    }
}
