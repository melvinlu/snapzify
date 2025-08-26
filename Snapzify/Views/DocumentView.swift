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
            HStack(spacing: T.S.md) {
                // Pleco button
                Button {
                    vm.openInPleco()
                } label: {
                    Label("Pleco", systemImage: "book")
                        .font(.caption)
                }
                .buttonStyle(PopupButtonStyle())
                
                // Audio button
                if vm.isGeneratingAudio || vm.isPreparingAudio {
                    HStack(spacing: 4) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: T.C.accent))
                            .scaleEffect(0.6)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(T.C.ink2)
                    }
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
                
                // ChatGPT button
                Button {
                    showingChatGPTInput = true
                } label: {
                    Label("ChatGPT", systemImage: "message.circle")
                        .font(.caption)
                }
                .buttonStyle(PopupButtonStyle())
                
                Spacer()
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
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: T.S.md) {
            Text("Add context for ChatGPT")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(T.C.ink)
            
            Text("Chinese: \"\(String(chineseText.prefix(50)))\(chineseText.count > 50 ? "..." : "")\"")
                .font(.system(size: 14))
                .foregroundStyle(T.C.ink2)
                .lineLimit(2)
            
            TextField("What would you like to know? (optional)", text: $context, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(2...4)
                .focused($isFocused)
            
            HStack(spacing: T.S.md) {
                Button {
                    isPresented = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(PopupButtonStyle())
                
                Button {
                    openChatGPTWithContext()
                } label: {
                    Text("Open ChatGPT")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(PopupButtonStyle(isActive: true))
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
            // Focus immediately for faster response
            isFocused = true
        }
    }
    
    private func openChatGPTWithContext() {
        let prompt: String
        if context.isEmpty {
            prompt = "Please explain this Chinese text: \(chineseText)"
        } else {
            prompt = "Please explain this Chinese text: \(chineseText)\n\nContext: \(context)"
        }
        
        let encodedPrompt = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Try ChatGPT app first
        if let url = URL(string: "chatgpt://message?prompt=\(encodedPrompt)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } 
        // Fall back to web version
        else if let url = URL(string: "https://chat.openai.com/?q=\(encodedPrompt)") {
            UIApplication.shared.open(url)
        }
        
        isPresented = false
    }
}

struct DocumentView: View {
    @StateObject var vm: DocumentViewModel
    @State private var selectedSentenceId: UUID?
    @State private var showingPopup = false
    @State private var tapLocation: CGPoint = .zero
    @State private var highlightedSentenceId: UUID?
    @State private var showingChatGPTInput = false
    @State private var chatGPTContext = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                
                // Full-screen image with tap detection
                if let imageData = vm.document.imageData,
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
                            
                            // Highlight overlays for all sentences
                            ForEach(vm.document.sentences.filter { $0.rangeInImage != nil }) { sentence in
                                if let rect = sentence.rangeInImage {
                                    Rectangle()
                                        .fill(highlightedSentenceId == sentence.id ? 
                                              Color.green.opacity(0.3) : Color.blue.opacity(0.1))
                                        .overlay(
                                            Rectangle()
                                                .strokeBorder(highlightedSentenceId == sentence.id ? 
                                                            Color.green.opacity(0.8) : Color.blue.opacity(0.4), 
                                                            lineWidth: highlightedSentenceId == sentence.id ? 2 : 1)
                                        )
                                        .frame(width: rect.width * scale,
                                               height: rect.height * scale)
                                        .position(x: rect.midX * scale,
                                                 y: rect.midY * scale)
                                        .animation(.easeInOut(duration: 0.2), value: highlightedSentenceId)
                                }
                            }
                            
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
                                highlightedSentenceId = nil
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
    }
    
    private func handleTextTap(sentence: Sentence, at location: CGPoint) {
        print("🎯 Tapped sentence: id=\(sentence.id), text='\(sentence.text)', english='\(sentence.english ?? "nil")'")
        
        // Find the current sentence data from the document
        if let currentSentence = vm.document.sentences.first(where: { $0.id == sentence.id }) {
            print("🎯 Current sentence data: english='\(currentSentence.english ?? "nil")', pinyin=\(currentSentence.pinyin), status=\(currentSentence.status)")
        } else {
            print("🎯 Could not find sentence in current document")
        }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSentenceId = sentence.id
            highlightedSentenceId = sentence.id
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