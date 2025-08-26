import Foundation
import Photos
import UIKit

// MARK: - Photo Library Service
/// Handles all interactions with the device's photo library
@MainActor
class PhotoLibraryService {
    
    // MARK: - Latest Asset Info
    struct LatestAssetInfo {
        let timestamp: String
        let asset: PHAsset
        let isNewer: Bool // Whether it's newer than the last processed document
    }
    
    // MARK: - Properties
    
    private let imageManager = PHImageManager.default()
    private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status == .authorized || status == .limited
    }
    
    func checkAuthorizationStatus() -> PHAuthorizationStatus {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return authorizationStatus
    }
    
    // MARK: - Fetch Latest Asset
    
    func fetchLatestAsset(newerThan date: Date? = nil) async -> LatestAssetInfo? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard let latestAsset = assets.firstObject else {
            return nil
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        
        let assetDate = latestAsset.creationDate ?? Date()
        let isNewer = date.map { assetDate > $0 } ?? true
        
        return LatestAssetInfo(
            timestamp: formatter.string(from: assetDate),
            asset: latestAsset,
            isNewer: isNewer
        )
    }
    
    // MARK: - Load Image from Asset
    
    func loadImage(
        from asset: PHAsset,
        targetSize: CGSize = PHImageManagerMaximumSize,
        contentMode: PHImageContentMode = .aspectFit,
        options: PHImageRequestOptions? = nil
    ) async throws -> UIImage {
        let requestOptions = options ?? PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.isSynchronous = false
        
        return try await withCheckedThrowingContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: requestOptions
            ) { image, info in
                if let image = image {
                    continuation.resume(returning: image)
                } else {
                    let error = info?[PHImageErrorKey] as? Error ?? 
                        PhotoLibraryError.failedToLoadAsset
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Load Video from Asset
    
    func loadVideoURL(from asset: PHAsset) async throws -> URL {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        
        return try await withCheckedThrowingContinuation { continuation in
            imageManager.requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, info in
                guard let urlAsset = avAsset as? AVURLAsset else {
                    let error = info?[PHImageErrorKey] as? Error ?? 
                        PhotoLibraryError.failedToLoadAsset
                    continuation.resume(throwing: error)
                    return
                }
                
                continuation.resume(returning: urlAsset.url)
            }
        }
    }
    
    // MARK: - Load Video Data
    
    func loadVideoData(from asset: PHAsset) async throws -> Data {
        let url = try await loadVideoURL(from: asset)
        return try Data(contentsOf: url)
    }
    
    // MARK: - Delete Asset
    
    func deleteAsset(_ asset: PHAsset) async throws {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw PhotoLibraryError.insufficientPermissions
        }
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
        }
    }
    
    func deleteAssetWithIdentifier(_ identifier: String) async throws {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        
        guard let asset = fetchResult.firstObject else {
            throw PhotoLibraryError.assetNotFound
        }
        
        try await deleteAsset(asset)
    }
    
    // MARK: - Batch Operations
    
    func fetchAssets(
        mediaType: PHAssetMediaType? = nil,
        limit: Int? = nil,
        sortDescriptor: NSSortDescriptor? = nil
    ) async -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        
        if let limit = limit {
            fetchOptions.fetchLimit = limit
        }
        
        if let sortDescriptor = sortDescriptor {
            fetchOptions.sortDescriptors = [sortDescriptor]
        }
        
        let assets: PHFetchResult<PHAsset>
        if let mediaType = mediaType {
            assets = PHAsset.fetchAssets(with: mediaType, options: fetchOptions)
        } else {
            assets = PHAsset.fetchAssets(with: fetchOptions)
        }
        
        var result: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            result.append(asset)
        }
        
        return result
    }
    
    // MARK: - Asset Metadata
    
    func getAssetMetadata(_ asset: PHAsset) -> AssetMetadata {
        AssetMetadata(
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            location: asset.location,
            duration: asset.duration,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            mediaType: asset.mediaType,
            mediaSubtypes: asset.mediaSubtypes,
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden
        )
    }
    
    struct AssetMetadata {
        let creationDate: Date?
        let modificationDate: Date?
        let location: CLLocation?
        let duration: TimeInterval
        let pixelWidth: Int
        let pixelHeight: Int
        let mediaType: PHAssetMediaType
        let mediaSubtypes: PHAssetMediaSubtype
        let isFavorite: Bool
        let isHidden: Bool
    }
    
    // MARK: - Thumbnail Generation
    
    func generateThumbnail(
        for asset: PHAsset,
        targetSize: CGSize = Constants.Media.thumbnailSize
    ) async throws -> UIImage {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        
        return try await loadImage(
            from: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        )
    }
    
    // MARK: - Photo Picker Support
    
    func processPickerResult(_ result: PHPickerResult) async throws -> (PHAsset?, Data?) {
        // Try to get the asset identifier first
        if let assetIdentifier = result.assetIdentifier {
            let fetchResult = PHAsset.fetchAssets(
                withLocalIdentifiers: [assetIdentifier],
                options: nil
            )
            if let asset = fetchResult.firstObject {
                return (asset, nil)
            }
        }
        
        // Fall back to loading data directly
        if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
            let image = try await withCheckedThrowingContinuation { continuation in
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let image = object as? UIImage {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: PhotoLibraryError.invalidPickerResult)
                    }
                }
            }
            
            let data = image.jpegData(compressionQuality: Constants.Media.imageCompressionQuality)
            return (nil, data)
        }
        
        throw PhotoLibraryError.invalidPickerResult
    }
}

// MARK: - Photo Library Errors
enum PhotoLibraryError: LocalizedError {
    case insufficientPermissions
    case failedToLoadAsset
    case assetNotFound
    case invalidPickerResult
    case exportFailed
    
    var errorDescription: String? {
        switch self {
        case .insufficientPermissions:
            return "Photo library access denied. Please enable in Settings."
        case .failedToLoadAsset:
            return "Failed to load media from photo library"
        case .assetNotFound:
            return "Media not found in photo library"
        case .invalidPickerResult:
            return "Invalid media selected"
        case .exportFailed:
            return "Failed to export media"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .insufficientPermissions:
            return "Go to Settings > Snapzify > Photos and enable access"
        default:
            return "Please try again"
        }
    }
}