//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Melvin Lu on 8/22/25.
//

import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

class ShareViewController: UIViewController {
    
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var snapzifyButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var previewImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    
    var sharedImage: UIImage?
    var sharedURL: URL?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("ShareExtension: viewDidLoad called")
        print("ShareExtension: viewDidLoad called")
        setupUI()
        loadSharedContent()
    }
    
    func setupUI() {
        // Create the UI programmatically since we're not using a storyboard
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        
        // Container view
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.layer.cornerRadius = 16
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.1
        container.layer.shadowOffset = CGSize(width: 0, height: 2)
        container.layer.shadowRadius = 8
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        
        // Title label
        let title = UILabel()
        title.text = "Share to Snapzify"
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)
        
        // Preview image view
        let preview = UIImageView()
        preview.contentMode = .scaleAspectFit
        preview.backgroundColor = .systemGray6
        preview.layer.cornerRadius = 8
        preview.clipsToBounds = true
        preview.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(preview)
        self.previewImageView = preview
        
        // Snapzify button
        let snapButton = UIButton(type: .system)
        snapButton.setTitle("Snapzify!", for: .normal)
        snapButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        snapButton.backgroundColor = .systemBlue
        snapButton.setTitleColor(.white, for: .normal)
        snapButton.layer.cornerRadius = 12
        snapButton.translatesAutoresizingMaskIntoConstraints = false
        snapButton.addTarget(self, action: #selector(snapzifyTapped), for: .touchUpInside)
        container.addSubview(snapButton)
        self.snapzifyButton = snapButton
        
        // Cancel button
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        container.addSubview(cancel)
        self.cancelButton = cancel
        
        // Setup constraints
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 320),
            container.heightAnchor.constraint(equalToConstant: 400),
            
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            
            preview.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
            preview.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            preview.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            preview.heightAnchor.constraint(equalToConstant: 200),
            
            snapButton.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 30),
            snapButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            snapButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            snapButton.heightAnchor.constraint(equalToConstant: 50),
            
            cancel.topAnchor.constraint(equalTo: snapButton.bottomAnchor, constant: 10),
            cancel.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])
    }
    
    func loadSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            return
        }
        
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, error) in
                    if let url = item as? URL {
                        self?.sharedURL = url
                        if let data = try? Data(contentsOf: url),
                           let image = UIImage(data: data) {
                            DispatchQueue.main.async {
                                self?.sharedImage = image
                                self?.previewImageView?.image = image
                            }
                        }
                    } else if let image = item as? UIImage {
                        DispatchQueue.main.async {
                            self?.sharedImage = image
                            self?.previewImageView?.image = image
                        }
                    } else if let data = item as? Data,
                              let image = UIImage(data: data) {
                        DispatchQueue.main.async {
                            self?.sharedImage = image
                            self?.previewImageView?.image = image
                        }
                    }
                }
            }
        }
    }
    
    @objc func snapzifyTapped() {
        NSLog("ShareExtension: Snapzify button tapped")
        print("ShareExtension: Snapzify button tapped")
        
        // Save the image to shared container if available
        if let image = sharedImage {
            NSLog("ShareExtension: Saving image to shared container")
            saveImageToSharedContainer(image)
        } else {
            NSLog("ShareExtension: No image to save")
        }
        
        // Set a flag to indicate the app should open the document
        if let sharedDefaults = UserDefaults(suiteName: "group.com.snapzify.app") {
            sharedDefaults.set(true, forKey: "shouldOpenDocument")
            sharedDefaults.set(Date().timeIntervalSince1970, forKey: "sharedImageTimestamp")
            sharedDefaults.synchronize()
            NSLog("ShareExtension: Set shouldOpenDocument flag and timestamp")
        } else {
            NSLog("ShareExtension: Failed to access UserDefaults")
        }
        
        // Try to open the app
        tryOpeningApp()
    }
    
    @objc func cancelTapped() {
        self.extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0, userInfo: nil))
    }
    
    func saveImageToSharedContainer(_ image: UIImage) {
        // Get shared container
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.snapzify.app") else {
            NSLog("ShareExtension: Failed to get shared container for group.com.snapzify.app")
            print("Failed to get shared container")
            return
        }
        NSLog("ShareExtension: Got shared container URL: \(sharedContainerURL.path)")
        
        // Create images directory if needed
        let imagesDirectory = sharedContainerURL.appendingPathComponent("SharedImages")
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
            NSLog("ShareExtension: Created/verified images directory")
        } catch {
            NSLog("ShareExtension: Error creating directory: \(error)")
        }
        
        // Save image with timestamp
        let fileName = "shared_\(Date().timeIntervalSince1970).jpg"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        
        if let imageData = image.jpegData(compressionQuality: 0.9) {
            do {
                try imageData.write(to: fileURL)
                NSLog("ShareExtension: Successfully saved image to: \(fileURL.path)")
                
                // Save the filename to UserDefaults for the main app to retrieve
                if let sharedDefaults = UserDefaults(suiteName: "group.com.snapzify.app") {
                    sharedDefaults.set(fileName, forKey: "pendingSharedImage")
                    sharedDefaults.synchronize()
                    NSLog("ShareExtension: Saved filename to UserDefaults: \(fileName)")
                } else {
                    NSLog("ShareExtension: Failed to access UserDefaults for group.com.snapzify.app")
                }
            } catch {
                NSLog("ShareExtension: Error saving image: \(error)")
            }
        } else {
            NSLog("ShareExtension: Failed to convert image to JPEG data")
        }
    }
    
    func tryOpeningApp() {
        let ctx = self.extensionContext!

        // 1) Probe http(s)
        ctx.open(URL(string:"https://apple.com")!) { ok in
            NSLog("EXT: open https = \(ok)")   // expect TRUE if host allows opens at all
        }

        // 2) Probe your scheme (built safely)
        var c = URLComponents(); c.scheme="snapzify"; c.host="document"; c.path="/new"
        ctx.open(c.url!) { ok in
            NSLog("EXT: open snapzify = \(ok)") // currently FALSE per your logs
        }
        
            // Build the exact URL your app expects: snapzify://document/new
            var comps = URLComponents()
            comps.scheme = "snapzify"
            comps.host = "document"
            comps.path = "/new"
            guard let url = comps.url else {
                NSLog("EXT: Failed to build deep link")
                return
            }
            NSLog("EXT: About to open URL: \(url.absoluteString)")

            // Strongly capture the extension context before hopping to main
            guard let ctx = self.extensionContext else {
                NSLog("EXT: Missing extensionContext")
                return
            }

            DispatchQueue.main.async {
                ctx.open(url) { success in
                    NSLog("EXT: ctx.open returned success=\(success)")
                    ctx.completeRequest(returningItems: nil, completionHandler: nil)
                }
        }
    }
    
    func showSuccessAndDismiss() {
        // Update UI to show success
        DispatchQueue.main.async {
            // Change button to show success
            self.snapzifyButton?.setTitle("✓ Saved!", for: .normal)
            self.snapzifyButton?.backgroundColor = .systemGreen
            self.snapzifyButton?.isEnabled = false
            
            // Add a label with instructions
            let instructionLabel = UILabel()
            instructionLabel.text = "Open Snapzify app to view"
            instructionLabel.font = .systemFont(ofSize: 14)
            instructionLabel.textColor = .systemGray
            instructionLabel.textAlignment = .center
            instructionLabel.translatesAutoresizingMaskIntoConstraints = false
            
            if let button = self.snapzifyButton {
                button.superview?.addSubview(instructionLabel)
                NSLayoutConstraint.activate([
                    instructionLabel.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 8),
                    instructionLabel.centerXAnchor.constraint(equalTo: button.centerXAnchor)
                ])
            }
            
            // Dismiss after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSLog("ShareExtension: Completing extension")
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }
    }
}
