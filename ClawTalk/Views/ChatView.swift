import SwiftUI

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
                            
                            if viewModel.state == .transcribing {
                                StatusBubble(text: "Transcribing...", icon: "waveform")
                            } else if viewModel.state == .thinking {
                                StatusBubble(text: "Thinking...", icon: "brain")
                            } else if viewModel.state == .speaking {
                                StatusBubble(text: "Speaking...", icon: "speaker.wave.2.fill")
                            }
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
                }
                
                Divider()
                
                // Bottom controls
                VStack(spacing: 12) {
                    // Waveform
                    if viewModel.state == .recording {
                        WaveformView(level: viewModel.audioLevel)
                            .frame(height: 40)
                            .padding(.horizontal)
                    }
                    
                    // Mic button
                    HStack {
                        Spacer()
                        
                        VoiceButton(
                            isRecording: viewModel.state == .recording,
                            isDisabled: viewModel.state == .transcribing ||
                                       viewModel.state == .thinking ||
                                       viewModel.state == .speaking,
                            onPress: { viewModel.startRecording() },
                            onRelease: { viewModel.stopAndProcess(settings: settings) }
                        )
                        
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
                }
                .padding(.top, 8)
                .background(Color(.systemBackground))
            }
            .navigationTitle("ClawTalk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        }
    }
}

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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemGray5))
            .cornerRadius(18)
            
            Spacer()
        }
    }
}

#Preview {
    ChatView()
        .environment(AppSettings())
        .preferredColorScheme(.dark)
}
