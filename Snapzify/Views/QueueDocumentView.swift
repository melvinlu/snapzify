import SwiftUI

struct QueueDocumentView: View {
    @EnvironmentObject var appState: AppState
    let documents: [Document]
    @State private var currentIndex: Int
    @State private var scrollOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isTranscriptShowing = false // Track transcript state
    @Environment(\.dismiss) private var dismiss
    
    init(documents: [Document], initialIndex: Int = 0) {
        self.documents = documents
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Vertical stack of all documents
                VStack(spacing: 0) {
                    ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                        DocumentContentView(
                            document: document,
                            isActive: index == currentIndex,
                            onTranscriptStateChange: { isShowing in
                                isTranscriptShowing = isShowing
                            }
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .offset(y: -CGFloat(currentIndex) * geometry.size.height + dragOffset)
                .animation(isDragging ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)
                .animation(isDragging ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30)
                        .onChanged { value in
                            // Don't handle vertical drags if transcript is showing
                            guard !isTranscriptShowing else { 
                                print("📍 Ignoring vertical drag - transcript is showing")
                                return 
                            }
                            
                            // Only handle vertical drags
                            let isVertical = abs(value.translation.height) > abs(value.translation.width)
                            
                            if isVertical {
                                if !isDragging {
                                    print("📍 Starting vertical drag in queue")
                                }
                                isDragging = true
                                dragOffset = value.translation.height
                            } else {
                                print("📍 Ignoring horizontal drag in queue - passing to child views")
                            }
                        }
                        .onEnded { value in
                            // Don't handle if transcript is showing
                            guard !isTranscriptShowing else { 
                                isDragging = false
                                dragOffset = 0
                                return 
                            }
                            
                            // Only process if this was a vertical drag
                            let isVertical = abs(value.translation.height) > abs(value.translation.width)
                            
                            if isVertical {
                                isDragging = false
                                let screenHeight = geometry.size.height
                                let threshold = screenHeight * 0.2
                                let velocity = value.predictedEndTranslation.height - value.translation.height
                                
                                // Determine if we should move to next/previous document
                                if value.translation.height < -threshold || velocity < -200 {
                                    // Swipe up - next document
                                    if currentIndex < documents.count - 1 {
                                        currentIndex += 1
                                    }
                                } else if value.translation.height > threshold || velocity > 200 {
                                    // Swipe down - previous document
                                    if currentIndex > 0 {
                                        currentIndex -= 1
                                    }
                                }
                                
                                // Reset drag offset - the animation will handle the transition
                                dragOffset = 0
                                
                                // Update app state
                                if currentIndex < documents.count {
                                    appState.currentQueueIndex = currentIndex
                                    appState.currentQueueDocument = documents[currentIndex]
                                }
                            } else {
                                // Reset if it was a horizontal drag
                                isDragging = false
                                dragOffset = 0
                            }
                        }
                )
                
                // Overlay UI elements
                VStack {
                    HStack {
                        // Back button
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.white)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        .padding()
                        
                        Spacer()
                        
                        // Queue position
                        if documents.count > 1 {
                            Text("\(currentIndex + 1)/\(documents.count)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.black.opacity(0.5)))
                                .padding(.trailing)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// Document content view using shared interaction components
struct DocumentContentView: View {
    let document: Document
    let isActive: Bool
    let onTranscriptStateChange: (Bool) -> Void
    
    var body: some View {
        // Use the shared document interaction view from Components
        DocumentInteractionView(
            document: document, 
            isActive: isActive,
            onTranscriptStateChange: onTranscriptStateChange
        )
    }
}