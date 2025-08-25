import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

class ActionViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up a simple UI
        view.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.layer.cornerRadius = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "doc.text.viewfinder")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        
        let label = UILabel()
        label.text = "Opening in Snapzify..."
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 240),
            container.heightAnchor.constraint(equalToConstant: 140),
            
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 30),
            imageView.widthAnchor.constraint(equalToConstant: 50),
            imageView.heightAnchor.constraint(equalToConstant: 50),
            
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 15),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        ])
        
        // Process the image and open the main app
        processAndOpenInApp()
    }
    
    private func processAndOpenInApp() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            self.done()
            return
        }
        
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
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
                        // Save image temporarily and open main app
                        self.saveAndOpenInApp(imageData)
                    } else {
                        self.done()
                    }
                }
                break // Only process first image
            }
        }
    }
    
    private func saveAndOpenInApp(_ imageData: Data) {
        // Save to shared container temporarily
        guard let sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.snapzify.app"
        ) else {
            done()
            return
        }
        
        let tempDirectory = sharedContainerURL.appendingPathComponent("ActionTemp")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        let fileName = "action_\(Date().timeIntervalSince1970).jpg"
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        
        do {
            try imageData.write(to: fileURL)
            
            // Create URL to open main app with the image reference
            if let url = URL(string: "snapzify://process-image?file=\(fileName)") {
                // Open the main app
                DispatchQueue.main.async {
                    self.openURL(url)
                    
                    // Dismiss extension after short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.done()
                    }
                }
            } else {
                done()
            }
        } catch {
            done()
        }
    }
    
    @objc private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                // Use the non-deprecated open method
                application.open(url, options: [:], completionHandler: nil)
                break
            }
            responder = responder?.next
        }
    }
    
    private func done() {
        // Return to the host app
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}