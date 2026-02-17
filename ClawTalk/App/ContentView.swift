import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) var settings
    @State private var showSettings = false
    
    var body: some View {
        Group {
            if settings.isConfigured {
                ChatView()
            } else {
                WelcomeView(showSettings: $showSettings)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

struct WelcomeView: View {
    @Binding var showSettings: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("🐙")
                .font(.system(size: 80))
            
            Text("ClawTalk")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Voice chat with your OpenClaw agent")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: { showSettings = true }) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
        .preferredColorScheme(.dark)
}
