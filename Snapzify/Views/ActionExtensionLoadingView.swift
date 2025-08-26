import SwiftUI

struct ActionExtensionLoadingView: View {
    let image: UIImage
    @StateObject private var vm: ActionExtensionLoadingViewModel
    @Binding var navigationPath: NavigationPath
    let onComplete: (Document) -> Void
    @Environment(\.dismiss) private var dismiss
    
    init(image: UIImage, navigationPath: Binding<NavigationPath>, onComplete: @escaping (Document) -> Void) {
        self.image = image
        self._navigationPath = navigationPath
        self.onComplete = onComplete
        self._vm = StateObject(wrappedValue: ActionExtensionLoadingViewModel(
            store: ServiceContainer.shared.documentStore,
            ocrService: ServiceContainer.shared.ocrService,
            scriptConversionService: ServiceContainer.shared.scriptConversionService
        ))
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Thumbnail of the image being processed
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 200)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                
                // Processing status
                VStack(spacing: 12) {
                    Text("Processing Image")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    if let progress = vm.processingProgress {
                        Text(progress)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    // Progress indicator
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                }
                
                // Cancel button
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                }
            }
            .padding()
        }
        .navigationBarHidden(true)
        .task {
            await vm.processImage(image) { document in
                // Call completion handler when processing is done
                onComplete(document)
            }
        }
        .onDisappear {
            vm.cancelProcessing()
        }
    }
}

@MainActor
class ActionExtensionLoadingViewModel: ObservableObject {
    @Published var processingProgress: String?
    @Published var isProcessing = false
    
    private let store: DocumentStore
    private let ocrService: OCRService
    private let scriptConversionService: ScriptConversionService
    private let chineseProcessingService: ChineseProcessingService = ServiceContainer.shared.chineseProcessingService
    private let streamingChineseProcessingService: StreamingChineseProcessingService = ServiceContainer.shared.streamingChineseProcessingService
    @AppStorage("selectedScript") private var selectedScript: String = ChineseScript.simplified.rawValue
    
    private var processingTask: Task<Void, Never>?
    
    init(store: DocumentStore, ocrService: OCRService, scriptConversionService: ScriptConversionService) {
        self.store = store
        self.ocrService = ocrService
        self.scriptConversionService = scriptConversionService
    }
    
    func processImage(_ image: UIImage, onComplete: @escaping (Document) -> Void) async {
        isProcessing = true
        processingProgress = "Recognizing text..."
        
        processingTask = Task { @MainActor in
            do {
                // OCR
                let ocrLines = try await ocrService.recognizeText(in: image)
                guard !Task.isCancelled else { return }
                
                processingProgress = "Segmenting sentences..."
                
                // Segment sentences
                let segmentationService = SentenceSegmentationServiceImpl()
                let sentencesWithRanges = await segmentationService.segmentIntoSentences(from: ocrLines)
                guard !Task.isCancelled else { return }
                
                processingProgress = "Processing \(sentencesWithRanges.count) sentences..."
                
                // Create document with initial sentences
                let imageData = image.jpegData(compressionQuality: 0.8)
                let script = ChineseScript(rawValue: selectedScript) ?? .simplified
                
                var sentences: [Sentence] = sentencesWithRanges.map { sentenceData in
                    Sentence(
                        text: sentenceData.text,
                        rangeInImage: sentenceData.bbox,
                        status: .ocrOnly
                    )
                }
                
                let document = Document(
                    source: .shareExtension,
                    script: script,
                    sentences: sentences,
                    imageData: imageData,
                    isVideo: false,
                    isSaved: false
                )
                
                // Save document
                try await store.save(document)
                guard !Task.isCancelled else { return }
                
                // Process Chinese sentences
                let chineseIndices = sentences.enumerated().compactMap { index, sentence in
                    ChineseDetector.containsChinese(sentence.text) ? index : nil
                }
                
                if !chineseIndices.isEmpty {
                    processingProgress = "Translating..."
                    
                    // Process Chinese sentences
                    let chineseTexts = chineseIndices.map { sentences[$0].text }
                    let processedResults = try await chineseProcessingService.processBatch(
                        chineseTexts,
                        script: script
                    )
                    
                    // Update sentences with processed results
                    for (idx, result) in processedResults.enumerated() {
                        let originalIdx = chineseIndices[idx]
                        sentences[originalIdx].pinyin = result.pinyin
                        sentences[originalIdx].english = result.english
                        sentences[originalIdx].status = .translated
                    }
                    
                    processingProgress = "Translation complete"
                }
                
                // Create final document
                let finalDocument = Document(
                    id: document.id,
                    createdAt: document.createdAt,
                    source: document.source,
                    script: script,
                    sentences: sentences,
                    imageData: imageData,
                    isVideo: false,
                    isSaved: false
                )
                
                // Save and navigate
                try await store.save(finalDocument)
                
                guard !Task.isCancelled else { return }
                
                isProcessing = false
                onComplete(finalDocument)
                
            } catch {
                print("Failed to process action extension image: \(error)")
                isProcessing = false
                processingProgress = "Failed to process image"
            }
        }
        
        await processingTask?.value
    }
    
    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
    }
}