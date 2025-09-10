import SwiftUI

struct StreamingTranslationPopup: View {
    let content: String
    let isStreaming: Bool
    let onDismiss: () -> Void
    let onSave: () async -> Void
    
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isStreaming {
                        onDismiss()
                    }
                }
            
            // Popup content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Translation")
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
                    
                    if !isStreaming {
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(T.C.ink2)
                        }
                    }
                }
                .padding()
                
                Divider()
                    .background(T.C.divider)
                
                // Content
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(content.isEmpty && isStreaming ? "Starting translation..." : content)
                            .font(.body)
                            .foregroundStyle(content.isEmpty ? T.C.ink2 : T.C.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .id("bottom")
                    }
                    .onChange(of: content) { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: 400)
                
                // Action buttons
                if !isStreaming && !content.isEmpty {
                    Divider()
                        .background(T.C.divider)
                    
                    HStack(spacing: T.S.md) {
                        Button {
                            onDismiss()
                        } label: {
                            Text("Close")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(T.C.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(T.C.cardElevated)
                                )
                        }
                        
                        Button {
                            Task {
                                await onSave()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                Text("Save")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [T.C.brandStart, T.C.brandEnd],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(T.C.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isStreaming ? T.C.accent : T.C.divider, lineWidth: 1)
            )
            .padding(.horizontal, 30)
            .padding(.vertical, 100)
        }
    }
}