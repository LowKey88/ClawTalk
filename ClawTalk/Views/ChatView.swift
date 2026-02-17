import SwiftUI
import Combine

struct ChatView: View {
    @Environment(AppSettings.self) var settings
    @State private var viewModel = ChatViewModel()
    @State private var showSettings = false
    @State private var showClearConfirm = false
    @State private var copiedMessageId: UUID?
    @State private var isConnected: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom header (no circle backgrounds)
                HStack {
                    Button(action: { showClearConfirm = true }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
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
                        HStack(spacing: 5) {
                            if let profile = settings.activeProfile {
                                Text(profile.emoji)
                                Text(profile.name)
                                    .fontWeight(.semibold)
                                Circle()
                                    .fill(isConnected ? .green : Color(.systemGray4))
                                    .frame(width: 7, height: 7)
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
                    
                    Spacer()
                    
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        if viewModel.messages.isEmpty && viewModel.state == .idle {
                            // Empty state
                            VStack(spacing: 16) {
                                Spacer()
                                    .frame(height: 80)
                                Text(settings.activeProfile?.emoji ?? "🤖")
                                    .font(.system(size: 64))
                                Text("Tap the mic to start talking")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        }
                        
                        LazyVStack(spacing: 4) {
                            ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                                // Date separator
                                if index == 0 || !Calendar.current.isDate(message.timestamp, inSameDayAs: viewModel.messages[index - 1].timestamp) {
                                    Text(dateSeparatorText(for: message.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 8)
                                }
                                
                                if !message.content.isEmpty {
                                MessageBubble(
                                    message: message,
                                    botEmoji: settings.activeProfile?.emoji ?? "🤖",
                                    isCopied: copiedMessageId == message.id
                                )
                                .id(message.id)
                                .onLongPressGesture {
                                    UIPasteboard.general.string = message.content
                                    let impact = UINotificationFeedbackGenerator()
                                    impact.notificationOccurred(.success)
                                    copiedMessageId = message.id
                                    // Reset after 1.5s
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        if copiedMessageId == message.id {
                                            copiedMessageId = nil
                                        }
                                    }
                                }
                                } // if !message.content.isEmpty
                            }
                            
                            if viewModel.state != .idle {
                                StatusBubble(text: viewModel.state.displayText, icon: viewModel.state.displayIcon)
                                    .id("status-bubble")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: viewModel.messages.last?.content) {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: viewModel.state) {
                        scrollToBottom(proxy: proxy)
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
                    } else if viewModel.state == .speaking {
                        WaveformView(level: viewModel.speakingLevel, color: .orange)
                            .frame(height: 40)
                            .padding(.horizontal)
                    }
                    
                    // Mic button
                    HStack {
                        Spacer()
                        
                        if settings.isHandsFree {
                            // Hands-free: tap to start/stop listening
                            HandsFreeButton(
                                state: viewModel.state,
                                onTap: {
                                    if viewModel.state == .idle {
                                        viewModel.startHandsFree(settings: settings)
                                    } else if viewModel.state == .recording {
                                        // Force-send recording immediately
                                        viewModel.forceEndRecording(settings: settings)
                                    } else {
                                        // Any other state: stop everything
                                        viewModel.stopAll()
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
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("New Conversation", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    viewModel.clearChat()
                }
            } message: {
                Text("Start a new conversation? Current messages will be cleared.")
            }
            .onAppear {
                viewModel.switchToProfile(settings.activeProfileID)
                checkServerStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Auto-restart listening if hands-free was active but mic died in background
                if settings.isHandsFree && (viewModel.state == .listening || viewModel.state == .recording) {
                    viewModel.stopHandsFree()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.startHandsFree(settings: settings)
                    }
                }
            }
            .onChange(of: settings.activeProfileID) { _, newID in
                // Stop any active recording/listening before switching
                viewModel.stopHandsFree()
                viewModel.switchToProfile(newID)
                checkServerStatus()
            }
        }
    }
    
    private func checkServerStatus() {
        guard let profile = settings.activeProfile,
              !profile.openclawURL.isEmpty else {
            isConnected = false
            return
        }
        let baseURL = profile.openclawURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            isConnected = false
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Bearer \(profile.gatewayToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5
        
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse,
                   (200...499).contains(http.statusCode) && http.statusCode != 401 && http.statusCode != 403 {
                    isConnected = true
                } else {
                    isConnected = false
                }
            } catch {
                isConnected = false
            }
        }
    }
    
    private func dateSeparatorText(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            // Always scroll to status bubble if visible, otherwise last message
            if viewModel.state != .idle {
                proxy.scrollTo("status-bubble", anchor: .bottom)
            } else if let last = viewModel.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
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
        case .streaming, .speaking: return .orange
        case .transcribing, .thinking: return .gray
        case .idle: return .blue
        }
    }
    
    private var iconName: String {
        switch state {
        case .listening: return "ear.fill"
        case .recording: return "arrow.up.circle.fill"
        case .idle: return "mic.fill"
        default: return "stop.fill"  // All other states: stop button
        }
    }
    
    private var isDisabled: Bool {
        false  // Always tappable
    }
}

// MARK: - Message views

struct MessageBubble: View {
    let message: ChatMessage
    var botEmoji: String = "🤖"
    var isCopied: Bool = false
    
    var isUser: Bool { message.role == .user }
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    Text(botEmoji)
                        .font(.caption)
                }
                
                ZStack(alignment: .topTrailing) {
                    Text(message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isUser ? Color.blue : Color(.systemGray5))
                        .foregroundColor(isUser ? .white : .primary)
                        .cornerRadius(18)
                    
                    if isCopied {
                        Text("Copied!")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(8)
                            .offset(y: -10)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3), value: isCopied)
                
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
