import SwiftUI

struct WaveformView: View {
    let level: Float
    var color: Color = .red
    
    @State private var bars: [CGFloat] = Array(repeating: 0.1, count: 30)
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.8))
                    .frame(width: 4, height: max(4, bars[index] * 40))
            }
        }
        .onChange(of: level) {
            // Shift bars left, add new level on right
            withAnimation(.easeOut(duration: 0.05)) {
                bars.removeFirst()
                bars.append(CGFloat(level) + CGFloat.random(in: -0.1...0.1))
            }
        }
    }
}

#Preview {
    WaveformView(level: 0.5)
        .frame(height: 40)
        .padding()
        .preferredColorScheme(.dark)
}
