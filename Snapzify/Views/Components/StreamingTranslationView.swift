import SwiftUI

struct StreamingTranslationView: View {
    let content: String
    let isStreaming: Bool
    
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: T.S.md) {
            // Header
            HStack {
                Text("Translation Results")
                    .font(.headline)
                    .foregroundStyle(T.C.ink)
                
                if isStreaming {
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(T.C.accent)
                                .frame(width: 6, height: 6)
                                .offset(y: animationOffset)
                                .animation(
                                    .easeInOut(duration: 0.5)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.15),
                                    value: animationOffset
                                )
                        }
                    }
                    .onAppear {
                        animationOffset = -3
                    }
                }
                
                Spacer()
            }
            
            // Content
            ScrollViewReader { proxy in
                ScrollView {
                    Text(content.isEmpty && isStreaming ? "Starting translation..." : content)
                        .font(.body)
                        .foregroundStyle(content.isEmpty ? T.C.ink2 : T.C.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("bottom")
                }
                .onChange(of: content) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: 300)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(T.C.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isStreaming ? T.C.accent : T.C.divider, lineWidth: 1)
            )
            
            // Streaming indicator
            if isStreaming {
                Text("Generating response...")
                    .font(.caption)
                    .foregroundStyle(T.C.ink2)
            }
        }
    }
}