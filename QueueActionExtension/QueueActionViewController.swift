import UIKit
import MobileCoreServices
import UniformTypeIdentifiers
import AVFoundation

class QueueActionViewController: UIViewController {
    
    private var statusLabel: UILabel?
    private var imageView: UIImageView?
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
        
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "plus.square.on.square")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        self.imageView = imageView
        
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
            container.heightAnchor.constraint(equalToConstant: 140),
            
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            imageView.widthAnchor.constraint(equalToConstant: 40),
            imageView.heightAnchor.constraint(equalToConstant: 40),
            
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 15),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
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
            done()
            return
        }
        
        // Update UI
        imageView?.image = UIImage(systemName: isVideo ? "video.fill" : "photo.fill")
        
        // Save to shared container queue directory
        guard let sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.snapzify.app"
        ) else {
            done()
            return
        }
        
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
                self.imageView?.image = UIImage(systemName: "checkmark.circle.fill")
                self.imageView?.tintColor = .systemGreen
                
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
        
        // Load existing queue
        var queueItems: [QueueItem] = []
        if let data = try? Data(contentsOf: queueFileURL),
           let items = try? JSONDecoder().decode([QueueItem].self, from: data) {
            queueItems = items
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
        
        // Save updated queue
        if let data = try? JSONEncoder().encode(queueItems) {
            try? data.write(to: queueFileURL)
        }
    }
    
    private func done() {
        // Return to the host app
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}