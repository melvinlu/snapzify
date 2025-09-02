import SwiftUI

// Structure to hold selected sentence data
struct SelectedSentencePopup: View {
    let sentences: [Sentence]  // Changed to array to support extended sentences
    let allSentences: [Sentence]  // All sentences in document for finding next
    @ObservedObject var vm: SentenceViewModel
    @Binding var isShowing: Bool
    let position: CGPoint
    @Binding var showingChatGPTInput: Bool
    @Binding var chatGPTContext: String
    @Binding var extendedSentenceIds: [UUID]
    @State private var chatGPTBreakdown = ""
    @State private var isLoadingBreakdown = false
    @State private var breakdownTask: Task<Void, Never>?
    
    private let chatGPTService = ServiceContainer.shared.chatGPTService
    
    // Computed property for concatenated text
    private var concatenatedText: String {
        sentences.map { $0.text }.joined(separator: " ")
    }
    
    // Check if we can extend further
    private var canExtend: Bool {
        guard let lastSentence = sentences.last,
              let currentIndex = allSentences.firstIndex(where: { $0.id == lastSentence.id }) else {
            return false
        }
        return currentIndex < allSentences.count - 1
    }
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: T.S.sm) {
            // Chinese text (concatenated if extended)
            Text(concatenatedText)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(T.C.ink)
            
            // ChatGPT breakdown - scrollable and streaming
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if chatGPTBreakdown.isEmpty && isLoadingBreakdown {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading breakdown...")
                                .font(.system(size: 14))
                                .foregroundStyle(T.C.ink2)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    } else if !chatGPTBreakdown.isEmpty {
                        Text(chatGPTBreakdown)
                            .font(.system(size: 14))
                            .foregroundStyle(T.C.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 250)
            
            // Action buttons
            HStack(alignment: .center, spacing: 0) {
                // Pleco button
                Button {
                    vm.openInPleco()
                } label: {
                    Label("Pleco", systemImage: "book")
                        .font(.caption)
                }
                .buttonStyle(PopupButtonStyle())
                
                // Spacing after Pleco
                Spacer().frame(width: T.S.sm)
                
                // Audio button
                if vm.isGeneratingAudio || vm.isPreparingAudio {
                    HStack(spacing: 4) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: T.C.accent))
                            .scaleEffect(0.6)
                        Text("Load")
                            .font(.caption)
                            .foregroundStyle(T.C.ink2)
                            .fixedSize()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(T.C.ink.opacity(0.1))
                    )
                    .fixedSize()
                } else {
                    Button {
                        vm.playOrPauseAudio()
                    } label: {
                        Label(
                            vm.isPlaying ? "Pause" : "Play",
                            systemImage: vm.isPlaying ? "pause.fill" : "play.fill"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(PopupButtonStyle(isActive: vm.isPlaying))
                }
                
                // Spacing
                Spacer().frame(width: T.S.sm)
                
                // Extend button
                if canExtend {
                    Button {
                        extendWithNextSentence()
                    } label: {
                        Label("Extend", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(PopupButtonStyle())
                }
                
                // Push remaining space
                Spacer(minLength: 0)
            }
        }
        .padding(T.S.lg)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(T.C.card)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: 340)
        .onAppear {
            loadChatGPTBreakdown()
        }
        .onChange(of: concatenatedText) { _ in
            // Reload breakdown when text changes (i.e., when extended)
            breakdownTask?.cancel()
            chatGPTBreakdown = ""
            loadChatGPTBreakdown()
        }
        .onDisappear {
            breakdownTask?.cancel()
        }
    }
    
    private func extendWithNextSentence() {
        guard let lastSentence = sentences.last,
              let currentIndex = allSentences.firstIndex(where: { $0.id == lastSentence.id }),
              currentIndex < allSentences.count - 1 else {
            return
        }
        
        let nextSentence = allSentences[currentIndex + 1]
        print("📝 Extending with next sentence: '\(nextSentence.text)'")
        print("📝 Current sentences count: \(sentences.count)")
        print("📝 Extended IDs before: \(extendedSentenceIds)")
        extendedSentenceIds.append(nextSentence.id)
        print("📝 Extended IDs after: \(extendedSentenceIds)")
        // The onChange modifier will detect the change and reload the breakdown
    }
    
    private func loadChatGPTBreakdown() {
        guard chatGPTService.isConfigured() else { return }
        
        print("📝 Loading ChatGPT breakdown for text: '\(concatenatedText)'")
        print("📝 Number of sentences: \(sentences.count)")
        
        isLoadingBreakdown = true
        chatGPTBreakdown = ""
        
        breakdownTask = Task {
            do {
                var isFirstChunk = true
                for try await chunk in chatGPTService.streamBreakdown(chineseText: concatenatedText) {
                    if !Task.isCancelled {
                        await MainActor.run {
                            if isFirstChunk {
                                isLoadingBreakdown = false
                                isFirstChunk = false
                            }
                            chatGPTBreakdown += chunk
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    chatGPTBreakdown = "Error loading breakdown"
                    isLoadingBreakdown = false
                }
            }
        }
    }
}

struct PopupButtonStyle: ButtonStyle {
    var isActive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? .white : T.C.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? T.C.accent : T.C.ink.opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct ChatGPTContextInputPopup: View {
    let chineseText: String
    @Binding var context: String
    @Binding var isPresented: Bool
    @State private var streamedResponse = ""
    @State private var isStreaming = false
    @State private var userPrompt = ""
    @State private var streamTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    
    private let chatGPTService = ServiceContainer.shared.chatGPTService
    
    var body: some View {
        VStack(alignment: .leading, spacing: T.S.md) {
            // Header
            HStack {
                Text("ChatGPT")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(T.C.ink)
                
                Spacer()
                
                Button {
                    streamTask?.cancel()
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(T.C.ink2)
                        .font(.title2)
                }
            }
            
            // Scrollable response area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: T.S.sm) {
                        if streamedResponse.isEmpty && isStreaming {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Prompting...")
                                    .font(.system(size: 14))
                                    .foregroundStyle(T.C.ink2)
                            }
                        } else if !streamedResponse.isEmpty {
                            Text(streamedResponse)
                                .font(.system(size: 14))
                                .foregroundStyle(T.C.ink)
                                .textSelection(.enabled)
                                .id("response")
                        } else {
                            Text("Ask me anything about: \"\(String(chineseText.prefix(50)))\(chineseText.count > 50 ? "..." : "")\"")
                                .font(.system(size: 14))
                                .foregroundStyle(T.C.ink2)
                                .italic()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: streamedResponse) { newValue in
                    // Only auto-scroll to show the latest question when user sends a follow-up
                    if newValue.contains("\n\n**You:**") {
                        let components = newValue.components(separatedBy: "\n\n**You:**")
                        if components.count > 1 {
                            // This is a follow-up question, scroll to show it
                            withAnimation {
                                proxy.scrollTo("response", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 400)
            .padding(T.S.sm)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(T.C.ink.opacity(0.05))
            )
            
            // Input area
            HStack(spacing: T.S.sm) {
                TextField("Ask a follow-up question...", text: $userPrompt, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(1...3)
                    .focused($isFocused)
                    .disabled(isStreaming)
                    .onSubmit {
                        sendCustomPrompt()
                    }
                
                Button {
                    if isStreaming {
                        streamTask?.cancel()
                    } else if !userPrompt.isEmpty {
                        sendCustomPrompt()
                    }
                } label: {
                    if isStreaming {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(userPrompt.isEmpty ? T.C.ink2 : T.C.accent)
                    }
                }
                .font(.title2)
                .disabled(!isStreaming && userPrompt.isEmpty)
            }
        }
        .padding(T.S.lg)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(T.C.card)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: 400, maxHeight: 600)
        .onAppear {
            startInitialBreakdown()
        }
        .onDisappear {
            streamTask?.cancel()
        }
    }
    
    private func startInitialBreakdown() {
        guard chatGPTService.isConfigured() else {
            streamedResponse = "Please configure your OpenAI API key in Settings to use ChatGPT features."
            return
        }
        
        isStreaming = true
        streamedResponse = ""
        
        streamTask = Task {
            do {
                for try await chunk in chatGPTService.streamBreakdown(chineseText: chineseText) {
                    if !Task.isCancelled {
                        await MainActor.run {
                            streamedResponse += chunk
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    streamedResponse = "Error: \(error.localizedDescription)"
                }
            }
            
            await MainActor.run {
                isStreaming = false
            }
        }
    }
    
    private func sendCustomPrompt() {
        guard !userPrompt.isEmpty, chatGPTService.isConfigured() else { return }
        
        let prompt = userPrompt
        userPrompt = ""
        
        isStreaming = true
        streamedResponse += "\n\n**You:** \(prompt)\n\n**ChatGPT:** "
        
        streamTask?.cancel()
        streamTask = Task {
            do {
                for try await chunk in chatGPTService.streamCustomPrompt(chineseText: chineseText, userPrompt: prompt) {
                    if !Task.isCancelled {
                        await MainActor.run {
                            streamedResponse += chunk
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    streamedResponse += "\n\nError: \(error.localizedDescription)"
                }
            }
            
            await MainActor.run {
                isStreaming = false
            }
        }
    }
}

struct DocumentView: View {
    @StateObject var vm: DocumentViewModel
    @State private var selectedSentenceId: UUID?
    @State private var showingPopup = false
    @State private var tapLocation: CGPoint = .zero
    @State private var showingChatGPTInput = false
    @State private var chatGPTContext = ""
    @State private var extendedSentenceIds: [UUID] = []
    @State private var showingRenameAlert = false
    @State private var newDocumentName = ""
    @State private var showingTranscript = false
    @State private var transcriptDragOffset: CGFloat = 0
    @State private var isDraggingTranscript = false
    @State private var dragOffset: CGFloat = 0
    @State private var isNavigatingQueue = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        NavigationStack {
            content
        }
    }
    
    @ViewBuilder
    private var content: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                
                // Full-screen image with tap detection
                if let mediaURL = vm.document.mediaURL,
                   let imageData = try? Data(contentsOf: mediaURL),
                   let uiImage = UIImage(data: imageData) {
                    
                    // Calculate the image size to fit screen like Photos app
                    let imageSize = uiImage.size
                    let screenSize = geometry.size
                    let scale = min(screenSize.width / imageSize.width,
                                   screenSize.height / imageSize.height,
                                   1.0) // Don't scale up, only down if needed
                    let displayWidth = imageSize.width * scale
                    let displayHeight = imageSize.height * scale
                    
                    // Debug logs - commented out for compilation
                    // let _ = print("🖼️ Image original size: \(imageSize)")
                    // let _ = print("📱 Screen size: \(screenSize)")
                    // let _ = print("🔍 Scale factor: \(scale)")
                    // let _ = print("📐 Display size: \(displayWidth) x \(displayHeight)")
                    
                    ZStack {
                        // Main image - display at calculated size, centered
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: displayWidth, height: displayHeight)
                            .position(x: screenSize.width / 2, y: screenSize.height / 2)
                        
                        // Invisible tap areas for each sentence
                        ForEach(vm.document.sentences.filter { $0.rangeInImage != nil }) { sentence in
                            if let rect = sentence.rangeInImage {
                                let tapX = (screenSize.width - displayWidth) / 2 + rect.midX * scale
                                let tapY = (screenSize.height - displayHeight) / 2 + rect.midY * scale
                                
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .frame(width: rect.width * scale,
                                           height: rect.height * scale)
                                    .position(x: tapX, y: tapY)
                                    .onTapGesture {
                                        print("🟡 DEBUG: Tapped on sentence area")
                                        print("🟡 DEBUG: Sentence text: \(sentence.text)")
                                        print("🟡 DEBUG: Tap rect: x=\(tapX), y=\(tapY), w=\(rect.width * scale), h=\(rect.height * scale)")
                                        handleTextTap(sentence: sentence, at: CGPoint(x: tapX, y: tapY))
                                    }
                            }
                        }
                    }
                    .frame(width: screenSize.width, height: screenSize.height)
                    .gesture(
                        !showingTranscript ?
                        DragGesture(minimumDistance: 30)
                            .onChanged { value in
                                // Only handle horizontal swipes
                                if abs(value.translation.width) > abs(value.translation.height) && value.translation.width < 0 {
                                    if !isDraggingTranscript {
                                        isDraggingTranscript = true
                                    }
                                    transcriptDragOffset = value.translation.width
                                }
                            }
                            .onEnded { value in
                                let threshold = geometry.size.width * 0.25
                                let velocity = value.predictedEndTranslation.width - value.translation.width
                                
                                withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                                    if -value.translation.width > threshold || velocity < -200 {
                                        showingTranscript = true
                                        transcriptDragOffset = 0
                                    } else {
                                        showingTranscript = false
                                        isDraggingTranscript = false
                                        transcriptDragOffset = 0
                                    }
                                }
                            }
                        : nil
                    )
                }
                
                
                
                // Popup overlay
                if showingPopup, 
                   let sentenceId = selectedSentenceId,
                   let sentence = vm.document.sentences.first(where: { $0.id == sentenceId }) {
                    
                    // Build the array of sentences including any extended ones
                    let displaySentences = [sentence] + extendedSentenceIds.compactMap { extendedId in
                        vm.document.sentences.first(where: { $0.id == extendedId })
                    }
                    
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                showingPopup = false
                                extendedSentenceIds = []  // Reset extended sentences
                            }
                        }
                    
                    SelectedSentencePopup(
                        sentences: displaySentences,
                        allSentences: vm.document.sentences,
                        vm: vm.createSentenceViewModel(for: sentence),
                        isShowing: $showingPopup,
                        position: tapLocation,
                        showingChatGPTInput: $showingChatGPTInput,
                        chatGPTContext: $chatGPTContext,
                        extendedSentenceIds: $extendedSentenceIds
                    )
                    .id(displaySentences.count) // Force re-render when sentences change
                    .position(x: geometry.size.width / 2,
                             y: min(tapLocation.y + 150, geometry.size.height - 200))
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(100)
                }
                
                // ChatGPT context input popup
                if showingChatGPTInput,
                   let sentenceId = selectedSentenceId,
                   let sentence = vm.document.sentences.first(where: { $0.id == sentenceId }) {
                    
                    // Build concatenated text including extended sentences
                    let concatenatedText = ([sentence] + extendedSentenceIds.compactMap { extendedId in
                        vm.document.sentences.first(where: { $0.id == extendedId })
                    }).map { $0.text }.joined(separator: " ")
                    
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                showingChatGPTInput = false
                            }
                        }
                        .zIndex(200)
                    
                    ChatGPTContextInputPopup(
                        chineseText: concatenatedText,
                        context: $chatGPTContext,
                        isPresented: $showingChatGPTInput
                    )
                    .position(x: geometry.size.width / 2,
                             y: geometry.size.height / 2)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(201)
                }
                
                // Top navigation bar
                VStack {
                    HStack {
                        Button {
                            print("🔴 DEBUG: Back button tapped")
                            print("🔴 DEBUG: showingTranscript = \(showingTranscript)")
                            print("🔴 DEBUG: isDraggingTranscript = \(isDraggingTranscript)")
                            print("🔴 DEBUG: transcriptDragOffset = \(transcriptDragOffset)")
                            
                            // Ensure transcript is closed before dismissing
                            if showingTranscript || isDraggingTranscript || transcriptDragOffset < 0 {
                                print("🔴 DEBUG: Closing transcript first")
                                withAnimation(.spring()) {
                                    transcriptDragOffset = 0
                                    isDraggingTranscript = false
                                    showingTranscript = false
                                }
                                // Small delay to allow animation to complete
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    print("🔴 DEBUG: Now dismissing view")
                                    dismiss()
                                }
                            } else {
                                print("🔴 DEBUG: Dismissing view immediately")
                                dismiss()
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.white)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        
                        Spacer()
                        
                        // Rename button
                        Button {
                            newDocumentName = vm.document.customName ?? ""
                            showingRenameAlert = true
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(.white)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        
                        // Transcript button
                        Button {
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                                showingTranscript = true
                                isDraggingTranscript = true
                                transcriptDragOffset = 0
                            }
                        } label: {
                            Image(systemName: "doc.text")
                                .foregroundColor(.white)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        
                        // Pin/Save button
                        Button {
                            vm.toggleImageSave()
                        } label: {
                            Image(systemName: vm.document.isSaved ? "pin.fill" : "pin")
                                .foregroundStyle(vm.document.isSaved ? T.C.accent : .white)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        
                        // Delete button (if from photos)
                        if vm.document.assetIdentifier != nil {
                            Button {
                                vm.showDeleteImageAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                        }
                    }
                    .padding()
                    
                    Spacer()
                }
                .zIndex(500) // Ensure navigation bar is always on top
            }
            
            // Dynamic transcript view that slides in from right
            if isDraggingTranscript || showingTranscript {
                TranscriptView(
                    document: vm.document, 
                    documentVM: vm
                )
                .frame(width: geometry.size.width)
                .background(Color.black)
                .offset(x: showingTranscript ? 0 : geometry.size.width + transcriptDragOffset)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: transcriptDragOffset)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: showingTranscript)
                .zIndex(200)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.width > 0 {
                                // Swiping right - dismiss transcript
                                transcriptDragOffset = value.translation.width
                            }
                        }
                        .onEnded { value in
                            let threshold = geometry.size.width * 0.25
                            let velocity = value.predictedEndTranslation.width - value.translation.width
                            
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                                if value.translation.width > threshold || velocity > 200 {
                                    // Dismiss transcript
                                    showingTranscript = false
                                    isDraggingTranscript = false
                                    transcriptDragOffset = 0
                                } else {
                                    // Snap back to open position
                                    transcriptDragOffset = 0
                                }
                            }
                        }
                )
            }
            
            // Queue navigation indicator
            if !appState.queueDocuments.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            if let currentIndex = appState.queueDocuments.firstIndex(where: { $0.id == vm.document.id }) {
                                if currentIndex > 0 {
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Text("\(currentIndex + 1)/\(appState.queueDocuments.count)")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                                if currentIndex < appState.queueDocuments.count - 1 {
                                    Image(systemName: "chevron.up")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                        .padding()
                    }
                }
            }
            
        }
        .navigationBarHidden(true)
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    // Only allow vertical swipes if we have queue documents and not already navigating
                    if !appState.queueDocuments.isEmpty && !isNavigatingQueue {
                        // Only respond to vertical swipes (ignore if horizontal swipe is stronger)
                        if abs(value.translation.height) > abs(value.translation.width) * 1.5 {
                            dragOffset = value.translation.height
                        }
                    }
                }
                .onEnded { value in
                    guard !appState.queueDocuments.isEmpty && !isNavigatingQueue else {
                        withAnimation(.spring()) {
                            dragOffset = 0
                        }
                        return
                    }
                    
                    // Lower threshold for easier swiping
                    let threshold: CGFloat = 50
                    let velocity = value.predictedEndTranslation.height - value.translation.height
                    
                    // Only process if it's primarily a vertical swipe
                    if abs(value.translation.height) > abs(value.translation.width) {
                        withAnimation(.spring()) {
                            if value.translation.height > threshold || velocity > 100 {
                                // Swipe down - previous in queue
                                navigateToPreviousInQueue()
                            } else if value.translation.height < -threshold || velocity < -100 {
                                // Swipe up - next in queue
                                navigateToNextInQueue()
                            } else {
                                dragOffset = 0
                            }
                        }
                    } else {
                        withAnimation(.spring()) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .alert("Delete Document", isPresented: $vm.showDeleteImageAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                vm.deleteImage()
            }
        } message: {
            Text("This will delete the document from Snapzify AND permanently delete the original photo from your device's photo library. This action cannot be undone.")
        }
        .alert("Rename Document", isPresented: $showingRenameAlert) {
            TextField("Enter name", text: $newDocumentName)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                vm.renameDocument(newDocumentName)
            }
        } message: {
            Text("Give this document a custom name")
        }
        .task {
            await vm.translateAllPending()
        }
        .task {
            // Start refresh timer if any sentences are not translated
            let hasUntranslated = vm.document.sentences.contains { sentence in
                sentence.status != .translated
            }
            if hasUntranslated {
                vm.startRefreshTimer()
            }
        }
        .onChange(of: vm.shouldDismiss) { shouldDismiss in
            if shouldDismiss {
                dismiss()
            }
        }
    }
    
    private func handleTextTap(sentence: Sentence, at location: CGPoint) {
        print("🎯 DEBUG: handleTextTap called")
        print("🎯 DEBUG: Sentence id=\(sentence.id), text='\(sentence.text)'")
        print("🎯 DEBUG: Current popup state: showingPopup=\(showingPopup)")
        
        // Find the current sentence data from the document
        if let currentSentence = vm.document.sentences.first(where: { $0.id == sentence.id }) {
            print("🎯 DEBUG: Found sentence in document")
            print("🎯 DEBUG: Status='\(currentSentence.status)'")
            
            // Check if sentence needs translation
            if currentSentence.status != .translated {
                print("🎯 DEBUG: Sentence needs translation")
                // Get or create the sentence view model
                let sentenceVM = vm.createSentenceViewModel(for: currentSentence)
            } else {
                print("🎯 DEBUG: Sentence already translated")
            }
        } else {
            print("🎯 DEBUG: ERROR - Could not find sentence in document")
        }
        
        print("🎯 DEBUG: Setting showingPopup to true")
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSentenceId = sentence.id
            tapLocation = location
            extendedSentenceIds = []  // Reset extended sentences when opening new popup
            showingPopup = true
        }
        print("🎯 DEBUG: After animation - showingPopup=\(showingPopup)")
    }
    
    private var documentTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: vm.document.createdAt)
    }
    
    private func navigateToNextInQueue() {
        print("📱 NavigateToNext - Queue docs count: \(appState.queueDocuments.count)")
        print("📱 Current document ID: \(vm.document.id)")
        
        guard let currentIndex = appState.queueDocuments.firstIndex(where: { $0.id == vm.document.id }),
              currentIndex < appState.queueDocuments.count - 1 else {
            print("📱 Cannot navigate next - at end or not found in queue")
            dragOffset = 0
            return
        }
        
        print("📱 Current index: \(currentIndex), navigating to: \(currentIndex + 1)")
        isNavigatingQueue = true
        let nextDocument = appState.queueDocuments[currentIndex + 1]
        appState.currentQueueIndex = currentIndex + 1
        appState.currentQueueDocument = nextDocument
        
        // Update the view model with the new document
        vm.updateDocument(nextDocument)
        
        // Reset offset
        dragOffset = 0
        isNavigatingQueue = false
    }
    
    private func navigateToPreviousInQueue() {
        guard let currentIndex = appState.queueDocuments.firstIndex(where: { $0.id == vm.document.id }),
              currentIndex > 0 else {
            dragOffset = 0
            return
        }
        
        isNavigatingQueue = true
        let previousDocument = appState.queueDocuments[currentIndex - 1]
        appState.currentQueueIndex = currentIndex - 1
        appState.currentQueueDocument = previousDocument
        
        // Update the view model with the new document
        vm.updateDocument(previousDocument)
        
        // Reset offset
        dragOffset = 0
        isNavigatingQueue = false
    }
}