import UIKit
import UniformTypeIdentifiers
import SwiftUI
import MobileCoreServices

class ActionViewController: UIViewController, ObservableObject {
    
    @Published var isProcessing = true
    @Published var processingStatus = "Saving screenshot..."
    @Published var isDone = false
    
    override func loadView() {
        view = UIView()
        setupUI()
        processSharedContent()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Don't auto-open, let user tap the button
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor.black
        
        let hostingController = UIHostingController(rootView: ActionExtensionView(
            viewController: self,
            onCancel: { [weak self] in
                self?.cancel()
            },
            onOpen: { [weak self] in
                self?.openSnapzify()
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
            showError("Failed to load image")
            return
        }
        processImage(image)
    }
    
    private func processImageFromData(_ data: Data) {
        guard let image = UIImage(data: data) else {
            showError("Failed to process image data")
            return
        }
        processImage(image)
    }
    
    private func processImage(_ image: UIImage) {
        // Save image to app group for main app to process
        guard let imageId = saveImageToAppGroup(image) else {
            isProcessing = false
            processingStatus = "Failed to save screenshot"
            return
        }
        
        print("ActionExtension: Image saved with ID: \(imageId)")
        
        // Save the image ID to shared UserDefaults
        if let userDefaults = UserDefaults(suiteName: "group.com.snapzify") {
            userDefaults.set(imageId, forKey: "pendingImageId")
            userDefaults.set(Date().timeIntervalSince1970, forKey: "pendingImageTimestamp")
            userDefaults.synchronize()
            print("ActionExtension: Saved pending image ID to UserDefaults")
        }
        
        // Store the imageId for later use when opening the app
        self.savedImageId = imageId
        
        // Update UI to show success immediately
        DispatchQueue.main.async {
            self.isProcessing = false
            self.isDone = true
            self.processingStatus = "Ready! Tap Snapzify!"
        }
    }
    
    private var savedImageId: String?
    
    private func saveImageToAppGroup(_ image: UIImage) -> String? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.snapzify"
        ) else { 
            print("ActionExtension: Failed to access app group container")
            return nil
        }
        
        let imagesURL = containerURL.appendingPathComponent("SharedImages")
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: imagesURL.path) {
            do {
                try FileManager.default.createDirectory(
                    at: imagesURL,
                    withIntermediateDirectories: true
                )
            } catch {
                print("ActionExtension: Failed to create images directory: \(error)")
                return nil
            }
        }
        
        // Generate unique ID for this image
        let imageId = UUID().uuidString
        let filename = "\(imageId).png"
        let fileURL = imagesURL.appendingPathComponent(filename)
        
        guard let imageData = image.pngData() else {
            print("ActionExtension: Failed to convert image to PNG data")
            return nil
        }
        
        do {
            try imageData.write(to: fileURL)
            print("ActionExtension: Successfully saved image with ID: \(imageId)")
            return imageId
        } catch {
            print("ActionExtension: Failed to save image: \(error)")
            return nil
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.isProcessing = false
            self.processingStatus = message
        }
    }
    
    private func completeAndOpenApp() {
        print("ActionExtension: Completing extension")
        
        // Just complete the request - the main app will check for pending images
        extensionContext?.completeRequest(returningItems: nil)
    }
    
    private func openMainApp(withImageId imageId: String? = nil) {
        // Legacy method - keeping for compatibility
        completeAndOpenApp()
    }
    
    private func openSnapzify() {
        print("ActionExtension: User tapped Snapzify! button")
        
        let token = savedImageId ?? UUID().uuidString
        tryOpenApp(with: token)
    }
    
    private func tryOpenApp(with token: String) {
        // Build the URL to open the app
        guard let url = URL(string: "snapzify://import?token=\(token)") else {
            print("ActionExtension: Failed to create URL")
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        
        print("ActionExtension: Opening URL: \(url)")
        
        self.extensionContext?.completeRequest(returningItems: nil) { _ in
                DispatchQueue.main.async {
                    self.extensionContext?.open(url, completionHandler: { success in
                        // Optional: log success/failure
                    })
                }
            }
        
        // Action Extensions have better support for opening URLs
        extensionContext?.open(url, completionHandler: { [weak self] success in
            print("ActionExtension: open URL result: \(success)")
            
            if success {
                // Successfully opened the app
                print("ActionExtension: Successfully opened Snapzify app")
            } else {
                // Failed to open, but image is saved
                print("ActionExtension: Could not open app, but image is saved")
            }
            
            // Complete the request to dismiss the extension
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
    }
    
    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "com.snapzify.share",
            code: 0,
            userInfo: nil
        ))
    }
}

struct ActionExtensionView: View {
    @ObservedObject var viewController: ActionViewController
    let onCancel: () -> Void
    let onOpen: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewController.isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    .scaleEffect(1.2)
            } else if viewController.isDone {
                Button {
                    onOpen()
                } label: {
                    Text("Snapzify!")
                        .font(.headline)
                        .frame(width: 200)
                        .padding(.vertical, 12)
                        .background(Color.cyan)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                // Error state - show close button
                Button {
                    onCancel()
                } label: {
                    Text("Close")
                        .foregroundStyle(.gray)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
