import SwiftUI
import PhotosUI

struct HomeView: View {
    @StateObject var vm: HomeViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    
    var body: some View {
        RootBackground {
            ScrollView {
                VStack(spacing: T.S.lg) {
                    if vm.shouldSuggestLatest, let info = vm.latestInfo {
                        smartBanner(info: info)
                    }
                    
                    if vm.isProcessing {
                        processingIndicator
                    }
                    
                    if let errorMessage = vm.errorMessage {
                        errorBanner(message: errorMessage)
                    }
                    
                    quickActions
                    
                    if !vm.documents.isEmpty {
                        recentDocuments
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Snapzify")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    vm.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(T.C.ink)
                }
            }
        }
        .preferredColorScheme(.dark)
        .photosPicker(
            isPresented: $vm.showPhotoPicker,
            selection: $selectedPhoto,
            matching: .images
        )
        .onChange(of: selectedPhoto) { newValue in
            Task {
                if let newValue {
                    print("Photo selected, loading data...")
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        print("Image loaded successfully, processing...")
                        vm.processPickedImage(image)
                    } else {
                        print("Failed to load image data")
                    }
                    selectedPhoto = nil
                }
            }
        }
        .task {
            await vm.loadDocuments()
        }
        .alert("Clear All History", isPresented: $vm.showClearHistoryAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                vm.confirmClearHistory()
            }
        } message: {
            Text("This will permanently delete all processed screenshots and translations. This action cannot be undone.")
        }
    }
    
    @ViewBuilder
    private func smartBanner(info: HomeViewModel.LatestScreenshotInfo) -> some View {
        HStack(spacing: T.S.md) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(T.C.ink)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Process latest screenshot?")
                    .foregroundStyle(T.C.ink)
                    .font(.headline)
                
                Text("\(info.timestamp) • ~\(info.estimate) sentences detected")
                    .foregroundStyle(T.C.ink2)
                    .font(.subheadline)
            }
            
            Spacer()
            
            Button("Process") {
                vm.processLatest()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(vm.isProcessing)
        }
        .padding()
        .card()
    }
    
    @ViewBuilder
    private var quickActions: some View {
        Button {
            vm.pickScreenshot()
        } label: {
            Label("Import Screenshot", systemImage: "square.and.arrow.down")
                .foregroundStyle(T.C.ink)
        }
        .buttonStyle(SecondaryButtonStyle())
    }
    
    @ViewBuilder
    private var recentDocuments: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            HStack {
                Text("Recent")
                    .font(.title3)
                    .foregroundStyle(T.C.ink)
                
                Spacer()
                
                Button("Clear All") {
                    vm.clearHistory()
                }
                .font(.caption)
                .foregroundStyle(T.C.ink2)
            }
            .padding(.horizontal, T.S.xs)
            
            VStack(spacing: 0) {
                ForEach(vm.documents) { doc in
                    documentRow(doc)
                    
                    if doc.id != vm.documents.last?.id {
                        Divider()
                            .background(T.C.divider.opacity(0.6))
                            .padding(.leading, 78)
                    }
                }
            }
            .card()
        }
    }
    
    @ViewBuilder
    private func documentRow(_ doc: Document) -> some View {
        HStack(spacing: T.S.md) {
            Group {
                if let imageData = doc.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(T.C.outline.opacity(0.3), lineWidth: 0.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "doc.text")
                                .foregroundStyle(T.C.ink2)
                                .font(.title2)
                        )
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(documentTitle(for: doc))
                        .foregroundStyle(T.C.ink)
                        .font(.subheadline)
                        .lineLimit(1)
                    
                    if doc.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(T.C.accent)
                            .font(.caption2)
                    }
                    
                    if doc.isSaved {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(T.C.accent)
                            .font(.caption2)
                    }
                }
                
                Text("\(doc.sentences.count) sentences • \(doc.script == .simplified ? "Simplified" : "Traditional") • \(vm.translatedCount(for: doc)) translated")
                    .foregroundStyle(T.C.ink2)
                    .font(.caption)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundStyle(T.C.ink2)
                .font(.caption)
        }
        .padding(.horizontal, T.S.md)
        .padding(.vertical, T.S.md)
        .contentShape(Rectangle())
        .onTapGesture {
            vm.open(doc)
        }
    }
    
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: T.S.lg) {
            Image(systemName: "photo.stack")
                .font(.system(size: 60))
                .foregroundStyle(T.C.ink2.opacity(0.5))
            
            VStack(spacing: T.S.xs) {
                Text("Easily turn screenshots into deeper understanding!")
                    .font(.headline)
                    .foregroundStyle(T.C.ink)
            }
            
            Button {
                vm.pickScreenshot()
            } label: {
                Label("Import Screenshot", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.vertical, 60)
    }
    
    @ViewBuilder
    private var processingIndicator: some View {
        HStack(spacing: T.S.md) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text("Processing image...")
                .foregroundStyle(T.C.ink2)
                .font(.subheadline)
        }
        .padding()
        .card()
    }
    
    @ViewBuilder
    private func errorBanner(message: String) -> some View {
        HStack(spacing: T.S.md) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.headline)
            
            Text(message)
                .foregroundStyle(.red)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button("Dismiss") {
                vm.errorMessage = nil
            }
            .foregroundStyle(.red)
            .font(.caption.weight(.medium))
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }
    
    private func documentTitle(for doc: Document) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Screenshot • \(formatter.string(from: doc.createdAt))"
    }
}