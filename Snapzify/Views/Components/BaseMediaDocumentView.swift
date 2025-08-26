import SwiftUI

// MARK: - Base Media Document View
/// Base view for both image and video documents, eliminating code duplication
struct BaseMediaDocumentView<Content: View>: View {
    @StateObject var vm: DocumentViewModel
    @State private var selectedSentenceId: UUID?
    @State private var showingPopup = false
    @State private var tapLocation: CGPoint = .zero
    @State private var showingChatGPTInput = false
    @State private var chatGPTContext = ""
    @State private var showingRenameAlert = false
    @State private var newDocumentName = ""
    @Environment(\.dismiss) private var dismiss
    
    let content: (GeometryProxy) -> Content
    let onSentenceTap: (Sentence, CGPoint) -> Void
    
    init(
        vm: DocumentViewModel,
        @ViewBuilder content: @escaping (GeometryProxy) -> Content,
        onSentenceTap: @escaping (Sentence, CGPoint) -> Void
    ) {
        self._vm = StateObject(wrappedValue: vm)
        self.content = content
        self.onSentenceTap = onSentenceTap
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                
                // Media content (image or video)
                content(geometry)
                
                // Popup overlay
                if showingPopup {
                    PopupOverlay(
                        selectedSentenceId: $selectedSentenceId,
                        showingPopup: $showingPopup,
                        tapLocation: tapLocation,
                        showingChatGPTInput: $showingChatGPTInput,
                        chatGPTContext: $chatGPTContext,
                        vm: vm,
                        geometry: geometry
                    )
                }
                
                // ChatGPT input overlay
                if showingChatGPTInput {
                    ChatGPTOverlay(
                        selectedSentenceId: $selectedSentenceId,
                        showingChatGPTInput: $showingChatGPTInput,
                        chatGPTContext: $chatGPTContext,
                        vm: vm,
                        geometry: geometry
                    )
                }
                
                // Navigation bar
                VStack {
                    MediaNavigationBar(
                        vm: vm,
                        showingRenameAlert: $showingRenameAlert,
                        newDocumentName: $newDocumentName
                    )
                    
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .mediaDocumentAlerts(
            vm: vm,
            showingRenameAlert: $showingRenameAlert,
            newDocumentName: $newDocumentName
        )
        .task {
            await vm.translateAllPending()
            startRefreshTimerIfNeeded()
        }
        .onChange(of: vm.shouldDismiss) { shouldDismiss in
            if shouldDismiss {
                dismiss()
            }
        }
        .onAppear {
            setupSentenceTapHandler()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupSentenceTapHandler() {
        // Override the onSentenceTap to handle common logic
        let originalHandler = onSentenceTap
        onSentenceTap = { sentence, location in
            handleSentenceTap(sentence: sentence, at: location)
            originalHandler(sentence, location)
        }
    }
    
    private func handleSentenceTap(sentence: Sentence, at location: CGPoint) {
        // Find the current sentence data from the document
        if let currentSentence = vm.document.sentences.first(where: { $0.id == sentence.id }) {
            // Check if sentence needs translation
            if currentSentence.english == nil || 
               currentSentence.english == "Generating..." || 
               currentSentence.pinyin.isEmpty {
                // Get or create the sentence view model to handle translation
                let sentenceVM = vm.createSentenceViewModel(for: currentSentence)
                
                // Trigger translation in background
                Task {
                    await sentenceVM.translateIfNeeded()
                }
            }
        }
        
        withAnimation(.easeInOut(duration: Constants.Animation.quick)) {
            selectedSentenceId = sentence.id
            tapLocation = location
            showingPopup = true
        }
    }
    
    private func startRefreshTimerIfNeeded() {
        // Start refresh timer if any sentences are still generating
        let hasGenerating = vm.document.sentences.contains { sentence in
            sentence.english == "Generating..."
        }
        if hasGenerating {
            vm.startRefreshTimer()
        }
    }
}

// MARK: - Popup Overlay
private struct PopupOverlay: View {
    @Binding var selectedSentenceId: UUID?
    @Binding var showingPopup: Bool
    let tapLocation: CGPoint
    @Binding var showingChatGPTInput: Bool
    @Binding var chatGPTContext: String
    @ObservedObject var vm: DocumentViewModel
    let geometry: GeometryProxy
    
    var body: some View {
        if let sentenceId = selectedSentenceId,
           let sentence = vm.document.sentences.first(where: { $0.id == sentenceId }) {
            
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        showingPopup = false
                    }
                }
                .zIndex(99)
            
            SentencePopup(
                sentence: sentence,
                vm: vm.createSentenceViewModel(for: sentence),
                isShowing: $showingPopup,
                position: tapLocation,
                showingChatGPTInput: $showingChatGPTInput,
                chatGPTContext: $chatGPTContext
            )
            .position(
                x: geometry.size.width / 2,
                y: min(tapLocation.y + 150, geometry.size.height - 200)
            )
            .transition(.scale.combined(with: .opacity))
            .zIndex(100)
        }
    }
}

// MARK: - ChatGPT Overlay
private struct ChatGPTOverlay: View {
    @Binding var selectedSentenceId: UUID?
    @Binding var showingChatGPTInput: Bool
    @Binding var chatGPTContext: String
    @ObservedObject var vm: DocumentViewModel
    let geometry: GeometryProxy
    
    var body: some View {
        if let sentenceId = selectedSentenceId,
           let sentence = vm.document.sentences.first(where: { $0.id == sentenceId }) {
            
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        showingChatGPTInput = false
                    }
                }
                .zIndex(200)
            
            ChatGPTContextInputPopup(
                chineseText: sentence.text,
                context: $chatGPTContext,
                isPresented: $showingChatGPTInput
            )
            .position(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2
            )
            .transition(.scale.combined(with: .opacity))
            .zIndex(201)
        }
    }
}