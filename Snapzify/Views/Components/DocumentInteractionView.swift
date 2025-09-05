import SwiftUI

// MARK: - Tappable Characters View
struct TappableCharactersView: View {
    let text: String
    @Binding var selectedWords: [String]
    let onCharacterTap: (String, Int) -> Void
    
    var body: some View {
        // Use a custom layout that wraps but keeps individual tap targets
        WrappingHStack(alignment: .leading, spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                let charStr = String(char)
                let isHighlighted = selectedWords.contains(where: { $0.contains(charStr) })
                
                Text(charStr)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isHighlighted ? T.C.accent : T.C.ink)
                    .onTapGesture {
                        // Check if it's a Chinese character
                        if let scalar = charStr.unicodeScalars.first {
                            let value = scalar.value
                            let isChinese = (0x4E00...0x9FFF).contains(value) || 
                                          (0x3400...0x4DBF).contains(value) ||
                                          (0x20000...0x2A6DF).contains(value) ||
                                          (0x2A700...0x2B73F).contains(value) ||
                                          (0x2B740...0x2B81F).contains(value) ||
                                          (0x2B820...0x2CEAF).contains(value) ||
                                          (0xF900...0xFAFF).contains(value) ||
                                          (0x2F800...0x2FA1F).contains(value)
                            
                            if isChinese {
                                onCharacterTap(charStr, index)
                            }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// A wrapping HStack implementation using Layout protocol (iOS 16+)
struct WrappingHStack: Layout {
    var alignment: Alignment = .center
    var spacing: CGFloat = 10
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            alignment: alignment,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            alignment: alignment,
            spacing: spacing
        )
        
        for row in result.rows {
            for element in row.elements {
                let x = element.x + bounds.minX
                let y = element.y + bounds.minY
                element.subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            }
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var rows: [Row] = []
        
        struct Row {
            var elements: [Element] = []
            var height: CGFloat = 0
        }
        
        struct Element {
            var subview: LayoutSubview
            var x: CGFloat
            var y: CGFloat
        }
        
        init(in maxWidth: CGFloat, subviews: Subviews, alignment: Alignment, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var currentRow = Row()
            var width: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && !currentRow.elements.isEmpty {
                    // Move to next row
                    rows.append(currentRow)
                    currentY += currentRow.height + spacing
                    currentRow = Row()
                    currentX = 0
                }
                
                currentRow.elements.append(Element(
                    subview: subview,
                    x: currentX,
                    y: currentY
                ))
                
                currentRow.height = max(currentRow.height, size.height)
                currentX += size.width + spacing
                width = max(width, currentX)
            }
            
            if !currentRow.elements.isEmpty {
                rows.append(currentRow)
            }
            
            if let lastRow = rows.last {
                size = CGSize(
                    width: width - spacing,
                    height: currentY + lastRow.height
                )
            }
        }
    }
}

// MARK: - Selected Sentence Popup with Extend functionality
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
    @State private var selectedWords: [String] = []
    @State private var characterAnalyses: [String: String] = [:]
    @State private var isLoadingCharacter = false
    @State private var characterTask: Task<Void, Never>?
    
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
            // Chinese text (concatenated if extended) - tappable characters
            TappableCharactersView(
                text: concatenatedText,
                selectedWords: $selectedWords,
                onCharacterTap: { char, position in
                    loadCharacterAnalysis(for: char, at: position)
                }
            )
            
            // Show both sentence translation and character analysis
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: T.S.sm) {
                        // Always show sentence translation first
                        if chatGPTBreakdown.isEmpty && isLoadingBreakdown {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Translating...")
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
                        
                        // Show character/word analyses below if any characters are selected
                        if !selectedWords.isEmpty || isLoadingCharacter {
                            Divider()
                                .padding(.vertical, 4)
                            
                            // Show all selected word analyses
                            VStack(alignment: .leading, spacing: T.S.sm) {
                                ForEach(selectedWords, id: \.self) { word in
                                    if let analysis = characterAnalyses[word] {
                                        VStack(alignment: .leading, spacing: 2) {
                                            // Parse the analysis
                                            let lines = analysis.split(separator: "\n")
                                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                                .filter { !$0.isEmpty }
                                            
                                            // Format main word/character breakdown
                                            if lines.count >= 2 {
                                                // Main word: pinyin, definition
                                                let mainText = "\(word): \(lines[0]), \(lines[1])"
                                                Text(mainText)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(T.C.ink)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                
                                                // Only show individual character breakdowns for multi-character words
                                                if word.count > 1 && lines.count > 2 {
                                                    ForEach(Array(lines.dropFirst(2)), id: \.self) { charLine in
                                                        Text("  " + charLine) // Indent character breakdowns
                                                            .font(.system(size: 12))
                                                            .foregroundStyle(T.C.ink2.opacity(0.8))
                                                            .frame(maxWidth: .infinity, alignment: .leading)
                                                    }
                                                }
                                            } else {
                                                // Fallback for single line or unexpected format
                                                Text("\(word): \(analysis)")
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(T.C.ink2)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .id(word) // Add ID for scrolling
                                    }
                                }
                                
                                // Show loading indicator if analyzing
                                if isLoadingCharacter {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Analyzing...")
                                            .font(.system(size: 12))
                                            .foregroundStyle(T.C.ink2)
                                    }
                                    .padding(.horizontal, 4)
                                    .id("loading") // Add ID for scrolling to loading indicator
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
                .onChange(of: selectedWords) { newWords in
                    // Scroll to the latest added word
                    if let lastWord = newWords.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(lastWord, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: isLoadingCharacter) { loading in
                    // Scroll to loading indicator when starting to load
                    if loading {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
            }
            
            // Action buttons
            HStack(alignment: .center, spacing: 0) {
                // Pleco button
                Button {
                    // Pass all sentences except the first (which is vm.sentence) as additional
                    let additionalSentences = sentences.count > 1 ? Array(sentences.dropFirst()) : []
                    vm.openInPleco(additionalSentences: additionalSentences)
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
            // Clear all state when popup appears
            selectedWords.removeAll()
            characterAnalyses.removeAll()
            chatGPTBreakdown = ""
            isLoadingCharacter = false
            characterTask?.cancel()
            breakdownTask?.cancel()
            
            // Load the sentence translation
            loadChatGPTBreakdown()
        }
        .onChange(of: concatenatedText) { _ in
            // Reload breakdown when text changes (i.e., when extended)
            selectedWords.removeAll()
            characterAnalyses.removeAll()
            isLoadingCharacter = false
            characterTask?.cancel()
            breakdownTask?.cancel()
            chatGPTBreakdown = ""
            loadChatGPTBreakdown()
        }
        .onDisappear {
            // Clean up when popup disappears
            breakdownTask?.cancel()
            characterTask?.cancel()
            selectedWords.removeAll()
            characterAnalyses.removeAll()
            chatGPTBreakdown = ""
            isLoadingCharacter = false
            isLoadingBreakdown = false
        }
    }
    
    private func loadCharacterAnalysis(for character: String, at position: Int) {
        guard chatGPTService.isConfigured() else { return }
        
        isLoadingCharacter = true
        
        characterTask = Task {
            var isFirstLine = true
            var fullAnalysis = ""
            var currentWord = character // Start with the single character
            
            do {
                for try await chunk in chatGPTService.streamCharacterAnalysis(character: character, context: concatenatedText, position: position) {
                    if !Task.isCancelled {
                        fullAnalysis += chunk
                        
                        // Check if we've received the first line (the word)
                        if isFirstLine && fullAnalysis.contains("\n") {
                            let lines = fullAnalysis.split(separator: "\n", maxSplits: 1)
                            if let firstLine = lines.first {
                                currentWord = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
                                
                                // Add to selected words if not already there
                                await MainActor.run {
                                    if !selectedWords.contains(currentWord) {
                                        selectedWords.append(currentWord)
                                    }
                                }
                                isFirstLine = false
                            }
                        }
                        
                        // Update the analysis for this word
                        await MainActor.run {
                            let lines = fullAnalysis.split(separator: "\n")
                            if lines.count > 1 {
                                // Skip first line (word), show rest
                                let analysis = lines.dropFirst().joined(separator: "\n")
                                characterAnalyses[currentWord] = analysis
                            }
                        }
                    }
                }
                
                // Final update after stream completes
                await MainActor.run {
                    let lines = fullAnalysis.split(separator: "\n")
                    if lines.count > 1 {
                        let analysis = lines.dropFirst().joined(separator: "\n")
                        if !analysis.isEmpty {
                            characterAnalyses[currentWord] = analysis
                        }
                    } else if !fullAnalysis.isEmpty && !fullAnalysis.contains("\n") {
                        // If we only got one line back (the word), still show it
                        characterAnalyses[currentWord] = "No additional analysis available"
                    }
                }
            } catch {
                await MainActor.run {
                    characterAnalyses[currentWord] = "Error analyzing"
                }
            }
            
            await MainActor.run {
                isLoadingCharacter = false
            }
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

// MARK: - Shared Document Interaction View
// This view provides tap detection, transcript swipe, and popup functionality for documents
struct DocumentInteractionView: View {
    let document: Document
    let isActive: Bool
    let showTranscript: Bool // Whether to show transcript in this view
    let onTranscriptRequest: (() -> Void)? // Callback to request transcript from parent
    let onPopupStateChanged: ((Bool) -> Void)? // Callback to notify popup state changes
    @StateObject private var vm: DocumentViewModel
    @State private var selectedSentenceId: UUID?
    @State private var showingPopup = false
    @State private var tapLocation: CGPoint = .zero
    @State private var showingTranscript = false
    @State private var transcriptDragOffset: CGFloat = 0
    @State private var isDraggingTranscript = false
    @State private var extendedSentenceIds: [UUID] = []
    @State private var showingChatGPTInput = false
    @State private var chatGPTContext = ""
    
    init(document: Document, isActive: Bool = true, showTranscript: Bool = true, onTranscriptRequest: (() -> Void)? = nil, onPopupStateChanged: ((Bool) -> Void)? = nil) {
        self.document = document
        self.isActive = isActive
        self.showTranscript = showTranscript
        self.onTranscriptRequest = onTranscriptRequest
        self.onPopupStateChanged = onPopupStateChanged
        self._vm = StateObject(wrappedValue: ServiceContainer.shared.makeDocumentViewModel(document: document))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                // Document image with tap detection
                if let mediaURL = document.mediaURL,
                   let imageData = try? Data(contentsOf: mediaURL),
                   let uiImage = UIImage(data: imageData) {
                    
                    DocumentImageView(
                        uiImage: uiImage,
                        geometry: geometry,
                        isActive: isActive,
                        showingTranscript: showingTranscript,
                        showingPopup: showingPopup,
                        transcriptDragOffset: $transcriptDragOffset,
                        isDraggingTranscript: $isDraggingTranscript,
                        onTap: handleTap,
                        onTranscriptSwipe: { 
                            if showTranscript {
                                showingTranscript = true
                            } else {
                                // Request transcript from parent (for queue view)
                                print("🎯 Requesting transcript from parent")
                                onTranscriptRequest?()
                            }
                        }
                    )
                }
                
                // Popup overlay with tap-to-dismiss background
                if isActive && showingPopup {
                    // Invisible background to detect taps outside popup
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            print("🔴 Dismissing popup via background tap")
                            showingPopup = false
                            extendedSentenceIds = []
                        }
                        .zIndex(49)
                    
                    if let sentenceId = selectedSentenceId,
                       let sentence = vm.document.sentences.first(where: { $0.id == sentenceId }) {
                        
                        // Build display sentences: original sentence + extended sentences (like DocumentView)
                        let displaySentences = [sentence] + extendedSentenceIds.compactMap { extendedId in
                            vm.document.sentences.first(where: { $0.id == extendedId })
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
                        .id(displaySentences.map { $0.id }) // Force re-render when sentences change
                        .position(x: geometry.size.width / 2,
                                 y: min(tapLocation.y + 150, geometry.size.height - 200))
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(50)
                    }
                }
                
                // Transcript overlay - only if showTranscript is true (for standalone DocumentView)
                if showTranscript && isActive && (showingTranscript || transcriptDragOffset < 0) {
                    // Full-width transcript
                    TranscriptView(
                        document: vm.document,
                        documentVM: vm
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemBackground))
                    .offset(x: showingTranscript ? 0 : geometry.size.width + transcriptDragOffset)
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: transcriptDragOffset)
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: showingTranscript)
                    .zIndex(75) // Ensure transcript appears above popups
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
                
                // ChatGPT input overlay
                if showingChatGPTInput && !chatGPTContext.isEmpty {
                    ChatGPTContextInputPopup(
                        chineseText: chatGPTContext,
                        context: $chatGPTContext,
                        isPresented: $showingChatGPTInput
                    )
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(100)
                }
            }
        }
        .onChange(of: showingPopup) { newValue in
            onPopupStateChanged?(newValue)
        }
    }
    
    private func handleTap(at location: CGPoint, in displaySize: CGSize, imageSize: CGSize, scale: CGFloat) {
        let normalizedX = location.x / displaySize.width
        let normalizedY = location.y / displaySize.height
        
        for sentence in vm.document.sentences {
            if let bbox = sentence.rangeInImage {
                let bboxLeft = bbox.minX / imageSize.width
                let bboxTop = bbox.minY / imageSize.height
                let bboxRight = bbox.maxX / imageSize.width
                let bboxBottom = bbox.maxY / imageSize.height
                
                if normalizedX >= bboxLeft && normalizedX <= bboxRight &&
                   normalizedY >= bboxTop && normalizedY <= bboxBottom {
                    selectedSentenceId = sentence.id
                    tapLocation = location
                    showingPopup = true
                    extendedSentenceIds = []
                    return
                }
            }
        }
    }
}

// MARK: - Document Image View with Gestures
private struct DocumentImageView: View {
    let uiImage: UIImage
    let geometry: GeometryProxy
    let isActive: Bool
    let showingTranscript: Bool
    let showingPopup: Bool
    @Binding var transcriptDragOffset: CGFloat
    @Binding var isDraggingTranscript: Bool
    let onTap: (CGPoint, CGSize, CGSize, CGFloat) -> Void
    let onTranscriptSwipe: () -> Void
    
    var body: some View {
        let imageSize = uiImage.size
        let screenSize = geometry.size
        let scale = min(screenSize.width / imageSize.width,
                        screenSize.height / imageSize.height,
                        1.0)
        let displayWidth = imageSize.width * scale
        let displayHeight = imageSize.height * scale
        
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: displayWidth, height: displayHeight)
            .position(x: screenSize.width / 2, y: screenSize.height / 2)
            .overlay(
                GeometryReader { imageGeometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard isActive else { return }
                            onTap(location, imageGeometry.size, imageSize, scale)
                        }
                }
            )
            .simultaneousGesture(
                isActive && !showingTranscript ?
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        // Block all gestures if popup is showing
                        guard !showingPopup else {
                            print("🚫 Blocking gesture - popup is showing")
                            return
                        }
                        
                        // Handle horizontal swipe for transcript - prioritize horizontal over vertical
                        let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                        
                        if isHorizontal && value.translation.width < 0 {
                            // Swipe left - show transcript
                            if !isDraggingTranscript {
                                isDraggingTranscript = true
                                print("🎯 Starting horizontal drag for transcript")
                            }
                            transcriptDragOffset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        // Block all gestures if popup is showing
                        guard !showingPopup else {
                            return
                        }
                        
                        let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                        
                        if isHorizontal {
                            let threshold = geometry.size.width * 0.25
                            let velocity = value.predictedEndTranslation.width - value.translation.width
                            
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                                if -value.translation.width > threshold || velocity < -200 {
                                    print("🎯 Opening transcript via swipe")
                                    onTranscriptSwipe()
                                    transcriptDragOffset = 0
                                } else {
                                    print("🎯 Cancelling transcript swipe")
                                    isDraggingTranscript = false
                                    transcriptDragOffset = 0
                                }
                            }
                        } else {
                            // Reset if it wasn't a horizontal swipe
                            isDraggingTranscript = false
                            transcriptDragOffset = 0
                        }
                    }
                : nil
            )
    }
}