import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss
    @State private var voices: [Voice] = []
    @State private var isLoadingVoices = false
    @State private var showToken = false
    @State private var showAPIKeys = false
    
    var body: some View {
        NavigationStack {
            Form {
                // OpenClaw Section
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("https://openclaw.example.com", text: $settings.openclawURL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gateway Token")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            if showToken {
                                TextField("Token", text: $settings.gatewayToken)
                                    .autocapitalization(.none)
                            } else {
                                SecureField("Token", text: $settings.gatewayToken)
                            }
                            Button(action: { showToken.toggle() }) {
                                Image(systemName: showToken ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("OpenClaw", systemImage: "server.rack")
                } footer: {
                    Text("Get these from running 'setup-api' on your VPS")
                }
                
                // API Keys Section
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenAI API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            if showAPIKeys {
                                TextField("sk-...", text: $settings.openaiAPIKey)
                                    .autocapitalization(.none)
                            } else {
                                SecureField("sk-...", text: $settings.openaiAPIKey)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ElevenLabs API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            if showAPIKeys {
                                TextField("xi-...", text: $settings.elevenlabsAPIKey)
                                    .autocapitalization(.none)
                            } else {
                                SecureField("xi-...", text: $settings.elevenlabsAPIKey)
                            }
                        }
                    }
                    
                    Toggle("Show API Keys", isOn: $showAPIKeys)
                } header: {
                    Label("API Keys", systemImage: "key.fill")
                } footer: {
                    Text("Keys are stored locally on your device")
                }
                
                // Voice Section
                Section {
                    if voices.isEmpty {
                        Button(action: { loadVoices() }) {
                            HStack {
                                Text("Load Voices")
                                if isLoadingVoices {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(settings.elevenlabsAPIKey.isEmpty || isLoadingVoices)
                    } else {
                        Picker("Voice", selection: $settings.selectedVoiceID) {
                            ForEach(voices) { voice in
                                Text(voice.name)
                                    .tag(voice.voice_id)
                            }
                        }
                    }
                    
                    if !settings.selectedVoiceName.isEmpty {
                        HStack {
                            Text("Selected")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(settings.selectedVoiceName)
                        }
                    }
                } header: {
                    Label("Voice", systemImage: "speaker.wave.2.fill")
                }
                
                // Mode Section
                Section {
                    Toggle("Hands-free Mode", isOn: $settings.isHandsFree)
                } header: {
                    Label("Mode", systemImage: "hand.raised.fill")
                } footer: {
                    Text(settings.isHandsFree ?
                         "Auto-detects when you speak" :
                         "Hold the mic button to talk")
                }
                
                // Status
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        if settings.isConfigured {
                            Label("Ready", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Not configured", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Label("Connection", systemImage: "wifi")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: settings.selectedVoiceID) {
                if let voice = voices.first(where: { $0.voice_id == settings.selectedVoiceID }) {
                    settings.selectedVoiceName = voice.name
                }
            }
        }
    }
    
    private func loadVoices() {
        guard !settings.elevenlabsAPIKey.isEmpty else { return }
        isLoadingVoices = true
        
        Task {
            do {
                let service = ElevenLabsService(apiKey: settings.elevenlabsAPIKey)
                let fetchedVoices = try await service.fetchVoices()
                await MainActor.run {
                    voices = fetchedVoices
                    isLoadingVoices = false
                }
            } catch {
                await MainActor.run {
                    isLoadingVoices = false
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
        .preferredColorScheme(.dark)
}
