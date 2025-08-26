import Foundation
import SwiftUI

// MARK: - Pagination State
enum PaginationState {
    case idle
    case loading
    case hasMore
    case completed
    case error(Error)
    
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
    
    var canLoadMore: Bool {
        switch self {
        case .idle, .hasMore: return true
        default: return false
        }
    }
}

// MARK: - Paginated Document Loader
/// Handles paginated loading of documents for better performance
@MainActor
class PaginatedDocumentLoader: ObservableObject {
    @Published var documents: [DocumentMetadata] = []
    @Published var state: PaginationState = .idle
    @Published var currentPage = 0
    
    private let store: DocumentStore
    private let pageSize: Int
    private let preloadThreshold: Int
    private var loadTask: Task<Void, Never>?
    private let cacheManager = DocumentCacheManager.shared
    
    init(
        store: DocumentStore,
        pageSize: Int = Constants.Pagination.defaultPageSize,
        preloadThreshold: Int = Constants.Pagination.preloadThreshold
    ) {
        self.store = store
        self.pageSize = pageSize
        self.preloadThreshold = preloadThreshold
    }
    
    // MARK: - Public Methods
    
    /// Load initial page of documents
    func loadInitialPage() async {
        guard state.canLoadMore else { return }
        
        state = .loading
        documents = []
        currentPage = 0
        
        await loadPage(0)
    }
    
    /// Load next page of documents
    func loadNextPage() async {
        guard state.canLoadMore else { return }
        
        state = .loading
        await loadPage(currentPage + 1)
    }
    
    /// Refresh all loaded documents
    func refresh() async {
        state = .idle
        await loadInitialPage()
    }
    
    /// Check if should load more based on visible item
    func checkLoadMore(for item: DocumentMetadata) {
        guard let index = documents.firstIndex(where: { $0.id == item.id }) else { return }
        
        let remainingItems = documents.count - index
        if remainingItems <= preloadThreshold && state.canLoadMore {
            Task {
                await loadNextPage()
            }
        }
    }
    
    /// Preload document data for visible items
    func preloadDocuments(visibleIds: Set<UUID>) {
        Task {
            for id in visibleIds {
                if cacheManager.getCachedDocument(id) == nil {
                    if let document = try? await store.fetch(id: id) {
                        cacheManager.cacheDocument(document)
                        
                        // Preload thumbnail
                        if let thumbnailURL = document.thumbnailURL,
                           let thumbnailData = try? Data(contentsOf: thumbnailURL),
                           let thumbnail = UIImage(data: thumbnailData) {
                            cacheManager.cacheThumbnail(thumbnail, for: id)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadPage(_ page: Int) async {
        do {
            let offset = page * pageSize
            let newDocuments = try await store.fetchMetadata(
                offset: offset,
                limit: pageSize
            )
            
            if newDocuments.isEmpty {
                state = .completed
            } else {
                if page == 0 {
                    documents = newDocuments
                } else {
                    // Append only unique documents
                    let existingIds = Set(documents.map { $0.id })
                    let uniqueNew = newDocuments.filter { !existingIds.contains($0.id) }
                    documents.append(contentsOf: uniqueNew)
                }
                
                currentPage = page
                state = newDocuments.count < pageSize ? .completed : .hasMore
                
                // Preload thumbnails for first few items
                preloadThumbnails(for: Array(newDocuments.prefix(5)))
            }
        } catch {
            state = .error(error)
            ErrorLogger.shared.log(error, context: "PaginatedDocumentLoader.loadPage")
        }
    }
    
    private func preloadThumbnails(for metadata: [DocumentMetadata]) {
        Task {
            for meta in metadata {
                if let thumbnailURL = meta.thumbnailURL,
                   cacheManager.getCachedThumbnail(for: meta.id) == nil {
                    if let data = try? Data(contentsOf: thumbnailURL),
                       let thumbnail = UIImage(data: data) {
                        cacheManager.cacheThumbnail(thumbnail, for: meta.id)
                    }
                }
            }
        }
    }
    
    deinit {
        loadTask?.cancel()
    }
}

// MARK: - Paginated List View
struct PaginatedDocumentList: View {
    @StateObject private var loader: PaginatedDocumentLoader
    let onSelect: (DocumentMetadata) -> Void
    @State private var visibleIds = Set<UUID>()
    
    init(
        store: DocumentStore,
        onSelect: @escaping (DocumentMetadata) -> Void
    ) {
        self._loader = StateObject(wrappedValue: PaginatedDocumentLoader(store: store))
        self.onSelect = onSelect
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: T.S.md) {
                ForEach(loader.documents) { document in
                    DocumentRow(metadata: document)
                        .onTapGesture {
                            onSelect(document)
                        }
                        .onAppear {
                            visibleIds.insert(document.id)
                            loader.checkLoadMore(for: document)
                        }
                        .onDisappear {
                            visibleIds.remove(document.id)
                        }
                }
                
                // Loading indicator
                if loader.state.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(T.C.ink2)
                    }
                    .padding()
                }
                
                // Error state
                if case .error(let error) = loader.state {
                    VStack(spacing: T.S.sm) {
                        Text("Failed to load documents")
                            .font(.caption)
                            .foregroundStyle(.red)
                        
                        Button("Retry") {
                            Task {
                                await loader.loadNextPage()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
            .padding()
        }
        .refreshable {
            await loader.refresh()
        }
        .task {
            if loader.documents.isEmpty {
                await loader.loadInitialPage()
            }
        }
        .onChange(of: visibleIds) { newValue in
            loader.preloadDocuments(visibleIds: newValue)
        }
    }
}

// MARK: - Document Row Component
private struct DocumentRow: View {
    let metadata: DocumentMetadata
    @State private var thumbnail: UIImage?
    
    var body: some View {
        HStack(spacing: T.S.md) {
            // Thumbnail
            Group {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(T.C.ink.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(metadata.customName ?? formatDate(metadata.createdAt))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(T.C.ink)
                
                HStack {
                    Label("\(metadata.sentenceCount)", systemImage: "text.alignleft")
                        .font(.caption)
                        .foregroundStyle(T.C.ink2)
                    
                    if metadata.isVideo {
                        Label("Video", systemImage: "video")
                            .font(.caption)
                            .foregroundStyle(T.C.ink2)
                    }
                    
                    if metadata.isSaved {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(T.C.accent)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(T.C.ink2)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                .fill(T.C.card)
        )
        .task {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        // Check cache first
        if let cached = DocumentCacheManager.shared.getCachedThumbnail(for: metadata.id) {
            thumbnail = cached
            return
        }
        
        // Load from URL
        Task {
            if let url = metadata.thumbnailURL,
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                await MainActor.run {
                    thumbnail = image
                }
                DocumentCacheManager.shared.cacheThumbnail(image, for: metadata.id)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Store Extension for Pagination
extension DocumentStore {
    func fetchMetadata(offset: Int, limit: Int) async throws -> [DocumentMetadata] {
        // This would need to be implemented in the actual DocumentStore
        // For now, returning a placeholder implementation
        let allMetadata = try await fetchRecentMetadata(limit: offset + limit)
        return Array(allMetadata.dropFirst(offset).prefix(limit))
    }
}