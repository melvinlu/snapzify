import SwiftUI

struct QueueDocumentView: View {
    @EnvironmentObject var appState: AppState
    let documents: [Document]
    @State private var currentIndex: Int
    @State private var scrollOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var showingTranscript = false // Track transcript state
    @State private var transcriptDragOffset: CGFloat = 0
    @State private var isDraggingTranscript = false
    @State private var isPopupShowing = false // Track popup state
    @Environment(\.dismiss) private var dismiss
    
    init(documents: [Document], initialIndex: Int = 0) {
        self.documents = documents
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Vertical stack of all documents - each takes exactly full screen
                VStack(spacing: 0) {
                    ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                        DocumentContentView(
                            document: document,
                            isActive: index == currentIndex,
                            onTranscriptRequest: {
                                showingTranscript = true
                            },
                            onPopupStateChanged: { isShowing in
                                isPopupShowing = isShowing
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
                            // Don't handle vertical drags if transcript or popup is showing
                            guard !showingTranscript && !isPopupShowing else { 
                                print("📍 Ignoring vertical drag - transcript (\(showingTranscript)) or popup (\(isPopupShowing)) is showing")
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
                            // Don't handle if transcript or popup is showing
                            guard !showingTranscript && !isPopupShowing else { 
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
                
                // Fullscreen transcript overlay (when active)
                if showingTranscript && currentIndex < documents.count {
                    TranscriptView(
                        document: documents[currentIndex],
                        documentVM: ServiceContainer.shared.makeDocumentViewModel(document: documents[currentIndex])
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemBackground))
                    .offset(x: showingTranscript ? 0 : geometry.size.width + transcriptDragOffset)
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: transcriptDragOffset)
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: showingTranscript)
                    .zIndex(100) // Above everything else
                    .overlay(
                        // Close button for transcript
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                                    showingTranscript = false
                                    isDraggingTranscript = false
                                    transcriptDragOffset = 0
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.width > 0 {
                                    transcriptDragOffset = value.translation.width
                                }
                            }
                            .onEnded { value in
                                let threshold = geometry.size.width * 0.25
                                let velocity = value.predictedEndTranslation.width - value.translation.width
                                
                                withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                                    if value.translation.width > threshold || velocity > 200 {
                                        showingTranscript = false
                                        isDraggingTranscript = false
                                        transcriptDragOffset = 0
                                    } else {
                                        transcriptDragOffset = 0
                                    }
                                }
                            }
                    )
                }
                
                // Overlay UI elements (only show when transcript is not showing)
                if !showingTranscript {
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
                    .zIndex(90) // Below transcript but above documents
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
    let onTranscriptRequest: () -> Void
    let onPopupStateChanged: (Bool) -> Void
    
    var body: some View {
        // Use the shared document interaction view from Components (without transcript)
        DocumentInteractionView(
            document: document, 
            isActive: isActive,
            showTranscript: false, // Never show transcript in child view
            onTranscriptRequest: onTranscriptRequest,
            onPopupStateChanged: onPopupStateChanged
        )
    }
}