import UIKit
import MobileCoreServices
import UniformTypeIdentifiers
import AVFoundation

class QueueActionViewController: UIViewController {
    
    private var statusLabel: UILabel?
    private var mediaData: Data?
    private var isVideo: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processAndQueueMedia()
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.layer.cornerRadius = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        
        let label = UILabel()
        label.text = "Adding to Queue..."
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        self.statusLabel = label
        
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 200),
            container.heightAnchor.constraint(equalToConstant: 80),
            
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
    }
    
    private func processAndQueueMedia() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            self.done()
            return
        }
        
        for provider in attachments {
            // Check for video first
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] (item, error) in
                    guard let self = self else { return }
                    
                    if let url = item as? URL {
                        if let videoData = try? Data(contentsOf: url) {
                            self.mediaData = videoData
                            self.isVideo = true
                            DispatchQueue.main.async {
                                self.addToQueue()
                            }
                        } else {
                            self.done()
                        }
                    } else {
                        self.done()
                    }
                }
                break
            }
            // Then check for image
            else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, error) in
                    guard let self = self else { return }
                    
                    var imageData: Data?
                    
                    if let url = item as? URL {
                        imageData = try? Data(contentsOf: url)
                    } else if let image = item as? UIImage {
                        imageData = image.jpegData(compressionQuality: 0.8)
                    } else if let data = item as? Data {
                        imageData = data
                    }
                    
                    if let imageData = imageData {
                        self.mediaData = imageData
                        self.isVideo = false
                        DispatchQueue.main.async {
                            self.addToQueue()
                        }
                    } else {
                        self.done()
                    }
                }
                break
            }
        }
    }
    
    private func addToQueue() {
        guard let data = mediaData else {
            print("QueueAction: No media data to queue")
            done()
            return
        }
        
        // Save to shared container queue directory
        guard let sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.snapzify.app"
        ) else {
            print("QueueAction: Failed to get shared container URL")
            done()
            return
        }
        
        print("QueueAction: Got shared container URL: \(sharedContainerURL.path)")
        
        let queueDirectory = sharedContainerURL.appendingPathComponent("QueuedMedia")
        try? FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        
        let fileExtension = isVideo ? "mov" : "jpg"
        let fileName = UUID().uuidString + ".\(fileExtension)"
        let fileURL = queueDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            
            // Add to queue metadata
            addToQueueMetadata(fileName: fileName, isVideo: isVideo, containerURL: sharedContainerURL)
            
            // Update UI to show success
            DispatchQueue.main.async {
                self.statusLabel?.text = "Added to Queue ✓"
                
                // Dismiss after short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.done()
                }
            }
        } catch {
            done()
        }
    }
    
    private func addToQueueMetadata(fileName: String, isVideo: Bool, containerURL: URL) {
        struct QueueItem: Codable {
            let id: String
            let fileName: String
            let isVideo: Bool
            let queuedAt: Date
            let source: String
        }
        
        let queueFileURL = containerURL.appendingPathComponent("mediaQueue.json")
        print("Queue file URL: \(queueFileURL.path)")
        
        // Load existing queue
        var queueItems: [QueueItem] = []
        if let data = try? Data(contentsOf: queueFileURL),
           let items = try? JSONDecoder().decode([QueueItem].self, from: data) {
            queueItems = items
            print("Loaded \(queueItems.count) existing queue items")
        } else {
            print("No existing queue file or failed to load")
        }
        
        // Add new item
        let newItem = QueueItem(
            id: UUID().uuidString,
            fileName: fileName,
            isVideo: isVideo,
            queuedAt: Date(),
            source: "queueActionExtension"
        )
        queueItems.append(newItem)
        print("Adding new item: \(fileName), total items: \(queueItems.count)")
        
        // Save updated queue
        if let data = try? JSONEncoder().encode(queueItems) {
            do {
                try data.write(to: queueFileURL)
                print("Successfully saved queue with \(queueItems.count) items")
            } catch {
                print("Failed to save queue: \(error)")
            }
        } else {
            print("Failed to encode queue items")
        }
    }
    
    private func done() {
        // Return to the host app
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}