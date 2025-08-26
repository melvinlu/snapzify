import UIKit

// Wrapper to make UIImage identifiable for navigation
struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}