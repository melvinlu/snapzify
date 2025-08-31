import SwiftUI
import AVKit

// Video-specific popup with ChatGPT context input
struct VideoSelectedSentencePopup: View {
    let sentence: Sentence
    @ObservedObject var vm: SentenceViewModel
    @Binding var isShowing: Bool
    let position: CGPoint
    @Binding var showingChatGPTInput: Bool
    @Binding var chatGPTContext: String
    
    var body: some View {
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

struct VideoDocumentView: View {
    @StateObject var vm: DocumentViewModel
    @State private var currentFrameIndex: Int = 0
    @State private var totalFrames: Int = 1
    @State private var videoDuration: TimeInterval = 0
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
    
    private let frameInterval: TimeInterval = 0.2 // Must match extraction interval
    
    var body: some View {
        NavigationStack {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                
                // Video frame viewer
                if let mediaURL = vm.document.mediaURL {
                    let _ = print("📹 VideoDocumentView: Loading video from URL: \(mediaURL)")
                    let _ = print("📹 VideoDocumentView: File exists: \(FileManager.default.fileExists(atPath: mediaURL.path))")
                    VideoFrameViewer(
                        videoURL: mediaURL,
                        sentences: vm.document.sentences,
                        currentFrameIndex: $currentFrameIndex,
                        totalFrames: $totalFrames,
                        videoDuration: $videoDuration,
                        frameInterval: frameInterval,
                        onSentenceTap: handleSentenceTap
                    )
                }
                
                // Popup overlay (behind slider)
                if showingPopup,
                   let sentenceId = selectedSentenceId,
                   let sentence = vm.document.sentences.first(where: { $0.id == sentenceId }) {
                    
                    let _ = print("🔹 Showing popup for sentence: english='\(sentence.english ?? "nil")', pinyin=\(sentence.pinyin)")
                    
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                showingPopup = false
                                // Keep video paused - user needs to tap again to resume
                            }
                        }
                    
                    VideoSelectedSentencePopup(
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
                            // Ensure transcript is closed before dismissing
                            if showingTranscript || isDraggingTranscript {
                                withAnimation(.spring()) {
                                    transcriptDragOffset = 0
                                    isDraggingTranscript = false
                                    showingTranscript = false
                                }
                                // Small delay to allow animation to complete
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    dismiss()
                                }
                            } else {
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
                .zIndex(500) // Ensure navigation bar is always on top
                
                // Frame navigation slider - always on top
                if vm.document.mediaURL != nil && !showingTranscript && !isDraggingTranscript {
                    VStack {
                        Spacer()
                        
                        Slider(
                            value: Binding(
                                get: { Double(currentFrameIndex) },
                                set: { newValue in
                                    currentFrameIndex = Int(newValue)
                                    // Dismiss popup when slider is used
                                    if showingPopup {
                                        withAnimation {
                                            showingPopup = false
                                        }
                                    }
                                }
                            ),
                            in: 0...Double(max(totalFrames - 1, 1)),
                            step: 1
                        )
                        .tint(.white)
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.8))
                    }
                    .zIndex(300) // Higher than popups to ensure it's always interactive
                }
            }
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
        }
        .navigationBarHidden(true)
        .alert("Delete Document", isPresented: $vm.showDeleteImageAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                vm.deleteImage()
            }
        } message: {
            Text("This will delete the document from Snapzify AND permanently delete the original video from your device's photo library. This action cannot be undone.")
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
        .onChange(of: vm.shouldDismiss) { shouldDismiss in
            if shouldDismiss {
                dismiss()
            }
        }
        }  // End NavigationStack
    }
    
    private func handleSentenceTap(_ sentence: Sentence, at location: CGPoint) {
        print("🎯 Tapped sentence in video: text='\(sentence.text)', frame=\(currentFrameIndex)")
        print("🎯 Sentence details:")
        print("🎯   - ID: \(sentence.id)")
        print("🎯   - English: '\(sentence.english ?? "nil")'")
        print("🎯   - Pinyin: \(sentence.pinyin)")
        print("🎯   - Status: \(sentence.status)")
        
        // Always show popup immediately
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSentenceId = sentence.id
            tapLocation = location
            showingPopup = true
        }
        
        // Check if sentence needs translation (either English or pinyin missing)
        if sentence.english == nil || sentence.english == "Generating..." || sentence.pinyin.isEmpty {
            print("🎯 Sentence needs translation (missing English or pinyin), creating view model")
            // Get or create the sentence view model to handle translation
            let sentenceVM = vm.createSentenceViewModel(for: sentence)
            print("🎯 View model created, triggering translation")
            
            // Trigger translation in background
            Task {
                await sentenceVM.translateIfNeeded()
                print("🎯 Translation completed")
            }
        } else {
            print("🎯 Sentence already fully translated (has both English and pinyin)")
        }
    }
}

struct VideoFrameViewer: UIViewRepresentable {
    let videoURL: URL
    let sentences: [Sentence]
    @Binding var currentFrameIndex: Int
    @Binding var totalFrames: Int
    @Binding var videoDuration: TimeInterval
    let frameInterval: TimeInterval
    let onSentenceTap: (Sentence, CGPoint) -> Void
    
