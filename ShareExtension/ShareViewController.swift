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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("ShareExtension: viewDidLoad called")
        setupUI()
        loadAndProcessSharedContent()
    }
    
    func setupUI() {
        // Simple background processing UI
        view.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        
        // Container view
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.layer.cornerRadius = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        
        // Checkmark image
        let checkmarkImageView = UIImageView()
        checkmarkImageView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkImageView.tintColor = .systemGreen
        checkmarkImageView.contentMode = .scaleAspectFit
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(checkmarkImageView)
        
        // Message label
        let messageLabel = UILabel()
        messageLabel.text = "Snapzifying!"
        messageLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        messageLabel.textAlignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(messageLabel)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 200),
            container.heightAnchor.constraint(equalToConstant: 130),
            
            checkmarkImageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            checkmarkImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 30),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 40),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 40),
            
            messageLabel.topAnchor.constraint(equalTo: checkmarkImageView.bottomAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        ])
    }
    
    func loadAndProcessSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            self.extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0, userInfo: nil))
            return
        }
        
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, error) in
                    var image: UIImage?
                    
                    if let url = item as? URL {
                        if let data = try? Data(contentsOf: url) {
                            image = UIImage(data: data)
                        }
                    } else if let img = item as? UIImage {
                        image = img
                    } else if let data = item as? Data {
                        image = UIImage(data: data)
                    }
                    
                    if let image = image {
                        // Save the image first
                        self?.saveImageToSharedContainer(image)
                        
                        // Auto-dismiss after 0.3 seconds (very fast)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                        }
                    } else {
                        // Failed to load image
                        self?.extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0, userInfo: nil))
                    }
                }
                break // Only process the first image
            }
        }
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
        
        // Save image with timestamp - use lower compression for faster saving
        let fileName = "shared_\(Date().timeIntervalSince1970).jpg"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        
        if let imageData = image.jpegData(compressionQuality: 0.7) {
            do {
                try imageData.write(to: fileURL)
                NSLog("ShareExtension: Successfully saved image to: \(fileURL.path)")
                
                // Save the filename and flags to UserDefaults for the main app to retrieve
                if let sharedDefaults = UserDefaults(suiteName: "group.com.snapzify.app") {
                    sharedDefaults.set(fileName, forKey: "pendingSharedImage")
                    sharedDefaults.set(true, forKey: "shouldOpenDocument")
                    sharedDefaults.set(Date().timeIntervalSince1970, forKey: "sharedImageTimestamp")
                    sharedDefaults.synchronize()
                    NSLog("ShareExtension: Saved filename and flags to UserDefaults: \(fileName)")
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
    
    
}
