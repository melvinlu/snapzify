import SwiftUI

// Structure to hold selected sentence data
struct SelectedSentencePopup: View {
    let sentence: Sentence
    @ObservedObject var vm: SentenceViewModel
    @Binding var isShowing: Bool
    let position: CGPoint
    @Binding var showingChatGPTInput: Bool
    @Binding var chatGPTContext: String
    
    var body: some View {
        let _ = print("📱 Popup rendering:")
        let _ = print("📱   - Text: '\(sentence.text)'")
        let _ = print("📱   - English: '\(sentence.english ?? "nil")'")
        let _ = print("📱   - Pinyin count: \(sentence.pinyin.count)")
        let _ = print("📱   - Pinyin: \(sentence.pinyin)")
        let _ = print("📱   - vm.sentence.pinyin: \(vm.sentence.pinyin)")
        let _ = print("📱   - isTranslating: \(vm.isTranslating)")
        
        VStack(alignment: .leading, spacing: T.S.sm) {
            // Chinese text
            Text(sentence.text)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(T.C.ink)
            
            // Pinyin
            if !vm.sentence.pinyin.isEmpty {
                Text(vm.sentence.pinyin.joined(separator: " "))
                    .font(.system(size: 14))
                    .foregroundStyle(T.C.ink2)
            } else if !sentence.pinyin.isEmpty {
                Text(sentence.pinyin.joined(separator: " "))
                    .font(.system(size: 14))
                    .foregroundStyle(T.C.ink2)
            }
            
            // English translation or loading indicator
            if vm.isTranslating {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Translating...")
                        .font(.system(size: 16))
                        .foregroundStyle(T.C.ink2)
                }
            } else if let english = sentence.english, english != "Generating..." {
                Text(english)
                    .font(.system(size: 16))
                    .foregroundStyle(T.C.ink2)
            }
            
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
                
                // Spacing after Audio
                Spacer().frame(width: T.S.sm)
                
                // ChatGPT button
                Button {
                    showingChatGPTInput = true
                } label: {
                    Label("ChatGPT", systemImage: "message.circle")
                        .font(.caption)
                }
                .buttonStyle(PopupButtonStyle())
                
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
    @State private var showingRenameAlert = false
    @State private var newDocumentName = ""
    @State private var showingTranscript = false
    @State private var transcriptDragOffset: CGFloat = 0
    @State private var isDraggingTranscript = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
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
                    
                    // Debug logs
                    let _ = print("🖼️ Image original size: \(imageSize)")
                    let _ = print("📱 Screen size: \(screenSize)")
                    let _ = print("🔍 Scale factor: \(scale)")
                    let _ = print("📐 Display size: \(displayWidth) x \(displayHeight)")
                    
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            // Main image - display at calculated size
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: displayWidth, height: displayHeight)
                            