    func makeUIView(context: Context) -> VideoFrameUIView {
        let view = VideoFrameUIView()
        view.sentences = sentences
        view.frameInterval = frameInterval
        view.onSentenceTap = onSentenceTap
        
        view.setupVideo(with: videoURL) { duration, frames in
            DispatchQueue.main.async {
                self.videoDuration = duration
                self.totalFrames = frames
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: VideoFrameUIView, context: Context) {
        uiView.showFrame(at: currentFrameIndex)
    }
}

class VideoFrameUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var asset: AVAsset?
    private var imageGenerator: AVAssetImageGenerator?
    private var currentFrameIndex: Int = 0
    
    var sentences: [Sentence] = []
    var frameInterval: TimeInterval = 0.2
    var onSentenceTap: ((Sentence, CGPoint) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupVideo(with url: URL, completion: @escaping (TimeInterval, Int) -> Void) {
        print("📹 VideoFrameUIView: Setting up video with URL: \(url)")
        print("📹 VideoFrameUIView: File exists: \(FileManager.default.fileExists(atPath: url.path))")
        
        asset = AVAsset(url: url)
        
        // Setup player for displaying frames
        player = AVPlayer(url: url)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspect
        
        if let playerLayer = playerLayer {
            layer.addSublayer(playerLayer)
        }
        
        // Pause immediately - we'll seek to show specific frames
        player?.pause()
        
        // Setup image generator for frame extraction
        imageGenerator = AVAssetImageGenerator(asset: asset!)
        imageGenerator?.appliesPreferredTrackTransform = true
        imageGenerator?.requestedTimeToleranceAfter = .zero
        imageGenerator?.requestedTimeToleranceBefore = .zero
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
        
        // Calculate total frames
        Task {
            guard let asset = asset else { return }
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            let totalFrames = Int(ceil(durationSeconds / frameInterval))
            
            print("📹 VideoFrameUIView: Video duration: \(durationSeconds) seconds, total frames: \(totalFrames)")
            
            await MainActor.run {
                completion(durationSeconds, totalFrames)
                // Show first frame
                self.showFrame(at: 0)
            }
        }
    }
    
    func showFrame(at frameIndex: Int) {
        // Allow showing frame 0 even if currentFrameIndex is 0 for initial setup
        if frameIndex == currentFrameIndex && frameIndex != 0 { return }
        
        print("📹 VideoFrameUIView: Showing frame \(frameIndex) (was \(currentFrameIndex))")
        currentFrameIndex = frameIndex
        
        let timeInSeconds = Double(frameIndex) * frameInterval
        let time = CMTime(seconds: timeInSeconds, preferredTimescale: 600)
        
        print("📹 VideoFrameUIView: Seeking to time \(timeInSeconds) seconds")
        // Seek to the specific frame
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        
        guard let player = player else { return }
        let videoRect = playerLayer?.videoRect ?? bounds
        
        // Guard against zero dimensions to prevent NaN
        guard videoRect.width > 0 && videoRect.height > 0 else { return }
        
        // Get actual video dimensions from the player item
        let videoSize: CGSize
        if let item = player.currentItem {
            videoSize = item.presentationSize
        } else {
            // Fallback to a reasonable default if we can't get video size
            videoSize = CGSize(width: 1920, height: 1080)
        }
        
        // Guard against zero video dimensions
        guard videoSize.width > 0 && videoSize.height > 0 else { return }
        
        // Calculate scale based on actual video dimensions
        let scaleX = videoRect.width / videoSize.width
        let scaleY = videoRect.height / videoSize.height
        
        // Calculate current timestamp from frame index
        let currentTimestamp = Double(currentFrameIndex) * frameInterval
        
        for sentence in sentences {
            var rect: CGRect? = nil
            
            // If this is a video with frame appearances, find the appropriate bbox for current frame
            if let appearances = sentence.frameAppearances, !appearances.isEmpty {
                // Find the frame appearance closest to current timestamp
                // We consider a sentence visible if we're within 0.15 seconds (most of a frame)
                for appearance in appearances {
                    if abs(currentTimestamp - appearance.timestamp) <= 0.15 {
                        rect = appearance.bbox
                        break
                    }
                }
                
                // If no frame is close enough to current time, skip this sentence
                if rect == nil {
                    continue
                }
            } else {
                // Fallback to rangeInImage for non-video content
                rect = sentence.rangeInImage
            }
            
            guard let bbox = rect else { continue }
            
            let sentenceFrame = CGRect(
                x: videoRect.minX + bbox.minX * scaleX,
                y: videoRect.minY + bbox.minY * scaleY,
                width: bbox.width * scaleX,
                height: bbox.height * scaleY
            )
            
            if sentenceFrame.contains(location) {
                onSentenceTap?(sentence, location)
                return // Found a sentence, exit
            }
        }
        
        // Tap was not on any sentence - do nothing (no-op)
        // The slider handles frame navigation
    }
    
    deinit {
        // Clean up if needed
    }
}

extension AVPlayerLayer {
    var videoRect: CGRect {
        guard let player = player,
              let currentItem = player.currentItem else {
            return bounds
        }
        
        let presentationSize = currentItem.presentationSize
        let videoAspect = presentationSize.width / presentationSize.height
        let layerAspect = bounds.width / bounds.height
        
        if videoAspect > layerAspect {
            // Video is wider
            let height = bounds.width / videoAspect
            return CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        } else {
            // Video is taller
            let width = bounds.height * videoAspect
            return CGRect(x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
        }
    }
}