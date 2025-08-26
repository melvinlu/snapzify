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
            
            VStack(spacing: 40) {
                Spacer()
                
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
                
                // "Snapzifying!" with percentage
                HStack(spacing: 8) {
                    Text("Snapzifying!")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(vm.processingPercentage)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Cancel button at bottom
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
                .padding(.bottom, 40)
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
    @Published var processingPercentage: String = "0%"
    @Published var isProcessing = false
    
    private let store: DocumentStore
    private let ocrService: OCRService
    private let scriptConversionService: ScriptConversionService
    @AppStorage("selectedScript") private var selectedScript: String = ChineseScript.simplified.rawValue
    
    private var processingTask: Task<Void, Never>?
    
    init(store: DocumentStore, ocrService: OCRService, scriptConversionService: ScriptConversionService) {
        self.store = store
        self.ocrService = ocrService
        self.scriptConversionService = scriptConversionService
    }
    
    func processImage(_ image: UIImage, onComplete: @escaping (Document) -> Void) async {
        isProcessing = true
        processingPercentage = "25%"
        
        processingTask = Task { @MainActor in
            do {
                // OCR
                let ocrLines = try await ocrService.recognizeText(in: image)
                guard !Task.isCancelled else { return }
                
                processingPercentage = "50%"
                
                // Segment sentences
                let segmentationService = SentenceSegmentationServiceImpl()
                let sentencesWithRanges = await segmentationService.segmentIntoSentences(from: ocrLines)
                guard !Task.isCancelled else { return }
                
                processingPercentage = "75%"
                
                // Create document with initial sentences (OCR only)
                let imageData = image.jpegData(compressionQuality: 0.8)
                let script = ChineseScript(rawValue: selectedScript) ?? .simplified
                
                let sentences: [Sentence] = sentencesWithRanges.map { sentenceData in
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
                
                processingPercentage = "100%"
                
                // Save document
                try await store.save(document)
                guard !Task.isCancelled else { return }
                
                // Navigate immediately - translations will happen on the fly in DocumentView
                isProcessing = false
                onComplete(document)
                
            } catch {
                print("Failed to process action extension image: \(error)")
                isProcessing = false
                processingPercentage = "Error"
            }
        }
        
        await processingTask?.value
    }
    
    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
    }
}