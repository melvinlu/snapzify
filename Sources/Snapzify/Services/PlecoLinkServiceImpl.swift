import Foundation
import UIKit

class PlecoLinkServiceImpl: PlecoLinkService {
    func buildURL(for sentence: String) -> URL {
        let encoded = sentence.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "plecoapi://x-callback-url/s?q=\(encoded)"
        return URL(string: urlString) ?? URL(string: "plecoapi://")!
    }
    
    func canOpenPleco() -> Bool {
        guard let url = URL(string: "plecoapi://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}