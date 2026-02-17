import SwiftUI
import Combine

struct ChatView: View {
    @Environment(AppSettings.self) var settings
    @State private var viewModel = ChatViewModel()
    @State private var showSettings = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if viewModel.state != .idle {
                                StatusBubble(text: viewModel.state.displayText, icon: viewModel.state.displayIcon)
                                    .id("status-bubble")
                            }
                            // Streaming text shows directly in message bubble (no status needed)
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) {
                        if let last = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.messages.last?.content) {
                        // Auto-scroll during streaming as content grows
                        if let last = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.state) {
                        // Scroll to status bubble or last message when state changes
                        withAnimation {
                            if viewModel.state != .idle {
                                proxy.scrollTo("status-bubble", anchor: .bottom)
                            } else if let last = viewModel.messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Bottom controls
                VStack(spacing: 12) {
                    // Waveform
                    if viewModel.state == .recording || viewModel.state == .listening {
                        WaveformView(level: viewModel.audioLevel)
                            .frame(height: 40)
                            .padding(.horizontal)
                    }
                    
                    // Skip button when speaking
                    if viewModel.state == .speaking {
                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            viewModel.skipSpeaking(settings: settings)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "forward.fill")
                                Text("Skip")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.orange)
                            .cornerRadius(20)
                        }
                    }
                    
                    // Mic button
                    HStack {
                        Spacer()
                        
                        if settings.isHandsFree {
                            // Hands-free: tap to start/stop listening
                            HandsFreeButton(
                                state: viewModel.state,
                                onTap: {
                                    if viewModel.state == .listening || viewModel.state == .recording {
                                        viewModel.stopHandsFree()
                                    } else if viewModel.state == .idle {
                                        viewModel.startHandsFree(settings: settings)
                                    }
                                }
                            )
                        } else {
                            // Push-to-talk
                            VoiceButton(
                                isRecording: viewModel.state == .recording,
                                isDisabled: viewModel.state == .transcribing ||
                                           viewModel.state == .thinking ||
                                           viewModel.state == .streaming ||
                                           viewModel.state == .speaking,
                                onPress: { viewModel.startRecording() },
                                onRelease: { viewModel.stopAndProcess(settings: settings) }
                            )
                        }
                        
                        Spacer()
                    }
                    
                    // Mode toggle
                    HStack {
                        Image(systemName: settings.isHandsFree ? "hand.raised.slash.fill" : "hand.raised.fill")
                            .foregroundColor(.secondary)
                        Text(settings.isHandsFree ? "Hands-free" : "Push to talk")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Toggle("", isOn: Bindable(settings).isHandsFree)
                            .labelsHidden()
                            .scaleEffect(0.8)
                    }
                    .padding(.bottom, 8)
                    .onChange(of: settings.isHandsFree) { _, isHandsFree in
                        // Stop current mode when toggling
                        if !isHandsFree {
                            viewModel.stopHandsFree()
                        }
                    }
                }
                .padding(.top, 8)
                .background(Color(.systemBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(settings.profiles) { profile in
                            Button(action: {
                                let impact = UINotificationFeedbackGenerator()
                                impact.notificationOccurred(.success)
                                settings.setActiveProfile(profile.id)
                            }) {
                                HStack {
                                    Text("\(profile.emoji) \(profile.name)")
                                    if profile.id == settings.activeProfileID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(action: { showSettings = true }) {
                            Label("Manage Profiles", systemImage: "person.2.fill")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if let profile = settings.activeProfile {
                                Text(profile.emoji)
                                Text(profile.name)
                                    .fontWeight(.semibold)
                            } else {
                                Text("ClawTalk")
                                    .fontWeight(.semibold)
                            }
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.primary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { viewModel.clearChat() }) {
                        Image(systemName: "trash")
                    }
                    .foregroundColor(.red)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                viewModel.switchToProfile(settings.activeProfileID)
            }
            .onChange(of: settings.activeProfileID) { _, newID in
                // Stop any active recording/listening before switching
                viewModel.stopHandsFree()
                viewModel.switchToProfile(newID)
            }
        }
    }
}

// MARK: - Hands-free button

struct HandsFreeButton: View {
    let state: ChatState
    let onTap: () -> Void
    
    var body: some View {
        Circle()
            .fill(buttonColor)
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: iconName)
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .symbolEffect(.pulse, isActive: state == .listening || state == .recording || state == .speaking)
            )
            .shadow(color: buttonColor.opacity(0.4), radius: state == .recording ? 20 : 10)
            .scaleEffect(state == .recording ? 1.1 : 1.0)
            .animation(.spring(response: 0.3), value: state)
            .opacity(isDisabled ? 0.5 : 1.0)
            .onTapGesture {
                guard !isDisabled else { return }
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                onTap()
            }
    }
    
    private var buttonColor: Color {
        switch state {
        case .listening: return .green
        case .recording: return .red
        case .streaming: return .purple
        case .transcribing, .thinking, .speaking: return .gray
        case .idle: return .blue
        }
    }
    
    private var iconName: String {
        switch state {
        case .listening: return "ear.fill"
        case .recording: return "waveform"
        case .transcribing: return "text.bubble"
        case .thinking: return "brain"
        case .streaming: return "text.cursor"
        case .speaking: return "speaker.wave.2.fill"
        case .idle: return "mic.fill"
        }
    }
    
    private var isDisabled: Bool {
        state == .transcribing || state == .thinking || state == .streaming || state == .speaking
    }
}

// MARK: - Message views

struct MessageBubble: View {
    let message: ChatMessage
    
    var isUser: Bool { message.role == .user }
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    Text("🐙")
                        .font(.caption)
                }
                
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(isUser ? .white : .primary)
                    .cornerRadius(18)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !isUser { Spacer() }
        }
    }
}

struct StatusBubble: View {
    let text: String
    let icon: String
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .symbolEffect(.pulse)
                Text(text)
                    .font(.subheadline)
                TypingDotsView()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemGray5))
            .cornerRadius(18)
            
            Spacer()
        }
    }
}

struct TypingDotsView: View {
    @State private var activeDot = 0
    
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.blue.opacity(index == activeDot ? 1.0 : 0.35))
                    .frame(width: 8, height: 8)
                    .offset(y: index == activeDot ? -4 : 0)
                    .animation(.easeInOut(duration: 0.3), value: activeDot)
            }
        }
        .onReceive(timer) { _ in
            activeDot = (activeDot + 1) % 3
        }
    }
}

#Preview {
    ChatView()
        .environment(AppSettings())
        .preferredColorScheme(.dark)
}
