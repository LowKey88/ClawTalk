import SwiftUI

struct VoiceButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Circle()
            .fill(buttonColor)
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .symbolEffect(.bounce, value: isRecording)
            )
            .shadow(color: buttonColor.opacity(0.4), radius: isRecording ? 20 : 8)
            .scaleEffect(isPressed ? 1.15 : 1.0)
            .animation(.spring(response: 0.3), value: isPressed)
            .opacity(isDisabled ? 0.5 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isDisabled && !isPressed else { return }
                        isPressed = true
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        onPress()
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        onRelease()
                    }
            )
    }
    
    private var buttonColor: Color {
        if isDisabled { return .gray }
        if isRecording { return .red }
        return .blue
    }
}

#Preview {
    VStack(spacing: 40) {
        VoiceButton(isRecording: false, isDisabled: false, onPress: {}, onRelease: {})
        VoiceButton(isRecording: true, isDisabled: false, onPress: {}, onRelease: {})
        VoiceButton(isRecording: false, isDisabled: true, onPress: {}, onRelease: {})
    }
    .preferredColorScheme(.dark)
}