                            // Invisible tap areas for each sentence
                            ForEach(vm.document.sentences.filter { $0.rangeInImage != nil }) { sentence in
                                if let rect = sentence.rangeInImage {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .contentShape(Rectangle())
                                        .frame(width: rect.width * scale,
                                               height: rect.height * scale)
                                        .position(x: rect.midX * scale,
                                                 y: rect.midY * scale)
                                        .onTapGesture { location in
                                            handleTextTap(sentence: sentence, at: location)
                                        }
                                }
                            }
                        }
                        .frame(width: max(displayWidth, screenSize.width),
                               height: max(displayHeight, screenSize.height))
                    }
                    .frame(width: screenSize.width, height: screenSize.height)
                    .zoomable(min: 1.0, max: 3.0)
                }
                
                // Popup overlay
                if showingPopup, 
                   let sentenceId = selectedSentenceId,
                   let sentence = vm.document.sentences.first(where: { $0.id == sentenceId }) {
                    
                    let _ = print("🔹 Showing popup for sentence: english='\(sentence.english ?? "nil")', pinyin=\(sentence.pinyin)")
                    
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                showingPopup = false
                            }
                        }
                    
                    SelectedSentencePopup(
                        sentence: sentence,
                        vm: vm.createSentenceViewModel(for: sentence),
                        isShowing: $showingPopup,
                        position: tapLocation,
                        showingChatGPTInput: $showingChatGPTInput,
                        chatGPTContext: $chatGPTContext
                    )
                    .position(x: geometry.size.width / 2,
                             y: min(tapLocation.y + 150, geometry.size.height - 200))
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(100)
                }
                
                // ChatGPT context input popup
                if showingChatGPTInput,
                   let sentenceId = selectedSentenceId,
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
                    .position(x: geometry.size.width / 2,
                             y: geometry.size.height / 2)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(201)
                }
                
                // Top navigation bar
                VStack {
                    HStack {
                        Button {
                            dismiss()
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
                            withAnimation(.spring()) {
                                showingTranscript = true
                                isDraggingTranscript = true
                                transcriptDragOffset = -geometry.size.width
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
            }
            
            // Dynamic transcript view that slides in from right
            if isDraggingTranscript || transcriptDragOffset < 0 {
                TranscriptView(document: vm.document, documentVM: vm)
                    .frame(width: geometry.size.width)
                    .background(Color.black)
                    .offset(x: geometry.size.width + transcriptDragOffset)
                    .transition(.move(edge: .trailing))
                    .zIndex(200)
                    .highPriorityGesture(
                        DragGesture()
                            .onChanged { value in
                                // Allow dragging back to the right to dismiss
                                if value.translation.width > 0 {
                                    transcriptDragOffset = -geometry.size.width + value.translation.width
                                }
                            }
                            .onEnded { value in
                                withAnimation(.spring()) {
                                    if value.translation.width > 100 {
                                        // Dismiss if dragged right more than 100 points
                                        transcriptDragOffset = 0
                                        isDraggingTranscript = false
                                        showingTranscript = false
                                    } else {
                                        // Snap back to open position
                                        transcriptDragOffset = -geometry.size.width
                                    }
                                }
                            }
                    )
            }
            
            // Invisible swipe area on the right edge
            HStack {
                Spacer()
                Color.clear
                    .frame(width: 30)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingTranscript = true
                                // Make the offset negative to pull view from right
                                let dragAmount = min(0, value.translation.width)
                                // Limit how far it can be pulled
                                transcriptDragOffset = max(dragAmount, -geometry.size.width)
                            }
                            .onEnded { value in
                                withAnimation(.spring()) {
                                    if value.translation.width < -50 {
                                        // If dragged enough, fully show transcript
                                        transcriptDragOffset = -geometry.size.width
                                        showingTranscript = true
                                    } else {
                                        // Otherwise, hide it
                                        transcriptDragOffset = 0
                                        isDraggingTranscript = false
                                        showingTranscript = false
                                    }
                                }
                            }
                    )
            }
            .ignoresSafeArea()
        }
        .navigationBarHidden(true)
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
            // Start refresh timer if any sentences are still generating
            let hasGenerating = vm.document.sentences.contains { sentence in
                sentence.english == "Generating..."
            }
            if hasGenerating {
                vm.startRefreshTimer()
            }
        }
        .onChange(of: vm.shouldDismiss) { shouldDismiss in
            if shouldDismiss {
                dismiss()
            }
        }
        }  // End NavigationStack
    }
    
    private func handleTextTap(sentence: Sentence, at location: CGPoint) {
        print("🎯 Tapped sentence: id=\(sentence.id), text='\(sentence.text)', english='\(sentence.english ?? "nil")'")
        
        // Find the current sentence data from the document
        if let currentSentence = vm.document.sentences.first(where: { $0.id == sentence.id }) {
            print("🎯 Current sentence data: english='\(currentSentence.english ?? "nil")', pinyin=\(currentSentence.pinyin), status=\(currentSentence.status)")
            
            // Check if sentence needs translation (either English or pinyin missing)
            if currentSentence.english == nil || currentSentence.english == "Generating..." || currentSentence.pinyin.isEmpty {
                print("🎯 Sentence needs translation (missing English or pinyin), creating view model")
                // Get or create the sentence view model to handle translation
                let sentenceVM = vm.createSentenceViewModel(for: currentSentence)
                print("🎯 View model created, triggering translation")
                
                // Trigger translation in background
                Task {
                    await sentenceVM.translateIfNeeded()
                    print("🎯 Translation completed")
                }
            } else {
                print("🎯 Sentence already fully translated (has both English and pinyin)")
            }
        } else {
            print("🎯 Could not find sentence in current document")
        }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSentenceId = sentence.id
            tapLocation = location
            showingPopup = true
        }
    }
    
    private var documentTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: vm.document.createdAt)
    }
}

// Extension to add pinch-to-zoom functionality
extension View {
    func zoomable(min minScale: CGFloat = 1.0, max maxScale: CGFloat = 5.0) -> some View {
        ZoomableView(content: self, minScale: minScale, maxScale: maxScale)
    }
}

struct ZoomableView<Content: View>: UIViewRepresentable {
    let content: Content
    let minScale: CGFloat
    let maxScale: CGFloat
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = maxScale
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        scrollView.addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
        ])
        
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        let parent: ZoomableView
        
        init(_ parent: ZoomableView) {
            self.parent = parent
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            scrollView.subviews.first
        }
    }
}