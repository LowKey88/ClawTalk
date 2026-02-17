import SwiftUI

@main
struct ClawTalkApp: App {
    @State private var settings = AppSettings()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .preferredColorScheme(.dark)
        }
    }
}
