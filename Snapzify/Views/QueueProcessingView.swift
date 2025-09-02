import SwiftUI

struct QueueProcessingView: View {
    @EnvironmentObject var appState: AppState
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Loading indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                    .opacity(isAnimating ? 1 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 1)
                            .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
                
                Text("Processing media \(appState.currentQueueItemIndex) of \(appState.totalQueueItems) • \(appState.queueProcessingProgress)%")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(UIColor.systemBackground).opacity(0.95))
            )
        }
        .onAppear {
            isAnimating = true
        }
    }
}