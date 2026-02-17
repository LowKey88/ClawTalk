import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) var settings
    @State private var showSettings = false
    
    var body: some View {
        Group {
            if settings.isConfigured {
                ChatView()
            } else if settings.profiles.isEmpty {
                WelcomeView(showSettings: $showSettings)
            } else {
                NeedKeysView(showSettings: $showSettings)
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

struct NeedKeysView: View {
    @Binding var showSettings: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("API Keys Needed")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Add your OpenAI and ElevenLabs API keys in Settings to start chatting")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button(action: { showSettings = true }) {
                Text("Open Settings")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
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
