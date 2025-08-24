import UIKit
import UniformTypeIdentifiers
import Vision
import SwiftUI

class ShareViewController: UIViewController, ObservableObject {
    
    private var processingView: ProcessingView?
    private var image: UIImage?
    
    @Published var isProcessing = true
    @Published var processingStatus = "Snapzifying screenshot..."
    @Published var sentenceCount = 0
    
    override func loadView() {
        view = UIView()
        setupUI()
        processSharedContent()
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor(T.C.bg)
        
        let hostingController = UIHostingController(rootView: ShareExtensionView(
            viewController: self,
            onCancel: { [weak self] in
                self?.cancel()
            },
            onOpen: { [weak self] in
                self?.openMainApp()
            }
        ))
        
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        hostingController.didMove(toParent: self)
    }
    
    private func processSharedContent() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            cancel()
            return
        }
        
        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            
            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
                        DispatchQueue.main.async {
                            if let url = item as? URL {
                                self?.processImageFromURL(url)
                            } else if let data = item as? Data {
                                self?.processImageFromData(data)
                            } else if let image = item as? UIImage {
                                self?.processImage(image)
                            }
                        }
                    }
                    return
                }
            }
        }
    }
    
    private func processImageFromURL(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            cancel()
            return
        }
        processImage(image)
    }
    
    private func processImageFromData(_ data: Data) {
        guard let image = UIImage(data: data) else {
            cancel()
            return
        }
        processImage(image)
    }
    
    private func processImage(_ image: UIImage) {
        self.image = image
        
        Task {
            await MainActor.run {
                isProcessing = true
                processingStatus = "Snapzifying screenshot..."
                sentenceCount = 0
            }
            
            do {
                let document = try await performOCR(on: image)
                saveToAppGroup(document)
                
                await MainActor.run {
                    isProcessing = false
                    processingStatus = "Snapzifying complete!"
                    sentenceCount = document.sentences.count
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    processingStatus = "Snapzifying failed"
                    showError(error)
                }
            }
        }
    }
    
    private func performOCR(on image: UIImage) async throws -> Document {
        let ocrService = OCRServiceImpl()
        let scriptConversionService = ScriptConversionServiceImpl()
        let segmentationService = SentenceSegmentationServiceImpl()
        let configService = ConfigServiceImpl()
        let pinyinService = PinyinServiceOpenAI(configService: configService)
        
        let script = ChineseScript.simplified
        
        let ocrLines = try await ocrService.recognizeText(in: image)
        
        let normalizedLines = ocrLines.map { line in
            let normalizedText = script == .simplified ?
                scriptConversionService.toSimplified(line.text) :
                scriptConversionService.toTraditional(line.text)
            return OCRLine(text: normalizedText, bbox: line.bbox, words: line.words)
        }
        
        let sentenceData = await segmentationService.segmentIntoSentences(from: normalizedLines)
        
        var sentences: [Sentence] = []
        for sentenceInfo in sentenceData {
            let tokens = await segmentationService.tokenize(sentenceInfo.text)
            let pinyin = await pinyinService.getPinyinForTokens(tokens, script: script)
            
            let sentence = Sentence(
                text: sentenceInfo.text,
                rangeInImage: sentenceInfo.bbox,
                tokens: tokens,
                pinyin: pinyin,
                status: .ocrOnly
            )
            sentences.append(sentence)
        }
        
        return Document(
            source: .shareExtension,
            script: script,
            sentences: sentences,
            imageData: image.pngData()
        )
    }
    
    private func saveToAppGroup(_ document: Document) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.snapzify"
        ) else { return }
        
        let documentsURL = containerURL.appendingPathComponent("Documents")
        
        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            try? FileManager.default.createDirectory(
                at: documentsURL,
                withIntermediateDirectories: true
            )
        }
        
        let fileURL = documentsURL.appendingPathComponent("\(document.id.uuidString).json")
        
        if let data = try? JSONEncoder().encode(document) {
            try? data.write(to: fileURL)
        }
    }
    
    private func showSuccess() {
    }
    
    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Snapzifying Failed",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.cancel()
        })
        
        present(alert, animated: true)
    }
    
    private func openMainApp() {
        // Create NSUserActivity to trigger app opening
        let activity = NSUserActivity("com.snapzify.share-complete")
        activity.title = "Snapzify Document Ready"
        activity.userInfo = ["action": "refresh-documents"]
        activity.isEligibleForHandoff = false
        
        // Complete request with the activity
        let item = NSExtensionItem()
        item.userInfo = [NSExtensionItemActivityKey: activity]
        
        extensionContext?.completeRequest(returningItems: [item]) { _ in
            // Fallback: try URL scheme
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let url = URL(string: "snapzify://open") {
                    self.extensionContext?.open(url) { success in
                        print("URL scheme result: \(success)")
                    }
                }
            }
        }
    }
    
    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "com.snapzify.share",
            code: 0,
            userInfo: nil
        ))
    }
}

struct ShareExtensionView: View {
    @ObservedObject var viewController: ShareViewController
    let onCancel: () -> Void
    let onOpen: () -> Void
    
    var body: some View {
        RootBackground {
            VStack(spacing: T.S.xl) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 60))
                    .foregroundStyle(T.C.accent)
                    .symbolEffect(.pulse, value: viewController.isProcessing)
                
                VStack(spacing: T.S.sm) {
                    Text("Snapzify")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(T.C.ink)
                    
                    Text(viewController.processingStatus)
                        .font(.subheadline)
                        .foregroundStyle(T.C.ink2)
                    
                    if viewController.sentenceCount > 0 {
                        Text("\(viewController.sentenceCount) sentences detected")
                            .font(.caption)
                            .foregroundStyle(T.C.accent)
                    }
                }
                
                if viewController.isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: T.C.accent))
                        .scaleEffect(1.2)
                } else {
                    VStack(spacing: T.S.md) {
                        Button {
                            onOpen()
                        } label: {
                            Text("Open in Snapzify")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        
                        Button {
                            onCancel()
                        } label: {
                            Text("Done")
                                .foregroundStyle(T.C.ink2)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .padding(40)
        }
        .preferredColorScheme(.dark)
    }
}

struct ProcessingView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor(T.C.bg)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}