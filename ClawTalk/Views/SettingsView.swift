import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) var settings
    @Environment(\.dismiss) var dismiss
    @State private var showAPIKeys = false
    @State private var editingProfile: BotProfile?
    @State private var showAddProfile = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    
    var body: some View {
        @Bindable var settings = settings
        
        NavigationStack {
            Form {
                // Profiles Section
                Section {
                    ForEach(settings.profiles) { profile in
                        Button(action: {
                            settings.setActiveProfile(profile.id)
                        }) {
                            HStack {
                                Text(profile.emoji)
                                    .font(.title2)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .fontWeight(profile.id == settings.activeProfileID ? .bold : .regular)
                                        .foregroundColor(.primary)
                                    Text(profile.openclawURL)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if profile.id == settings.activeProfileID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                settings.deleteProfile(profile.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                editingProfile = profile
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    
                    Button(action: { showAddProfile = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("Add Profile")
                        }
                    }
                } header: {
                    Label("Bot Profiles", systemImage: "person.2.fill")
                } footer: {
                    Text("Tap to switch, swipe to edit or delete")
                }
                
                // API Keys Section (global)
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
                    Label("API Keys (Shared)", systemImage: "key.fill")
                } footer: {
                    Text("These keys are shared across all profiles")
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
                
                // Appearance
                Section {
                    Picker("Theme", selection: $settings.appearanceMode) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Appearance", systemImage: "paintbrush.fill")
                }
                
                // Connection Status
                Section {
                    if let profile = settings.activeProfile {
                        HStack {
                            Text("Active")
                            Spacer()
                            Text("\(profile.emoji) \(profile.name)")
                        }
                        HStack {
                            Text("Voice")
                            Spacer()
                            Text(profile.voiceName)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("Server")
                        Spacer()
                        switch connectionStatus {
                        case .unknown:
                            Label("Not checked", systemImage: "questionmark.circle.fill")
                                .foregroundColor(.secondary)
                        case .checking:
                            ProgressView()
                                .scaleEffect(0.8)
                        case .connected(let ms):
                            Label("Connected (\(ms)ms)", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        case .failed(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    
                    Button(action: { checkConnection() }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Test Connection")
                        }
                    }
                    .disabled(!settings.isConfigured)
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
            .sheet(isPresented: $showAddProfile) {
                ProfileEditorView(profile: BotProfile(), isNew: true)
            }
            .onAppear {
                if settings.isConfigured {
                    checkConnection()
                }
            }
            .sheet(item: $editingProfile) { profile in
                ProfileEditorView(profile: profile, isNew: false)
            }
        }
    }
}

// MARK: - Profile Editor

struct ProfileEditorView: View {
    @Environment(AppSettings.self) var settings
    @Environment(\.dismiss) var dismiss
    @State var profile: BotProfile
    let isNew: Bool
    @State private var showToken = false
    @State private var voices: [Voice] = []
    @State private var isLoadingVoices = false
    
    let emojiOptions = ["🤖", "🐙", "🦀", "🦐", "🦑", "🐟", "🐠", "🦈", "🐳", "🧠", "⚡", "🔮", "🛡️", "🎯", "👩", "👨", "🧑", "👧", "👦", "🧙‍♀️", "🧝‍♀️", "🦸‍♀️", "🦹‍♀️", "🥷", "👾", "🤡", "💀", "👻", "🐱", "🐶", "🦊", "🐰", "🦄"]
    
    var body: some View {
        NavigationStack {
            Form {
                // Identity
                Section {
                    HStack {
                        Text("Emoji")
                        Spacer()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(emojiOptions, id: \.self) { emoji in
                                    Text(emoji)
                                        .font(.title2)
                                        .padding(6)
                                        .background(profile.emoji == emoji ? Color.blue.opacity(0.3) : Color.clear)
                                        .cornerRadius(8)
                                        .onTapGesture { profile.emoji = emoji }
                                }
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. Botopus", text: $profile.name)
                    }
                } header: {
                    Label("Identity", systemImage: "person.fill")
                }
                
                // Connection
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("https://openclaw.example.com", text: $profile.openclawURL)
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
                                TextField("Token", text: $profile.gatewayToken)
                                    .autocapitalization(.none)
                            } else {
                                SecureField("Token", text: $profile.gatewayToken)
                            }
                            Button(action: { showToken.toggle() }) {
                                Image(systemName: showToken ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("Connection", systemImage: "server.rack")
                } footer: {
                    Text("Get these from running 'setup-api' on your VPS")
                }
                
                // Voice
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
                        Picker("Voice", selection: $profile.voiceID) {
                            Text("Default").tag("")
                            ForEach(voices) { voice in
                                Text(voice.name).tag(voice.voice_id)
                            }
                        }
                    }
                    
                    if !profile.voiceName.isEmpty && profile.voiceName != "Default" {
                        HStack {
                            Text("Selected")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(profile.voiceName)
                        }
                    }
                } header: {
                    Label("Voice", systemImage: "speaker.wave.2.fill")
                }
            }
            .navigationTitle(isNew ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(profile.name.isEmpty || profile.openclawURL.isEmpty)
                }
            }
            .onChange(of: profile.voiceID) {
                if let voice = voices.first(where: { $0.voice_id == profile.voiceID }) {
                    profile.voiceName = voice.name
                }
            }
        }
    }
    
    private func save() {
        if isNew {
            settings.addProfile(profile)
        } else {
            settings.updateProfile(profile)
        }
        dismiss()
    }
    
    private func loadVoices() {
        guard !settings.elevenlabsAPIKey.isEmpty else { return }
        isLoadingVoices = true
        
        Task {
            do {
                let service = ElevenLabsService(apiKey: settings.elevenlabsAPIKey)
                let fetchedVoices = try await service.fetchVoices()
                voices = fetchedVoices
                isLoadingVoices = false
            } catch {
                isLoadingVoices = false
            }
        }
    }
}

enum ConnectionStatus {
    case unknown
    case checking
    case connected(Int)  // latency in ms
    case failed(String)
}

extension SettingsView {
    func checkConnection() {
        guard let profile = settings.activeProfile else { return }
        connectionStatus = .checking
        
        // Test connection with a lightweight HEAD request to the API endpoint
        let baseURL = profile.openclawURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(baseURL)/v1/chat/completions"
        
        guard let url = URL(string: urlString) else {
            connectionStatus = .failed("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Bearer \(profile.gatewayToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        
        Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                if let http = response as? HTTPURLResponse {
                    // Any response means server is reachable and auth is accepted
                    // 405 = Method Not Allowed (HEAD not supported but server alive)
                    if (200...499).contains(http.statusCode) && http.statusCode != 401 && http.statusCode != 403 {
                        connectionStatus = .connected(elapsed)
                    } else if http.statusCode == 401 || http.statusCode == 403 {
                        connectionStatus = .failed("Auth failed")
                    } else {
                        connectionStatus = .failed("HTTP \(http.statusCode)")
                    }
                } else {
                    connectionStatus = .failed("Unknown error")
                }
            } catch {
                connectionStatus = .failed("Unreachable")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
        .preferredColorScheme(.dark)
}
