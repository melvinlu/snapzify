import SwiftUI

struct ScreenshotProcessingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isAnimating = false
    @State private var shouldDismiss = false
    
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
                
                Text("Processing screenshot...")
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
        .onChange(of: appState.pendingDocument) { document in
            // When document is ready, prepare navigation BEFORE dismissing
            if document != nil && appState.shouldNavigateToDocument {
                // Set the direct navigation document first
                appState.directNavigationDocument = document
                
                // Small delay to ensure navigation is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Now dismiss the processing screen
                    appState.isProcessingScreenshot = false
                }
            }
        }
    }
}