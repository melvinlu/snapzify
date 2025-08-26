import SwiftUI
import AVKit

struct VideoDocumentView: View {
    @StateObject var vm: DocumentViewModel
    @State private var player: AVPlayer?
    @State private var isPlaying = true
    @State private var currentTime: TimeInterval = 0
    @State private var selectedSentenceId: UUID?
    @State private var showingPopup = false
    @State private var tapLocation: CGPoint = .zero
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                
                // Video player with overlay
                if let videoData = vm.document.videoData {
                    VideoPlayerWithOverlay(
                        videoData: videoData,
                        sentences: vm.document.sentences,
                        currentTime: $currentTime,
                        isPlaying: $isPlaying,
                        onSentenceTap: handleSentenceTap
                    )
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
                                isPlaying = true // Resume video
                            }
                        }
                    
                    SelectedSentencePopup(
                        sentence: sentence,
                        vm: vm.createSentenceViewModel(for: sentence),
                        isShowing: $showingPopup,
                        position: tapLocation
                    )
                    .position(x: geometry.size.width / 2,
                             y: min(tapLocation.y + 150, geometry.size.height - 200))
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(100)
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
                                .padding()
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
                                .padding()
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
                                    .padding()
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
            Text("This will delete the document from Snapzify AND permanently delete the original video from your device's photo library. This action cannot be undone.")
        }
        .onChange(of: vm.shouldDismiss) { shouldDismiss in
            if shouldDismiss {
                dismiss()
            }
        }
    }
    
    private func handleSentenceTap(_ sentence: Sentence, at location: CGPoint) {
        print("🎯 Tapped sentence in video: text='\(sentence.text)', timestamp=\(sentence.timestamp ?? -1)")
        
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSentenceId = sentence.id
            tapLocation = location
            showingPopup = true
            isPlaying = false // Pause video when showing popup
        }
    }
}

struct VideoPlayerWithOverlay: UIViewRepresentable {
    let videoData: Data
    let sentences: [Sentence]
    @Binding var currentTime: TimeInterval
    @Binding var isPlaying: Bool
    let onSentenceTap: (Sentence, CGPoint) -> Void
    
    func makeUIView(context: Context) -> VideoPlayerUIView {
        let view = VideoPlayerUIView()
        view.sentences = sentences
        view.onSentenceTap = onSentenceTap
        
        // Save video to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_video_\(UUID().uuidString).mov")
        try? videoData.write(to: tempURL)
        
        view.setupPlayer(with: tempURL)
        return view
    }
    
    func updateUIView(_ uiView: VideoPlayerUIView, context: Context) {
        if isPlaying {
            uiView.play()
        } else {
            uiView.pause()
        }
    }
}

class VideoPlayerUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var highlightLayers: [CALayer] = []
    private var timeObserver: Any?
    private var currentPlaybackTime: TimeInterval = 0
    
    var sentences: [Sentence] = []
    var onSentenceTap: ((Sentence, CGPoint) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupPlayer(with url: URL) {
        player = AVPlayer(url: url)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspect
        
        if let playerLayer = playerLayer {
            layer.addSublayer(playerLayer)
        }
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
        
        // Start playback
        player?.play()
        
        // Observe time to track current playback position for tap detection
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentPlaybackTime = CMTimeGetSeconds(time)
        }
        
        // Loop video
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem
        )
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
        
        for sentence in sentences {
            var rect: CGRect? = nil
            
            // If this is a video with frame appearances, find the appropriate bbox for current time
            if let appearances = sentence.frameAppearances, !appearances.isEmpty {
                // Find the frame appearance closest to current time
                // We consider a sentence visible if we're within 0.15 seconds of a frame where it appears
                for appearance in appearances {
                    if abs(currentPlaybackTime - appearance.timestamp) <= 0.15 {
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
                break
            }
        }
    }
    
    @objc private func playerItemDidReachEnd() {
        player?.seek(to: .zero)
        player?.play()
    }
    
    func play() {
        player?.play()
    }
    
    func pause() {
        player?.pause()
    }
    
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
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