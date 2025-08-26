import UIKit
import Foundation

// Wrapper to make UIImage identifiable for navigation
struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

// Wrapper to make video URL identifiable for navigation
struct IdentifiableVideoURL: Identifiable {
    let id = UUID()
    let url: URL
}